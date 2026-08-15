import Foundation
import SwiftUI

/// Bridges imperative AppKit events (panel shown) into SwiftUI focus.
/// Bumping `focusPulse` tells the card to re-focus its editor on every summon,
/// since SwiftUI `.onAppear` only fires the first time the view is created.
final class PanelState: ObservableObject {
    @Published var focusPulse: Int = 0

    func requestFocus() {
        focusPulse &+= 1
    }
}
