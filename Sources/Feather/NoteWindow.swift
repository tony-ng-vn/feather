import AppKit
import FeatherCore

/// One page window per open note (spec section 5). Kept in `WindowController`'s
/// `[UUID: NoteWindow]` map, at normal window level so the card floats above it.
final class NoteWindow: ShortcutWindow {
    static let defaultSize = NSSize(width: 720, height: 900)

    let noteID: UUID
    /// Chrome state (focus mode, editor focus) the key handling has to reach.
    let state = PageState()

    init(noteID: UUID) {
        self.noteID = noteID
        super.init(
            contentRect: NSRect(origin: .zero, size: NoteWindow.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        backgroundColor = Theme.deskBackground // the sheet inside is the paper
        isMovableByWindowBackground = true
        minSize = NSSize(width: 520, height: 480)
    }
}
