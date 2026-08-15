import AppKit
import Carbon.HIToolbox
import FeatherCore

/// The editor itself: a TextKit 2 `NSTextView` that drives `FeatherCore.Markup`
/// for every structural edit and lets `MarkdownStyler` paint the result.
///
/// The view never parses markdown on its own; it converts selections to
/// `String.Index` ranges, calls a pure helper, and applies the returned text as
/// one undoable step.
final class MarkdownTextView: NSTextView {
    /// Called on Escape. SwiftUI's `onExitCommand` never fires while a text view
    /// is first responder, so the panel needs this hook to hide itself.
    var onEscape: (() -> Void)?

    /// Typewriter scrolling: keep the caret line near the vertical center while
    /// focus mode is on (spec 5).
    var keepsCaretCentered = false

    /// Shared LeetCode index, so a background refresh reaches every open editor.
    var problems: ProblemIndexProvider? {
        didSet { styler.problems = problems }
    }

    /// One undo manager per note, injected by the host (spec 3.5).
    var noteUndoManager: UndoManager?
    override var undoManager: UndoManager? { noteUndoManager ?? super.undoManager }

    let styler: MarkdownStyler
    private let style: EditorStyle
    /// Retained here: `NSTextLayoutManager` holds its content manager weakly.
    private let contentStorage: NSTextContentStorage
    /// UTF-16 location of a closer this view auto-inserted, while it is still
    /// adjacent to the caret. Enables type-over and paired backspace.
    private var autoPairCloser: Int?
    private var lastCaretLine: Int?

    private static let autoPairs: [Character: Character] = ["(": ")", "[": "]", "\"": "\"", "`": "`"]
    private static let wrapPairs: [Character: Character] = [
        "*": "*", "_": "_", "`": "`", "[": "]", "(": ")", "\"": "\"",
    ]

    // MARK: - Construction

    init(style: EditorStyle, palette: EditorPalette) {
        self.style = style
        self.styler = MarkdownStyler(style: style, palette: palette)

        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.textContainer = container
        self.contentStorage = contentStorage

        super.init(frame: .zero, textContainer: container)
        assert(textLayoutManager != nil, "MarkdownTextView requires the TextKit 2 stack")
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownTextView is created in code, not from a nib")
    }

    private func configure() {
        isEditable = true
        isSelectable = true
        // Rich text stays on because styling lives in the attributes; the user's
        // own font and attribute changes are refused below instead.
        isRichText = true
        importsGraphics = false
        usesFontPanel = false
        usesRuler = false
        isRulerVisible = false
        allowsUndo = true

        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false

        drawsBackground = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        autoresizingMask = [.width]
        textContainerInset = style.insets

        // Links are painted by the styler; AppKit's blue underline would fight it.
        linkTextAttributes = [:]
        typingAttributes = [
            .font: style.bodyFont,
            .foregroundColor: styler.palette.ink,
        ]

        contentStorage.textStorage?.delegate = styler
        styler.caretLineProvider = { [weak self] in self?.caretLine() }
    }

    // MARK: - Text access

    private var storage: NSTextStorage? { contentStorage.textStorage }

    /// Replaces the whole document, keeping the caret where it was if it still fits.
    func setText(_ newText: String) {
        guard newText != string else { return }
        let previous = selectedRange
        string = newText
        let length = (string as NSString).length
        let location = min(previous.location, length)
        setSelectedRange(NSRange(location: location, length: min(previous.length, length - location)))
    }

    func restyleAll() {
        guard let storage else { return }
        styler.restyle(storage, in: nil, caretLine: caretLine())
    }

    // MARK: - Applying pure edits

    /// Runs a `Markup` helper over the current text and selection.
    private func applyMarkup(_ transform: (String, Range<String.Index>) -> EditResult) {
        let text = string
        guard let selection = Range(selectedRange, in: text) else { return }
        let result = transform(text, selection)
        replace(with: result.text, selection: NSRange(result.selection, in: result.text))
    }

    /// Applies `newText` as the smallest possible change, so undo and layout stay
    /// cheap and the whole edit is one undo step.
    private func replace(with newText: String, selection: NSRange, scroll: Bool = true) {
        guard let storage else { return }
        let old = string
        if newText == old {
            setSelectedRange(selection)
            return
        }
        let change = MarkdownTextView.minimalChange(from: old, to: newText)
        guard shouldChangeText(in: change.range, replacementString: change.replacement) else { return }
        storage.replaceCharacters(in: change.range, with: change.replacement)
        didChangeText()
        setSelectedRange(selection)
        if scroll { scrollRangeToVisible(selection) }
    }

    /// The single replacement that turns `old` into `new`, found by trimming the
    /// common prefix and suffix. Ranges are UTF-16, as AppKit expects.
    static func minimalChange(from old: String, to new: String) -> (range: NSRange, replacement: String) {
        let oldUnits = Array(old.utf16)
        let newUnits = Array(new.utf16)

        var prefix = 0
        while prefix < oldUnits.count, prefix < newUnits.count, oldUnits[prefix] == newUnits[prefix] {
            prefix += 1
        }
        // Never split a surrogate pair.
        if prefix < oldUnits.count, UTF16.isTrailSurrogate(oldUnits[prefix]), prefix > 0 { prefix -= 1 }

        var suffix = 0
        while suffix < oldUnits.count - prefix,
              suffix < newUnits.count - prefix,
              oldUnits[oldUnits.count - 1 - suffix] == newUnits[newUnits.count - 1 - suffix] {
            suffix += 1
        }
        if suffix > 0, UTF16.isTrailSurrogate(oldUnits[oldUnits.count - suffix]) { suffix -= 1 }

        let range = NSRange(location: prefix, length: oldUnits.count - prefix - suffix)
        let replacement = String(decoding: newUnits[prefix..<(newUnits.count - suffix)], as: UTF16.self)
        return (range, replacement)
    }

    // MARK: - Key handling

    override func didChangeText() {
        super.didChangeText()
        centerCaretLine()
    }

    /// Scrolls the caret line to the middle of the visible area. No animation is
    /// used, so this needs no Reduce Motion branch.
    private func centerCaretLine() {
        guard keepsCaretCentered,
              let window,
              let clip = enclosingScrollView?.contentView
        else { return }
        let onScreen = firstRect(forCharacterRange: selectedRange, actualRange: nil)
        guard onScreen.height > 0 else { return }
        let caret = convert(window.convertFromScreen(onScreen), from: nil)
        let padding = max(0, (clip.bounds.height - caret.height) / 2)
        scrollToVisible(caret.insetBy(dx: 0, dy: -padding))
    }

    override func insertNewline(_ sender: Any?) {
        applyMarkup { Markup.insertNewline(text: $0, selection: $1) }
    }

    /// Shift-Return: a soft break, with no marker continuation.
    override func insertLineBreak(_ sender: Any?) {
        super.insertText("\n", replacementRange: selectedRange)
    }

    override func insertTab(_ sender: Any?) {
        applyMarkup { Markup.indent(text: $0, selection: $1) }
    }

    override func insertBacktab(_ sender: Any?) {
        applyMarkup { Markup.outdent(text: $0, selection: $1) }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleCommandShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleCommandShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), isEditable else { return false }
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let keyCode = Int(event.keyCode)

        if option {
            switch keyCode {
            case kVK_UpArrow:
                applyMarkup { Markup.moveLine(text: $0, selection: $1, direction: .up) }
                return true
            case kVK_DownArrow:
                applyMarkup { Markup.moveLine(text: $0, selection: $1, direction: .down) }
                return true
            default:
                return false
            }
        }

        if keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter {
            applyMarkup { Markup.toggleCheckbox(text: $0, selection: $1) }
            return true
        }
        if keyCode == kVK_Delete, shift {
            applyMarkup { Markup.deleteLine(text: $0, selection: $1) }
            return true
        }

        if shift {
            // Shift rewrites charactersIgnoringModifiers, so list keys go by key code.
            switch keyCode {
            case kVK_ANSI_7:
                applyMarkup { Markup.setList(text: $0, selection: $1, kind: .ordered) }
                return true
            case kVK_ANSI_8:
                applyMarkup { Markup.setList(text: $0, selection: $1, kind: .bullet) }
                return true
            case kVK_ANSI_9:
                applyMarkup { Markup.setList(text: $0, selection: $1, kind: .checkbox) }
                return true
            default:
                break
            }
        }

        switch (event.charactersIgnoringModifiers ?? "").lowercased() {
        case "b" where !shift:
            applyMarkup { Markup.wrap(text: $0, selection: $1, marker: "**") }
        case "i" where !shift:
            applyMarkup { Markup.wrap(text: $0, selection: $1, marker: "*") }
        case "e" where !shift:
            applyMarkup { Markup.wrap(text: $0, selection: $1, marker: "`") }
        case "x" where shift:
            applyMarkup { Markup.wrap(text: $0, selection: $1, marker: "~~") }
        case "h" where shift:
            applyMarkup { Markup.wrap(text: $0, selection: $1, marker: "==") }
        case "k" where !shift:
            insertLink()
        case "l" where shift:
            // Cmd-Shift-L: turn the references on this line into real markdown links.
            guard let index = problems?.index else { return false }
            applyMarkup { Markup.rewriteProblemRef(text: $0, selection: $1, index: index) }
        case "0", "1", "2", "3":
            let level = Int((event.charactersIgnoringModifiers ?? "0")) ?? 0
            applyMarkup { Markup.setHeading(text: $0, selection: $1, level: level) }
        case "]":
            applyMarkup { Markup.indent(text: $0, selection: $1) }
        case "[":
            applyMarkup { Markup.outdent(text: $0, selection: $1) }
        case "d" where !shift:
            applyMarkup { Markup.duplicateLine(text: $0, selection: $1) }
        case "c":
            copy(nil)
        case "x":
            cut(nil)
        case "v":
            if shift { pasteAsPlainText(nil) } else { paste(nil) }
        case "a":
            selectAll(nil)
        case "z":
            // No main menu owns these, so the editor drives the undo manager itself.
            if shift {
                if undoManager?.canRedo == true { undoManager?.redo() }
            } else if undoManager?.canUndo == true {
                undoManager?.undo()
            }
        default:
            return false
        }
        return true
    }

    /// Cmd-K: wrap the selection as a link, using a clipboard URL when there is one.
    private func insertLink() {
        let range = selectedRange
        let text = string as NSString
        let selected = range.length > 0 ? text.substring(with: range) : ""
        let clipboard = range.length > 0 ? MarkdownTextView.singleURL(in: NSPasteboard.general.string(forType: .string)) : nil
        let url = clipboard ?? ""
        let markdown = "[" + selected + "](" + url + ")"
        let newText = text.replacingCharacters(in: range, with: markdown)

        let caret: NSRange
        if clipboard != nil {
            caret = NSRange(location: range.location + (markdown as NSString).length, length: 0)
        } else if range.length > 0 {
            // Caret inside the empty parentheses, ready for the URL.
            caret = NSRange(location: range.location + (selected as NSString).length + 3, length: 0)
        } else {
            caret = NSRange(location: range.location + 1, length: 0)
        }
        replace(with: newText, selection: caret)
    }

    // MARK: - Typing: wrap on type and auto-pairs

    override func insertText(_ input: Any, replacementRange: NSRange) {
        let range = replacementRange.location == NSNotFound ? selectedRange : replacementRange
        guard isEditable,
              let typed = MarkdownTextView.plainText(from: input),
              typed.count == 1,
              let character = typed.first,
              !isCodeContext(at: range.location)
        else {
            autoPairCloser = nil
            super.insertText(input, replacementRange: replacementRange)
            return
        }

        if range.length > 0, let closer = MarkdownTextView.wrapPairs[character] {
            wrapSelection(range: range, open: String(character), close: String(closer))
            return
        }
        if range.length == 0, typeOverCloser(character, at: range.location) {
            return
        }
        if range.length == 0,
           let closer = MarkdownTextView.autoPairs[character],
           allowsAutoPair(at: range.location) {
            insertPair(open: String(character), close: String(closer), replacing: range)
            return
        }

        autoPairCloser = nil
        super.insertText(input, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        let range = selectedRange
        let text = string as NSString
        if range.length == 0,
           let closer = autoPairCloser,
           closer == range.location,
           range.location > 0,
           closer < text.length {
            autoPairCloser = nil
            let both = NSRange(location: closer - 1, length: 2)
            replace(
                with: text.replacingCharacters(in: both, with: ""),
                selection: NSRange(location: both.location, length: 0)
            )
            return
        }
        autoPairCloser = nil
        super.deleteBackward(sender)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        if let closer = autoPairCloser, selectedRange.location != closer { autoPairCloser = nil }
        restyleIfCaretLineChanged()
    }

    private func wrapSelection(range: NSRange, open: String, close: String) {
        let text = string as NSString
        let selected = text.substring(with: range)
        let newText = text.replacingCharacters(in: range, with: open + selected + close)
        let location = range.location + (open as NSString).length
        replace(with: newText, selection: NSRange(location: location, length: range.length))
    }

    private func insertPair(open: String, close: String, replacing range: NSRange) {
        let text = string as NSString
        let newText = text.replacingCharacters(in: range, with: open + close)
        let caret = range.location + (open as NSString).length
        replace(with: newText, selection: NSRange(location: caret, length: 0))
        autoPairCloser = caret
    }

    private func typeOverCloser(_ character: Character, at location: Int) -> Bool {
        let text = string as NSString
        guard let closer = autoPairCloser, closer == location, closer < text.length else { return false }
        guard text.substring(with: NSRange(location: closer, length: 1)) == String(character) else { return false }
        autoPairCloser = nil
        setSelectedRange(NSRange(location: closer + 1, length: 0))
        return true
    }

    /// Auto-pairing only makes sense at the end of the text or before whitespace
    /// and closing punctuation; mid-word it fights the typist.
    private func allowsAutoPair(at location: Int) -> Bool {
        let text = string as NSString
        guard location < text.length else { return true }
        let next = text.substring(with: NSRange(location: location, length: 1))
        guard let scalar = next.unicodeScalars.first else { return true }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return true }
        return ")]}\"'.,;:!?".contains(next)
    }

    private static func plainText(from input: Any) -> String? {
        if let text = input as? String { return text }
        if let attributed = input as? NSAttributedString { return attributed.string }
        return nil
    }

    // MARK: - Copy and paste

    /// Cmd-C with nothing selected copies the whole note as markdown (spec 3.6).
    override func copy(_ sender: Any?) {
        guard selectedRange.length == 0 else {
            super.copy(sender)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    override func paste(_ sender: Any?) {
        guard let pasted = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }
        let range = selectedRange
        let text = string as NSString

        if range.length > 0, let url = MarkdownTextView.singleURL(in: pasted) {
            let selected = text.substring(with: range)
            let markdown = "[" + selected + "](" + url + ")"
            replace(
                with: text.replacingCharacters(in: range, with: markdown),
                selection: NSRange(location: range.location + (markdown as NSString).length, length: 0)
            )
            return
        }
        replace(
            with: text.replacingCharacters(in: range, with: pasted),
            selection: NSRange(location: range.location + (pasted as NSString).length, length: 0)
        )
    }

    /// The clipboard as a single URL, or nil when it holds anything else.
    private static func singleURL(in candidate: String?) -> String? {
        guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: trimmed),
              let scheme = url.scheme,
              scheme == "http" || scheme == "https"
        else { return nil }
        return trimmed
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let location = characterIndexForInsertion(at: point)

        if event.modifierFlags.contains(.command) {
            if let url = url(at: location) {
                _ = NSWorkspace.shared.open(url)
                return
            }
        } else if toggleCheckbox(clickedAt: location) {
            return
        }
        super.mouseDown(with: event)
    }

    private func url(at location: Int) -> URL? {
        let text = string
        guard let line = lineInfo(at: location, in: text) else { return nil }
        let index = String.Index(utf16Offset: location, in: text)
        for span in Markup.inlineSpans(in: text, line: line) where span.range.contains(index) {
            switch span.kind {
            case .link(let url), .bareURL(let url):
                return URL(string: url)
            case .problemRef(_, let number):
                return problems?.index.url(for: number)
            default:
                continue
            }
        }
        return nil
    }

    /// Clicking the `- [ ]` marker toggles the box and leaves the caret alone.
    private func toggleCheckbox(clickedAt location: Int) -> Bool {
        let text = string
        guard let line = lineInfo(at: location, in: text),
              case .checkbox = line.kind,
              let marker = line.markerRange
        else { return false }

        let index = String.Index(utf16Offset: location, in: text)
        guard index >= marker.lowerBound, index < marker.upperBound else { return false }

        let previous = selectedRange
        let caret = line.contentRange.lowerBound..<line.contentRange.lowerBound
        let result = Markup.toggleCheckbox(text: text, selection: caret)
        replace(with: result.text, selection: NSRange(result.selection, in: result.text), scroll: false)

        let length = (string as NSString).length
        let restoredLocation = min(previous.location, length)
        setSelectedRange(NSRange(
            location: restoredLocation,
            length: min(previous.length, length - restoredLocation)
        ))
        return true
    }

    // MARK: - Lines

    private func lineInfo(at location: Int, in text: String) -> LineInfo? {
        let index = String.Index(utf16Offset: location, in: text)
        return Markup.lines(in: text).first {
            $0.range.lowerBound <= index && index <= $0.range.upperBound
        }
    }

    private func caretLine() -> Int? {
        let text = string
        let index = String.Index(utf16Offset: selectedRange.location, in: text)
        return Markup.lines(in: text).firstIndex {
            $0.range.lowerBound <= index && index <= $0.range.upperBound
        }
    }

    private func isCodeContext(at location: Int) -> Bool {
        guard let line = lineInfo(at: location, in: string) else { return false }
        return line.kind == .codeLine || line.kind == .fenceDelimiter
    }

    /// Only needed while markers hide off the caret line; muted markers do not
    /// change when the caret moves.
    private func restyleIfCaretLineChanged() {
        guard style.hidesMarkers else { return }
        let line = caretLine()
        guard line != lastCaretLine else { return }
        lastCaretLine = line
        restyleAll()
    }

    // MARK: - Appearance and attribute changes

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        styler.palette = EditorPalette.resolving(effectiveAppearance)
        typingAttributes = [
            .font: style.bodyFont,
            .foregroundColor: styler.palette.ink,
        ]
        restyleAll()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateHorizontalInset()
    }

    /// Centers the text column when the skin caps its width (the page skin).
    private func updateHorizontalInset() {
        guard let column = style.textColumnWidth else { return }
        let extra = max(0, bounds.width - column - style.insets.width * 2)
        let width = style.insets.width + extra / 2
        guard abs(width - textContainerInset.width) > 0.5 else { return }
        textContainerInset = NSSize(width: width, height: style.insets.height)
    }

    // Styling is ours: the user cannot apply fonts or attributes of their own.
    override func changeFont(_ sender: Any?) {}
    override func changeAttributes(_ sender: Any?) {}
}
