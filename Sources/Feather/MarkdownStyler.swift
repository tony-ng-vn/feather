import AppKit
import FeatherCore

/// Applies markdown styling to an `NSTextStorage`.
///
/// All syntax analysis comes from `FeatherCore.Markup`; this type only turns
/// line and span information into text attributes, incrementally as the user
/// types (spec 3.1).
final class MarkdownStyler: NSObject, NSTextStorageDelegate {
    var style: EditorStyle
    var palette: EditorPalette
    /// Index of the caret's line, used only when `style.hidesMarkers` is on.
    var caretLineProvider: (() -> Int?)?

    /// Restyling edits attributes, which re-enters `didProcessEditing`.
    private var isRestyling = false

    init(style: EditorStyle, palette: EditorPalette) {
        self.style = style
        self.palette = palette
        super.init()
    }

    // MARK: - Storage delegate

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        restyle(textStorage, in: editedRange, caretLine: caretLineProvider?())
    }

    // MARK: - Restyling

    /// Restyles the paragraphs touching `editedRange` plus one on either side,
    /// or the whole document when `editedRange` is nil.
    func restyle(_ storage: NSTextStorage, in editedRange: NSRange?, caretLine: Int?) {
        guard !isRestyling else { return }
        isRestyling = true
        defer { isRestyling = false }

        let text = storage.string
        let lines = Markup.lines(in: text)
        guard !lines.isEmpty else { return }
        let targets = targetLines(lines: lines, text: text, editedRange: editedRange)

        storage.beginEditing()
        for index in targets {
            apply(line: lines[index], isCaretLine: index == caretLine, text: text, storage: storage)
        }
        storage.endEditing()
    }

    private func targetLines(lines: [LineInfo], text: String, editedRange: NSRange?) -> Range<Int> {
        let all = 0..<lines.count
        guard let editedRange, let edited = Range(editedRange, in: text) else { return all }

        var first = lines.count - 1
        var last = 0
        for (index, line) in lines.enumerated() {
            if line.range.upperBound >= edited.lowerBound && line.range.lowerBound <= edited.upperBound {
                first = min(first, index)
                last = max(last, index)
            }
        }
        guard first <= last else { return all }
        let expanded = max(0, first - 1)...min(lines.count - 1, last + 1)
        // A fence delimiter flips every line after it between code and prose.
        if lines[expanded].contains(where: { $0.kind == .fenceDelimiter }) { return all }
        return expanded.lowerBound..<(expanded.upperBound + 1)
    }

    // MARK: - Line attributes

    private func apply(line: LineInfo, isCaretLine: Bool, text: String, storage: NSTextStorage) {
        let markerText = line.markerRange.map { String(text[$0]) } ?? ""
        let markerWidth = hangingMarkerWidth(kind: line.kind, marker: markerText)
        let paragraph = paragraphStyle(for: line, markerWidth: markerWidth)

        storage.setAttributes(
            baseAttributes(for: line, paragraph: paragraph),
            range: paragraphRange(of: line, in: text)
        )

        if let markerRange = line.markerRange {
            storage.addAttributes(
                markerAttributes(isCaretLine: isCaretLine, kind: line.kind),
                range: NSRange(markerRange, in: text)
            )
        }

        if case .checkbox(let done) = line.kind, done {
            storage.addAttributes(
                [
                    .foregroundColor: palette.muted,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: palette.muted,
                ],
                range: NSRange(line.contentRange, in: text)
            )
        }

        for span in Markup.inlineSpans(in: text, line: line) {
            apply(span: span, isCaretLine: isCaretLine, text: text, storage: storage)
        }
    }

    /// The line plus its trailing newline, so the paragraph style covers the
    /// whole paragraph and wrapped lines keep the hanging indent.
    private func paragraphRange(of line: LineInfo, in text: String) -> NSRange {
        var range = NSRange(line.range, in: text)
        let end = range.location + range.length
        if end < (text as NSString).length, (text as NSString).character(at: end) == 0x0A {
            range.length += 1
        }
        return range
    }

    private func baseAttributes(for line: LineInfo, paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: palette.ink,
            .paragraphStyle: paragraph,
        ]
        switch line.kind {
        case .heading(let level):
            attributes[.font] = style.serifFont(size: style.headingSize(level: level), weight: .semibold)
        case .quote:
            attributes[.foregroundColor] = palette.muted
        case .codeLine, .fenceDelimiter:
            attributes[.font] = NSFont.monospacedSystemFont(ofSize: style.codeSize, weight: .regular)
            attributes[.backgroundColor] = palette.codeBackground
        case .rule:
            attributes[.foregroundColor] = palette.marker
        case .body, .blank, .bullet, .ordered, .checkbox:
            break
        }
        return attributes
    }

    private func markerAttributes(isCaretLine: Bool, kind: LineKind) -> [NSAttributedString.Key: Any] {
        if style.hidesMarkers && !isCaretLine {
            return [.foregroundColor: NSColor.clear]
        }
        switch kind {
        case .quote:
            return [.foregroundColor: palette.quoteBar]
        case .bullet, .checkbox:
            // A touch heavier so the bullet reads as a glyph, not as punctuation.
            return [
                .foregroundColor: palette.marker,
                .font: style.serifFont(size: style.bodySize, weight: .medium),
            ]
        default:
            return [.foregroundColor: palette.marker]
        }
    }

    // MARK: - Inline attributes

    private func apply(span: InlineSpan, isCaretLine: Bool, text: String, storage: NSTextStorage) {
        let contentRange = NSRange(span.contentRange, in: text)
        let current = font(in: storage, at: contentRange)

        switch span.kind {
        case .bold:
            storage.addAttributes([.font: adding(.bold, to: current)], range: contentRange)
        case .italic:
            storage.addAttributes([.font: adding(.italic, to: current)], range: contentRange)
        case .code:
            storage.addAttributes(
                [
                    .font: NSFont.monospacedSystemFont(ofSize: style.codeSize, weight: .regular),
                    .backgroundColor: palette.codeBackground,
                ],
                range: contentRange
            )
        case .strike:
            storage.addAttributes(
                [
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: palette.muted,
                    .foregroundColor: palette.muted,
                ],
                range: contentRange
            )
        case .highlight:
            storage.addAttributes([.backgroundColor: palette.highlight], range: contentRange)
        case .link(let url), .bareURL(let url):
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: palette.link]
            if let parsed = URL(string: url) { attributes[.link] = parsed }
            storage.addAttributes(attributes, range: contentRange)
        }

        let markerColor: NSColor = (style.hidesMarkers && !isCaretLine) ? .clear : palette.marker
        for markerRange in span.markerRanges {
            storage.addAttributes([.foregroundColor: markerColor], range: NSRange(markerRange, in: text))
        }
    }

    // MARK: - Paragraph and fonts

    private func paragraphStyle(for line: LineInfo, markerWidth: CGFloat) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = style.lineHeightMultiple

        let indent = CGFloat(line.depth) * style.indentUnit
        paragraph.firstLineHeadIndent = indent
        // Hanging indent: wrapped text lines up with the content, not the marker.
        paragraph.headIndent = indent + markerWidth
        if markerWidth > 0 {
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent + markerWidth)]
        }

        switch line.kind {
        case .bullet, .ordered, .checkbox:
            paragraph.paragraphSpacing = style.listSpacing
        case .heading(let level):
            paragraph.paragraphSpacing = level == 1 ? style.paragraphSpacing * 1.5 : style.paragraphSpacing
        default:
            paragraph.paragraphSpacing = style.paragraphSpacing
        }
        return paragraph
    }

    /// Markers that hang: only lists and quotes, so headings keep a flush left edge.
    private func hangingMarkerWidth(kind: LineKind, marker: String) -> CGFloat {
        guard !marker.isEmpty else { return 0 }
        switch kind {
        case .bullet, .ordered, .checkbox, .quote:
            return (marker as NSString).size(withAttributes: [.font: bodyFont]).width
        default:
            return 0
        }
    }

    private var bodyFont: NSFont { style.bodyFont }

    private func adding(_ traits: NSFontDescriptor.SymbolicTraits, to font: NSFont) -> NSFont {
        let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    private func font(in storage: NSTextStorage, at range: NSRange) -> NSFont {
        guard range.length > 0, range.location < storage.length,
              let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        else { return bodyFont }
        return font
    }
}
