import AppKit
import SwiftUI
import Carbon.HIToolbox
import FeatherCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NoteStore()
    private let panelState = PanelState()
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var hotKey: HotKey?

    private let positionKey = "panelFrameOrigin"
    private let sizeKey = "panelFrameSize"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
        setupStatusItem()
        setupPanel()
        setupHotKey()
        showPanel() // greet the user with the card on first launch
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Feather")
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            presentMenu()
        } else {
            togglePanel()
        }
    }

    private func presentMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Note", action: #selector(newNote), keyEquivalent: "")
        menu.addItem(withTitle: "Show / Hide  (Ctrl-Opt-J)", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Feather", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }

        // Show the menu once, then detach so the next left-click toggles instead.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func newNote() {
        store.createNote()
        showPanel()
    }

    @objc private func quit() {
        store.save()
        NSApp.terminate(nil)
    }

    // MARK: Panel

    private func setupPanel() {
        panel = FloatingPanel(size: Theme.panelSize)
        let root = NoteCardView(
            store: store,
            panelState: panelState,
            onEscape: { [weak self] in self?.hidePanel() },
            onResize: { [weak self] dx, dy in self?.resizePanel(dx: dx, dy: dy) }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: Theme.panelSize)
        // Content view must track the panel's size as the user drags the resize grip.
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelMoved),
            name: NSWindow.didMoveNotification,
            object: panel
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelResized),
            name: NSWindow.didResizeNotification,
            object: panel
        )
        restoreFrame()
    }

    @objc private func togglePanel() {
        // Visible but unfocused (floating over another app) -> bring it to focus so the
        // very next keystroke lands, rather than hiding it and forcing a second press.
        if panel.isVisible && !panel.isKeyWindow {
            showPanel()
        } else if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Focus the editor after the window is key so typing lands immediately.
        DispatchQueue.main.async { [weak self] in self?.panelState.requestFocus() }
    }

    private func hidePanel() {
        store.save()
        panel.orderOut(nil)
        NSApp.hide(nil) // return focus to the previously active app
    }

    @objc private func panelMoved() {
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: positionKey)
    }

    @objc private func panelResized() {
        UserDefaults.standard.set(NSStringFromSize(panel.frame.size), forKey: sizeKey)
    }

    private func restoreFrame() {
        let size: NSSize
        if let saved = UserDefaults.standard.string(forKey: sizeKey) {
            size = NSSizeFromString(saved)
        } else {
            size = Theme.panelSize
        }
        panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: false)

        if let saved = UserDefaults.standard.string(forKey: positionKey) {
            panel.setFrameOrigin(NSPointFromString(saved))
            return
        }
        // First launch: top-right, just under the menu bar.
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - size.width - 16,
                y: visible.maxY - size.height - 8
            ))
        }
    }

    /// Grows/shrinks the panel from its bottom-right corner grip, keeping the
    /// top-left corner fixed so the card doesn't drift while resizing.
    private func resizePanel(dx: CGFloat, dy: CGFloat) {
        var frame = panel.frame
        let maxSize = maxAllowedSize()

        let newWidth = min(max(frame.width + dx, FloatingPanel.minSize.width), maxSize.width)
        let newHeight = min(max(frame.height + dy, FloatingPanel.minSize.height), maxSize.height)
        let actualDeltaHeight = newHeight - frame.height

        frame.size.width = newWidth
        frame.size.height = newHeight
        frame.origin.y -= actualDeltaHeight // AppKit y grows upward; keep the top edge in place
        panel.setFrame(frame, display: true)
    }

    private func maxAllowedSize() -> NSSize {
        guard let screen = NSScreen.main else { return FloatingPanel.maxSize }
        let visible = screen.visibleFrame
        return NSSize(
            width: min(FloatingPanel.maxSize.width, visible.width - 24),
            height: min(FloatingPanel.maxSize.height, visible.height - 24)
        )
    }

    // MARK: Hotkey

    private func setupHotKey() {
        // J, not N: Option-N is the US-layout dead key for combining tilde (~), which
        // collides with Vietnamese IM / accent composition instead of reaching this app.
        hotKey = HotKey(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(controlKey | optionKey)
        ) { [weak self] in
            DispatchQueue.main.async { self?.togglePanel() }
        }
        if hotKey == nil {
            NSLog("Feather: failed to register global hotkey (Ctrl-Opt-J)")
        }
    }
}
