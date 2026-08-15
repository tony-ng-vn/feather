import Foundation
import SwiftUI

/// A short-lived message with one action, shown at the bottom of the card.
struct CardPill: Identifiable {
    let id = UUID()
    let text: String
    let actionTitle: String
    let action: () -> Void
}

/// Bridges imperative AppKit events (panel shown, note trashed) into the card.
/// Bumping `focusPulse` tells the card to re-focus its editor on every summon,
/// since SwiftUI `.onAppear` only fires the first time the view is created.
final class PanelState: ObservableObject {
    @Published var focusPulse: Int = 0
    @Published var pill: CardPill?

    func requestFocus() {
        focusPulse &+= 1
    }

    func show(_ pill: CardPill, for seconds: TimeInterval) {
        self.pill = pill
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            // A newer pill may have replaced this one in the meantime.
            guard self?.pill?.id == pill.id else { return }
            self?.pill = nil
        }
    }

    func dismissPill() {
        pill = nil
    }
}
