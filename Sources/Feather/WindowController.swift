import AppKit
import Combine
import QuartzCore
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
    private var gallery: GalleryWindow?
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

    /// Soft-deletes the card's note and offers an undo for five seconds.
    private func trashCardNote() {
        guard let id = store.selectedID else { return }
        store.delete(id: id)
        normalizeCardSelection()
        panelState.show(
            CardPill(text: "Note moved to trash.", actionTitle: "Undo") { [weak self] in
                self?.store.restore(id: id)
                self?.store.select(id: id)
            },
            for: 5
        )
    }

    /// Cmd-Shift-K on the card: the note graduates to the gallery and, unless it
    /// is pinned, leaves the strip.
    private func keepAsNote() {
        guard let id = store.selectedID else { return }
        store.promote(id: id)
        normalizeCardSelection()
        panelState.show(
            CardPill(text: "Kept as note.", actionTitle: "Open") { [weak self] in
                self?.openPage(id: id)
            },
            for: 3
        )
    }

    /// The card only edits notes in its strip, so after a trash or a promote it
    /// may need to move to another one.
    private func normalizeCardSelection() {
        if let id = store.selectedID, store.cardNotes.contains(where: { $0.id == id }) { return }
        if let first = store.cardNotes.first {
            store.select(id: first.id)
        } else {
            store.createNote()
        }
    }

    private func stepCardNote(by delta: Int) {
        let notes = store.cardNotes
        guard !notes.isEmpty,
              let current = store.selectedID,
              let index = notes.firstIndex(where: { $0.id == current })
        else { return }
        store.select(id: notes[(index + delta + notes.count) % notes.count].id)
    }

    private func handleCardShortcut(_ event: NSEvent) -> Bool {
        switch Shortcut.match(event) {
        case .newNote:
            store.createNote()
        case .closeOrTrash, .trashNote:
            trashCardNote()
        case .previousNote:
            stepCardNote(by: -1)
        case .nextNote:
            stepCardNote(by: 1)
        case .openGallery:
            openGallery()
        case .toggleKeep:
            keepAsNote()
        case .quickSwitcher:
            openSwitcher(in: panel) { [weak self] in self?.panelState.switcherOpen = true }
        case .togglePin:
            guard let note = store.selectedNote else { return false }
            store.setPinned(!note.pinned, id: note.id)
        default:
            return false
        }
        return true
    }

    // MARK: - Gallery

    /// Opens, or raises, the single gallery window.
    func openGallery() {
        if let gallery {
            present(gallery)
            return
        }
        let window = GalleryWindow()
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: GalleryView(
            store: store,
            actions: GalleryActions(
                openPage: { [weak self] id, cardRect in self?.openPage(id: id, from: cardRect) },
                newPage: { [weak self] in self?.newPage() },
                close: { [weak window] in window?.performClose(nil) }
            )
        ))
        window.setContentSize(GalleryWindow.defaultSize)
        _ = window.setFrameAutosaveName("FeatherGallery")
        gallery = window
        present(window)
    }

    // MARK: - Pages

    /// Opens (or raises) the page window for a note. `cardRect` is the gallery
    /// card the note was opened from, in the gallery's own coordinates.
    func openPage(id: UUID, from cardRect: CGRect? = nil) {
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
            actions: PageActions(
                openGallery: { [weak self] in self?.openGallery() },
                openPage: { [weak self] id in self?.openPage(id: id) },
                close: { [weak window] in window?.performClose(nil) }
            )
        ))
        window.setContentSize(NoteWindow.defaultSize)
        // Per-note frame memory, so a note reopens where the user last left it.
        _ = window.setFrameAutosaveName("FeatherPage-\(id.uuidString)")
        window.shortcutHandler = { [weak self, weak window] event in
            guard let self, let window else { return false }
            return self.handlePageShortcut(event, window: window)
        }
        pages[id] = window
        present(window, from: cardRect.flatMap { screenRect($0) })
    }

    /// A new note that starts life as a page, leaving the card's own note alone.
    func newPage() {
        let previous = store.selectedID
        let note = store.createNote()
        store.promote(id: note.id)
        if let previous { store.select(id: previous) }
        openPage(id: note.id)
    }

    /// Shows a window, growing it out of the gallery card it came from.
    private func present(_ window: NSWindow, from sourceRect: NSRect? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        guard let sourceRect, !Motion.isReduced else {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let target = window.frame
        window.setFrame(sourceRect, display: false)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            window.animator().setFrame(target, display: true)
            window.animator().alphaValue = 1
        }
    }

    /// SwiftUI reports frames top-left down from the hosting view; AppKit screen
    /// coordinates run bottom-left up.
    private func screenRect(_ rect: CGRect) -> NSRect? {
        guard let gallery, let content = gallery.contentView else { return nil }
        let flipped = NSRect(
            x: rect.minX,
            y: content.bounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        return gallery.convertToScreen(flipped)
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
        case .openGallery:
            openGallery()
        case .quickSwitcher:
            openSwitcher(in: window) { window.state.switcherOpen = true }
        default:
            return false
        }
        return true
    }

    /// The editor holds first responder, so it has to let go before the
    /// switcher's text field can take it.
    private func openSwitcher(in window: NSWindow, show: @escaping () -> Void) {
        window.makeFirstResponder(nil)
        show()
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
            actions: CardActions(
                hide: { [weak self] in self?.hidePanel() },
                resize: { [weak self] dx, dy in self?.resizePanel(dx: dx, dy: dy) },
                newNote: { [weak self] in self?.store.createNote() },
                trashNote: { [weak self] in self?.trashCardNote() },
                openGallery: { [weak self] in self?.openGallery() },
                openPage: { [weak self] id in self?.openPage(id: id) }
            )
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: Theme.panelSize)
        // Content view must track the panel's size as the user drags the resize grip.
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.shortcutHandler = { [weak self] event in self?.handleCardShortcut(event) ?? false }

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
        if let page = notification.object as? NoteWindow {
            pages.removeValue(forKey: page.noteID)
        } else if let window = notification.object as? GalleryWindow, window === gallery {
            gallery = nil
        }
    }
}
