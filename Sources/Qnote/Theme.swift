import AppKit
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

    /// The desk the page sits on: a shade deeper than the paper, so a page window
    /// reads as a sheet rather than as a full-bleed background.
    static func desk(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.086, green: 0.082, blue: 0.072)
                   : Color(red: 0.953, green: 0.933, blue: 0.894) // #F3EEE4
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

    // MARK: Editor tokens (spec 3.4), warm-toned to sit on the paper.

    static func link(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.553, green: 0.722, blue: 0.855)
                   : Color(red: 0.180, green: 0.380, blue: 0.545)
    }

    static func highlight(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.420, green: 0.360, blue: 0.160)
                   : Color(red: 0.976, green: 0.898, blue: 0.620)
    }

    static func codeBackground(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.165, green: 0.157, blue: 0.141)
                   : Color(red: 0.941, green: 0.922, blue: 0.882)
    }

    static func quoteBar(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.400, green: 0.380, blue: 0.340)
                   : Color(red: 0.780, green: 0.745, blue: 0.686)
    }

    /// Markdown markers stay visible but recede (iA style).
    static func markerMuted(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.450, green: 0.430, blue: 0.390)
                   : Color(red: 0.702, green: 0.671, blue: 0.612)
    }

    // MARK: Window backgrounds

    /// Appearance-adaptive `NSColor`s, for the window chrome SwiftUI does not paint.
    static let paperBackground = dynamic { paper($0) }
    static let deskBackground = dynamic { desk($0) }

    private static func dynamic(_ color: @escaping (ColorScheme) -> Color) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(color(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light))
        }
    }
}

/// System Reduce Motion, read live so a change mid-session is respected.
enum Motion {
    static var isReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Muted "2 hours ago" stamps, shared by the gallery cards and the page footer.
enum RelativeDate {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func text(_ date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// The editor's colors as `NSColor`, resolved once per appearance so the
/// TextKit styler never has to touch SwiftUI while applying attributes.
struct EditorPalette {
    let ink: NSColor
    let muted: NSColor
    let link: NSColor
    let highlight: NSColor
    let codeBackground: NSColor
    let quoteBar: NSColor
    let marker: NSColor

    static func make(dark: Bool) -> EditorPalette {
        let scheme: ColorScheme = dark ? .dark : .light
        return EditorPalette(
            ink: NSColor(Theme.ink(scheme)),
            muted: NSColor(Theme.muted(scheme)),
            link: NSColor(Theme.link(scheme)),
            highlight: NSColor(Theme.highlight(scheme)),
            codeBackground: NSColor(Theme.codeBackground(scheme)),
            quoteBar: NSColor(Theme.quoteBar(scheme)),
            marker: NSColor(Theme.markerMuted(scheme))
        )
    }

    static func resolving(_ appearance: NSAppearance) -> EditorPalette {
        make(dark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }
}
