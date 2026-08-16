import AppKit
import Carbon.HIToolbox

/// A command a surface (card, page, gallery) can run from the keyboard.
///
/// One table for every surface so the keys cannot drift apart, and so nothing
/// here collides with the editor's own Command keys (spec section 6).
enum Shortcut: Equatable {
    case newNote
    /// Cmd-W: close a page window, or trash the card's note.
    case closeOrTrash
    /// Cmd-Delete, honored by the gallery only: in an editor it deletes text.
    case trashNote
    case quickSwitcher
    case previousNote
    case nextNote
    case openGallery
    /// Keep as note, or send back to the card.
    case toggleKeep
    case togglePin
    case focusMode
    /// Cmd-1..9, honored by the switcher and the gallery only.
    case pick(Int)

    /// Maps a Command-key event, or nil when the editor owns those keys
    /// (Cmd-B/I/E/K, Cmd-] indent, Cmd-Option-arrows, ...).
    static func match(_ event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return nil }
        let shift = flags.contains(.shift)
        let keyCode = Int(event.keyCode)

        if flags.contains(.option) {
            // Cmd-] / Cmd-[ already indent and outdent in the editor, so stepping
            // through notes takes Option as well.
            switch keyCode {
            case kVK_ANSI_RightBracket: return .nextNote
            case kVK_ANSI_LeftBracket: return .previousNote
            default: return nil
            }
        }
        if keyCode == kVK_Delete && !shift { return .trashNote }

        switch (event.charactersIgnoringModifiers ?? "").lowercased() {
        case "n" where !shift: return .newNote
        case "w" where !shift: return .closeOrTrash
        case "p": return shift ? .togglePin : .quickSwitcher
        case "o" where shift: return .openGallery
        case "k" where shift: return .toggleKeep
        case "f" where shift: return .focusMode
        case let key where !shift:
            guard let digit = Int(key), (1...9).contains(digit) else { return nil }
            return .pick(digit)
        default: return nil
        }
    }
}

/// A window that gives its editor first refusal on a key equivalent and only
/// then offers the event to the surface's own shortcut table.
class ShortcutWindow: NSWindow {
    /// Returns true when the event was handled.
    var shortcutHandler: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        return shortcutHandler?(event) ?? false
    }
}
