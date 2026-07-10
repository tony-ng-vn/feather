import SwiftUI

/// Design tokens: Apple Books warm paper for the writing surface,
/// Luma / event-distributor neutral chrome for the tabs and buttons.
enum Theme {
    static let cornerRadius: CGFloat = 16
    static let panelSize = CGSize(width: 360, height: 440)

    // Warm cream paper (light) / warm charcoal (dark).
    static func paper(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.110, green: 0.105, blue: 0.092)
                   : Color(red: 0.984, green: 0.972, blue: 0.949) // #FBF8F2
    }

    // Warm near-black ink / warm off-white.
    static func ink(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.925, green: 0.905, blue: 0.865)
                   : Color(red: 0.102, green: 0.090, blue: 0.070)
    }

    static func muted(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.60, green: 0.58, blue: 0.53)
                   : Color(red: 0.54, green: 0.52, blue: 0.47)
    }

    // Warm hairline, matched to the paper rather than the cool #ebebeb of the web app.
    static func border(_ s: ColorScheme) -> Color {
        s == .dark ? Color.white.opacity(0.10)
                   : Color(red: 0.898, green: 0.878, blue: 0.839)
    }

    // Filled pill for the active tab: near-black (light) / near-white (dark), Luma style.
    static func accent(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.925, green: 0.905, blue: 0.865)
                   : Color(red: 0.102, green: 0.102, blue: 0.102)
    }

    static func accentText(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.110, green: 0.105, blue: 0.092)
                   : Color.white
    }
}
