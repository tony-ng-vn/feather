import AppKit

/// The single browse window (spec section 4): paper background, no visible
/// titlebar, its own remembered frame.
final class GalleryWindow: ShortcutWindow {
    static let defaultSize = NSSize(width: 900, height: 640)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: GalleryWindow.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Feather"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        backgroundColor = Theme.paperBackground
        isMovableByWindowBackground = true
        minSize = NSSize(width: 520, height: 400)
    }
}
