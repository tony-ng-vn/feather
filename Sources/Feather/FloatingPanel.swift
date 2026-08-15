import AppKit

/// Borderless floating panel that hovers over any app, including fullscreen ones,
/// and can still become key so the user can type into it.
final class FloatingPanel: NSPanel {
    static let minSize = NSSize(width: 260, height: 280)
    static let maxSize = NSSize(width: 720, height: 860)

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        minSize = FloatingPanel.minSize
        maxSize = FloatingPanel.maxSize

        // Clear background so the rounded SwiftUI card and its native shadow show.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
    }

    /// Same contract as `ShortcutWindow`: the editor sees Command keys first,
    /// then the card's own table. `NSPanel` cannot share that base class.
    var shortcutHandler: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        return shortcutHandler?(event) ?? false
    }

    // Borderless windows refuse key/main by default; the user needs to type here.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
