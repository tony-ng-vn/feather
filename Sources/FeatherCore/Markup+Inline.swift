import Foundation

/// What an inline span within a line's content is.
public enum InlineKind: Equatable {
    case bold
    case italic
    case code
    case strike
    case highlight
    case link(url: String)
    case bareURL(url: String)
}

/// A run of text within a line carrying inline formatting.
public struct InlineSpan: Equatable {
    public let kind: InlineKind
    /// The whole span, including its markers.
    public let range: Range<String.Index>
    /// The formatted text, excluding markers.
    public let contentRange: Range<String.Index>
    /// The marker characters themselves, e.g. "**"/"**", or "[", "]", "(", ")" for a link.
    public let markerRanges: [Range<String.Index>]

    public init(
        kind: InlineKind,
        range: Range<String.Index>,
        contentRange: Range<String.Index>,
        markerRanges: [Range<String.Index>]
    ) {
        self.kind = kind
        self.range = range
        self.contentRange = contentRange
        self.markerRanges = markerRanges
    }
}

extension Markup {
    /// Scans `line`'s content (not the whole line) for inline formatting spans.
    ///
    /// Spans never overlap: scanning is left to right, the earliest possible
    /// start wins, and a code span always takes priority over other markers
    /// that would otherwise start at the same position.
    public static func inlineSpans(in text: String, line: LineInfo) -> [InlineSpan] {
        switch line.kind {
        case .codeLine, .fenceDelimiter:
            return []
        default:
            break
        }

        var spans: [InlineSpan] = []
        var i = line.contentRange.lowerBound
        let end = line.contentRange.upperBound

        while i < end {
            if let span = matchAny(text: text, at: i, end: end) {
                spans.append(span)
                i = span.range.upperBound
            } else {
                i = text.index(after: i)
            }
        }
        return spans
    }

    private static func matchAny(text: String, at i: String.Index, end: String.Index) -> InlineSpan? {
        if let span = matchCode(text: text, at: i, end: end) { return span }
        if let span = matchLink(text: text, at: i, end: end) { return span }
        if let span = matchBracket(text: text, at: i, end: end, marker: "**", kind: .bold) { return span }
        if let span = matchBracket(text: text, at: i, end: end, marker: "~~", kind: .strike) { return span }
        if let span = matchBracket(text: text, at: i, end: end, marker: "==", kind: .highlight) { return span }
        if let span = matchItalic(text: text, at: i, end: end, marker: "*") { return span }
        if let span = matchItalic(text: text, at: i, end: end, marker: "_") { return span }
        if let span = matchBareURL(text: text, at: i, end: end) { return span }
        return nil
    }

    // MARK: - Code

    private static func matchCode(text: String, at i: String.Index, end: String.Index) -> InlineSpan? {
        guard text[i] == "`" else { return nil }
        let contentStart = text.index(after: i)
        guard let closing = firstIndex(of: "`", in: text, from: contentStart, upTo: end) else { return nil }
        let closingEnd = text.index(after: closing)
        return InlineSpan(
            kind: .code,
            range: i..<closingEnd,
            contentRange: contentStart..<closing,
            markerRanges: [i..<contentStart, closing..<closingEnd]
        )
    }

    // MARK: - Two-character markers: bold, strike, highlight

    private static func matchBracket(
        text: String, at i: String.Index, end: String.Index, marker: String, kind: InlineKind
    ) -> InlineSpan? {
        guard hasPrefix(marker, in: text, at: i, end: end) else { return nil }
        let openEnd = text.index(i, offsetBy: marker.count)
        var k = openEnd
        while k < end {
            if hasPrefix(marker, in: text, at: k, end: end) {
                let closeEnd = text.index(k, offsetBy: marker.count)
                return InlineSpan(
                    kind: kind,
                    range: i..<closeEnd,
                    contentRange: openEnd..<k,
                    markerRanges: [i..<openEnd, k..<closeEnd]
                )
            }
            k = text.index(after: k)
        }
        return nil // unterminated
    }

    // MARK: - Single-character markers: italic, with a no-whitespace-inside rule

    private static func matchItalic(
        text: String, at i: String.Index, end: String.Index, marker: Character
    ) -> InlineSpan? {
        guard text[i] == marker else { return nil }
        // Reject the doubled marker; that is bold/strike/highlight's territory.
        let openEnd = text.index(after: i)
        guard openEnd < end, text[openEnd] != marker, !text[openEnd].isWhitespace else { return nil }

        var k = openEnd
        while k < end {
            if text[k] == marker {
                let before = text.index(before: k)
                if !text[before].isWhitespace {
                    let closeEnd = text.index(after: k)
                    return InlineSpan(
                        kind: .italic,
                        range: i..<closeEnd,
                        contentRange: openEnd..<k,
                        markerRanges: [i..<openEnd, k..<closeEnd]
                    )
                }
                return nil // whitespace right before the closing marker: not italic
            }
            k = text.index(after: k)
        }
        return nil // unterminated
    }

    // MARK: - Links

    private static func matchLink(text: String, at i: String.Index, end: String.Index) -> InlineSpan? {
        guard text[i] == "[" else { return nil }
        let textStart = text.index(after: i)
        guard let closeBracket = firstIndex(of: "]", in: text, from: textStart, upTo: end) else { return nil }
        let openParen = text.index(after: closeBracket)
        guard openParen < end, text[openParen] == "(" else { return nil }
        let urlStart = text.index(after: openParen)
        guard let closeParen = firstIndex(of: ")", in: text, from: urlStart, upTo: end) else { return nil }
        let url = String(text[urlStart..<closeParen])
        let spanEnd = text.index(after: closeParen)
        return InlineSpan(
            kind: .link(url: url),
            range: i..<spanEnd,
            contentRange: textStart..<closeBracket,
            markerRanges: [
                i..<textStart,
                closeBracket..<openParen,
                openParen..<urlStart,
                closeParen..<spanEnd,
            ]
        )
    }

    // MARK: - Bare URLs

    private static func matchBareURL(text: String, at i: String.Index, end: String.Index) -> InlineSpan? {
        let prefix: String
        if hasPrefix("https://", in: text, at: i, end: end) {
            prefix = "https://"
        } else if hasPrefix("http://", in: text, at: i, end: end) {
            prefix = "http://"
        } else {
            return nil
        }
        var k = text.index(i, offsetBy: prefix.count)
        var urlEnd = k
        while k < end, !text[k].isWhitespace {
            k = text.index(after: k)
            urlEnd = k
        }
        // Trim trailing punctuation that reads as sentence punctuation, not URL.
        let trimmable: Set<Character> = [")", "]", ",", "."]
        while urlEnd > i, trimmable.contains(text[text.index(before: urlEnd)]) {
            urlEnd = text.index(before: urlEnd)
        }
        guard urlEnd > text.index(i, offsetBy: prefix.count) else { return nil } // nothing after scheme
        let url = String(text[i..<urlEnd])
        return InlineSpan(
            kind: .bareURL(url: url),
            range: i..<urlEnd,
            contentRange: i..<urlEnd,
            markerRanges: []
        )
    }

    // MARK: - Shared scan helpers

    private static func hasPrefix(_ marker: String, in text: String, at i: String.Index, end: String.Index) -> Bool {
        var t = i
        for ch in marker {
            guard t < end, text[t] == ch else { return false }
            t = text.index(after: t)
        }
        return true
    }

    private static func firstIndex(
        of char: Character, in text: String, from start: String.Index, upTo end: String.Index
    ) -> String.Index? {
        var i = start
        while i < end {
            if text[i] == char { return i }
            i = text.index(after: i)
        }
        return nil
    }
}
