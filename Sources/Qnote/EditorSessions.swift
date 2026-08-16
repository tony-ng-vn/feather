import AppKit

/// Per-note editing state shared by the card and the page.
///
/// One note has one undo history no matter which surface it is typed on
/// (spec 3.5), so the map lives here rather than in any one window's state.
final class EditorSessions {
    private var undoManagers: [UUID: UndoManager] = [:]

    func undoManager(for id: UUID?) -> UndoManager? {
        guard let id else { return nil }
        if let existing = undoManagers[id] { return existing }
        let manager = UndoManager()
        undoManagers[id] = manager
        return manager
    }
}
