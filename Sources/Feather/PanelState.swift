import Foundation
import SwiftUI

/// Bridges imperative AppKit events (panel shown) into SwiftUI focus.
/// Bumping `focusPulse` tells the card to re-focus its editor on every summon,
/// since SwiftUI `.onAppear` only fires the first time the view is created.
final class PanelState: ObservableObject {
    @Published var focusPulse: Int = 0

    /// One undo manager per note, so switching tabs keeps each note's history
    /// (spec 3.5). Not published: handing one out must not redraw the card.
    private var undoManagers: [UUID: UndoManager] = [:]

    func requestFocus() {
        focusPulse &+= 1
    }

    func undoManager(for id: UUID?) -> UndoManager? {
        guard let id else { return nil }
        if let existing = undoManagers[id] { return existing }
        let manager = UndoManager()
        undoManagers[id] = manager
        return manager
    }
}
