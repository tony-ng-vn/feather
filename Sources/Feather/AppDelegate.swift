import AppKit
import Carbon.HIToolbox

/// App lifecycle, the status item, and the global hotkey. Every window lives in
/// `WindowController`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windows = WindowController()
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
        setupStatusItem()
        setupHotKey()
        windows.start()
    }

    func applicationWillResignActive(_ notification: Notification) {
        windows.flush()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windows.flush()
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }
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
            windows.togglePanel()
        }
    }

    private func presentMenu() {
        guard let statusItem else { return }
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
        windows.newNoteOnCard()
    }

    @objc private func togglePanel() {
        windows.togglePanel()
    }

    @objc private func quit() {
        windows.flush()
        NSApp.terminate(nil)
    }

    // MARK: Hotkey

    private func setupHotKey() {
        // J, not N: Option-N is the US-layout dead key for combining tilde (~), which
        // collides with Vietnamese IM / accent composition instead of reaching this app.
        hotKey = HotKey(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(controlKey | optionKey)
        ) { [weak self] in
            DispatchQueue.main.async { self?.windows.togglePanel() }
        }
        if hotKey == nil {
            NSLog("Feather: failed to register global hotkey (Ctrl-Opt-J)")
        }
    }
}
