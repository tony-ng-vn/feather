import AppKit

/// Borderless floating panel that hovers over any app, including fullscreen ones,
/// and can still become key so the user can type into it.
final class FloatingPanel: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        // Clear background so the rounded SwiftUI card and its native shadow show.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
    }

    // Borderless windows refuse key/main by default; the user needs to type here.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
