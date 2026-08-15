import AppKit
import Combine
import SwiftUI
import FeatherCore

/// Owns every surface Feather can show: the floating card, the gallery, and one
/// page window per open note. `AppDelegate` keeps only app lifecycle, the status
/// item, and the global hotkey, and routes everything else here (spec section 8).
final class WindowController: NSObject {
    private let store: NoteStore
    private let panelState = PanelState()
    private let sessions = EditorSessions()

    /// Built on first use so the controller can hand itself to the card's actions.
    private lazy var panel: FloatingPanel = makePanel()
    private var pages: [UUID: NoteWindow] = [:]
    private var storeObserver: AnyCancellable?

    private let positionKey = "panelFrameOrigin"
    private let sizeKey = "panelFrameSize"

    override init() {
        // Debounced writes (spec section 7); every hide, close, and quit flushes.
        store = NoteStore(repository: FileRepository(directory: NoteStore.defaultDirectory()))
        super.init()
    }

    /// One-time launch work, after the app has finished starting up.
    func start() {
        store.purgeExpiredTrash()
        // A note trashed anywhere (card, page, gallery) must not leave its page open.
        storeObserver = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.closePagesForGoneNotes() }
        }
        showPanel()
    }

    /// Writes any pending debounced edit. Called on hide, on resign active, on
    /// window close, and on quit.
    func flush() {
        store.flush()
    }

    // MARK: - Card

    func togglePanel() {
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

    func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Focus the editor after the window is key so typing lands immediately.
        DispatchQueue.main.async { [weak self] in self?.panelState.requestFocus() }
    }

    func hidePanel() {
        flush()
        panel.orderOut(nil)
        NSApp.hide(nil) // return focus to the previously active app
    }

    /// Menu-bar "New Note": a fresh quick note on the card.
    func newNoteOnCard() {
        store.createNote()
        showPanel()
    }

    // MARK: - Pages

    /// Opens (or raises) the page window for a note.
    func openPage(id: UUID) {
        if let existing = pages[id] {
            present(existing)
            return
        }
        let window = NoteWindow(noteID: id)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: PageView(
            store: store,
            state: window.state,
            noteID: id,
            sessions: sessions,
            actions: PageActions(close: { [weak window] in window?.performClose(nil) })
        ))
        window.setContentSize(NoteWindow.defaultSize)
        // Per-note frame memory, so a note reopens where the user last left it.
        _ = window.setFrameAutosaveName("FeatherPage-\(id.uuidString)")
        window.shortcutHandler = { [weak self, weak window] event in
            guard let self, let window else { return false }
            return self.handlePageShortcut(event, window: window)
        }
        pages[id] = window
        present(window)
    }

    /// A new note that starts life as a page, leaving the card's own note alone.
    func newPage() {
        let previous = store.selectedID
        let note = store.createNote()
        store.promote(id: note.id)
        if let previous { store.select(id: previous) }
        openPage(id: note.id)
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func handlePageShortcut(_ event: NSEvent, window: NoteWindow) -> Bool {
        let id = window.noteID
        switch Shortcut.match(event) {
        case .newNote:
            newPage()
        case .closeOrTrash:
            window.performClose(nil)
        case .trashNote:
            store.delete(id: id)
        case .togglePin:
            store.setPinned(!(store.liveNotes.first { $0.id == id }?.pinned ?? false), id: id)
        case .toggleKeep:
            store.demote(id: id) // "Send to card": the note belongs to the strip again
            window.performClose(nil)
        case .focusMode:
            window.state.focusMode.toggle()
        default:
            return false
        }
        return true
    }

    /// Closes pages whose note has been trashed or purged.
    private func closePagesForGoneNotes() {
        let live = Set(store.liveNotes.map { $0.id })
        for (id, window) in pages where !live.contains(id) {
            window.performClose(nil)
        }
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(size: Theme.panelSize)
        let root = NoteCardView(
            store: store,
            panelState: panelState,
            sessions: sessions,
            onEscape: { [weak self] in self?.hidePanel() },
            onResize: { [weak self] dx, dy in self?.resizePanel(dx: dx, dy: dy) }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: Theme.panelSize)
        // Content view must track the panel's size as the user drags the resize grip.
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        NotificationCenter.default.addObserver(
            self, selector: #selector(panelMoved),
            name: NSWindow.didMoveNotification, object: panel
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelResized),
            name: NSWindow.didResizeNotification, object: panel
        )
        restoreFrame(of: panel)
        return panel
    }

    // MARK: - Card frame

    @objc private func panelMoved() {
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: positionKey)
    }

    @objc private func panelResized() {
        UserDefaults.standard.set(NSStringFromSize(panel.frame.size), forKey: sizeKey)
    }

    private func restoreFrame(of panel: FloatingPanel) {
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
        let maxSize = maxAllowedPanelSize()

        let newWidth = min(max(frame.width + dx, FloatingPanel.minSize.width), maxSize.width)
        let newHeight = min(max(frame.height + dy, FloatingPanel.minSize.height), maxSize.height)
        let actualDeltaHeight = newHeight - frame.height

        frame.size.width = newWidth
        frame.size.height = newHeight
        frame.origin.y -= actualDeltaHeight // AppKit y grows upward; keep the top edge in place
        panel.setFrame(frame, display: true)
    }

    private func maxAllowedPanelSize() -> NSSize {
        guard let screen = NSScreen.main else { return FloatingPanel.maxSize }
        let visible = screen.visibleFrame
        return NSSize(
            width: min(FloatingPanel.maxSize.width, visible.width - 24),
            height: min(FloatingPanel.maxSize.height, visible.height - 24)
        )
    }
}

extension WindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        flush()
        guard let window = notification.object as? NoteWindow else { return }
        pages.removeValue(forKey: window.noteID)
    }
}
