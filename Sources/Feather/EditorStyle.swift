import AppKit

/// Typography and layout for one editor skin (spec 3.4). The card and the page
/// share the same editor and differ only in these numbers.
struct EditorStyle {
    let bodySize: CGFloat
    /// H1, H2, H3 point sizes, largest first.
    let headingSizes: [CGFloat]
    let lineHeightMultiple: CGFloat
    /// Space after a paragraph, as a fraction of the body size.
    let paragraphSpacingRatio: CGFloat
    /// Space between list items, as a fraction of the body size.
    let listSpacingRatio: CGFloat
    /// Code font size, as a fraction of the body size.
    let codeSizeRatio: CGFloat
    /// One list nesting level, in points.
    let indentUnit: CGFloat
    /// Text container inset: width is the side margin, height the top/bottom one.
    let insets: NSSize
    /// Text column cap in characters; nil lets the text follow the view width.
    let maxCharacters: Int?
    /// Hide markers on lines the caret is not on. False ships the muted-marker
    /// fallback the spec allows (section 12): clearing a marker's color keeps its
    /// width, so hiding it this way would leave a gap where the marker was.
    let hidesMarkers: Bool

    var paragraphSpacing: CGFloat { bodySize * paragraphSpacingRatio }
    var listSpacing: CGFloat { bodySize * listSpacingRatio }
    var codeSize: CGFloat { bodySize * codeSizeRatio }

    /// Point size for a heading level, clamped to the levels this skin defines.
    func headingSize(level: Int) -> CGFloat {
        let index = min(max(level, 1), headingSizes.count) - 1
        return headingSizes[index]
    }

    /// Width of the text column in points, or nil when it should follow the view.
    func maxTextWidth(font: NSFont) -> CGFloat? {
        guard let maxCharacters else { return nil }
        let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
        return CGFloat(maxCharacters) * advance
    }

    /// The floating card: small type, no column cap, tight margins.
    static let compact = EditorStyle(
        bodySize: 16,
        headingSizes: [26, 21, 17],
        lineHeightMultiple: 1.5,
        paragraphSpacingRatio: 0.5,
        listSpacingRatio: 0.2,
        codeSizeRatio: 0.9,
        indentUnit: 22,
        insets: NSSize(width: 20, height: 14),
        maxCharacters: nil,
        hidesMarkers: false
    )

    /// The page window: larger type, 68-character column, page-like margins.
    static let page = EditorStyle(
        bodySize: 18,
        headingSizes: [29, 24, 19],
        lineHeightMultiple: 1.5,
        paragraphSpacingRatio: 0.5,
        listSpacingRatio: 0.2,
        codeSizeRatio: 0.9,
        indentUnit: 25,
        insets: NSSize(width: 32, height: 56),
        maxCharacters: 68,
        hidesMarkers: false
    )
}
