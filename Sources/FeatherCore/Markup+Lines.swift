import Foundation

/// What a line at the start of the document is, syntactically.
public enum LineKind: Equatable {
    case body
    /// 1...3, where 1 is the largest (title-sized) heading.
    case heading(level: Int)
    case bullet
    case ordered(number: Int)
    case checkbox(done: Bool)
    case quote
    case fenceDelimiter
    case codeLine
    case rule
    case blank
}

/// A single line's classification plus the ranges a caller needs to render or edit it.
///
/// All ranges are `String.Index` ranges into the text that was passed to
/// `Markup.lines(in:)`; they become invalid once that text changes.
public struct LineInfo: Equatable {
    /// The whole line, excluding the trailing newline.
    public let range: Range<String.Index>
    public let kind: LineKind
    /// List nesting depth, 0-based. 4 spaces or 1 tab counts as one level, capped at 6.
    public let depth: Int
    /// Leading whitespace at the start of the line.
    public let indentRange: Range<String.Index>
    /// The marker text, e.g. "## ", "- [ ] ", "> ", "1. ". Nil when the line has no marker.
    public let markerRange: Range<String.Index>?
    /// Everything after the marker (or after the indent, for markerless lines).
    public let contentRange: Range<String.Index>

    public init(
        range: Range<String.Index>,
        kind: LineKind,
        depth: Int,
        indentRange: Range<String.Index>,
        markerRange: Range<String.Index>?,
        contentRange: Range<String.Index>
    ) {
        self.range = range
        self.kind = kind
        self.depth = depth
        self.indentRange = indentRange
        self.markerRange = markerRange
        self.contentRange = contentRange
    }
}

extension Markup {
    /// Classifies every line of `text`, tracking code fence state across lines.
    ///
    /// Single forward pass over the string, O(n) in the length of `text`.
    public static func lines(in text: String) -> [LineInfo] {
        var result: [LineInfo] = []
        var inFence = false
        var lineStart = text.startIndex
        var cursor = text.startIndex

        // Split manually (instead of `components(separatedBy:)`) to keep
        // String.Index ranges into the original string, and to fold the
        // fence-state pass in for free.
        while cursor <= text.endIndex {
            if cursor == text.endIndex || text[cursor] == "\n" {
                let lineRange = lineStart..<cursor
                let info = classify(text: text, range: lineRange, inFence: &inFence)
                result.append(info)
                if cursor == text.endIndex { break }
                lineStart = text.index(after: cursor)
                cursor = lineStart
            } else {
                cursor = text.index(after: cursor)
            }
        }
        return result
    }

    private static func classify(
        text: String,
        range: Range<String.Index>,
        inFence: inout Bool
    ) -> LineInfo {
        let indentEnd = indentEndIndex(text: text, range: range)
        let indentRange = range.lowerBound..<indentEnd
        let contentStart = indentEnd
        let hasIndent = indentEnd > range.lowerBound
        let depth = min(indentDepth(text: text, indentRange: indentRange), 6)

        // Blank: whitespace-only (or empty) line.
        if contentStart == range.upperBound {
            return LineInfo(
                range: range, kind: .blank, depth: 0,
                indentRange: indentRange, markerRange: nil,
                contentRange: contentStart..<contentStart
            )
        }

        // Fence delimiter: a run of 3+ backticks, optionally followed by a language.
        if let markerEnd = fenceMarkerEnd(text: text, from: contentStart, upTo: range.upperBound) {
            inFence.toggle()
            return LineInfo(
                range: range, kind: .fenceDelimiter, depth: depth,
                indentRange: indentRange, markerRange: contentStart..<markerEnd,
                contentRange: markerEnd..<range.upperBound
            )
        }

        // Inside a fence: everything is code until the closing delimiter (handled above).
        if inFence {
            return LineInfo(
                range: range, kind: .codeLine, depth: depth,
                indentRange: indentRange, markerRange: nil,
                contentRange: contentStart..<range.upperBound
            )
        }

        // Only list markers (bullet/ordered/checkbox) may be indented; everything
        // else with leading whitespace falls back to body.
        if let checkbox = checkboxMarker(text: text, from: contentStart, upTo: range.upperBound) {
            return LineInfo(
                range: range, kind: .checkbox(done: checkbox.done), depth: depth,
                indentRange: indentRange, markerRange: contentStart..<checkbox.markerEnd,
                contentRange: checkbox.markerEnd..<range.upperBound
            )
        }
        if let markerEnd = bulletMarkerEnd(text: text, from: contentStart, upTo: range.upperBound) {
            return LineInfo(
                range: range, kind: .bullet, depth: depth,
                indentRange: indentRange, markerRange: contentStart..<markerEnd,
                contentRange: markerEnd..<range.upperBound
            )
        }
        if let ordered = orderedMarker(text: text, from: contentStart, upTo: range.upperBound) {
            return LineInfo(
                range: range, kind: .ordered(number: ordered.number), depth: depth,
                indentRange: indentRange, markerRange: contentStart..<ordered.markerEnd,
                contentRange: ordered.markerEnd..<range.upperBound
            )
        }

        if hasIndent {
            // Indented, but not a list marker: plain indented body text.
            return LineInfo(
                range: range, kind: .body, depth: depth,
                indentRange: indentRange, markerRange: nil,
                contentRange: contentStart..<range.upperBound
            )
        }

        if let heading = headingMarker(text: text, from: contentStart, upTo: range.upperBound) {
            return LineInfo(
                range: range, kind: .heading(level: heading.level), depth: 0,
                indentRange: indentRange, markerRange: contentStart..<heading.markerEnd,
                contentRange: heading.markerEnd..<range.upperBound
            )
        }
        if let markerEnd = quoteMarkerEnd(text: text, from: contentStart, upTo: range.upperBound) {
            return LineInfo(
                range: range, kind: .quote, depth: 0,
                indentRange: indentRange, markerRange: contentStart..<markerEnd,
                contentRange: markerEnd..<range.upperBound
            )
        }
        if isRule(text: text, from: contentStart, upTo: range.upperBound) {
            return LineInfo(
                range: range, kind: .rule, depth: 0,
                indentRange: indentRange, markerRange: nil,
                contentRange: contentStart..<range.upperBound
            )
        }

        return LineInfo(
            range: range, kind: .body, depth: 0,
            indentRange: indentRange, markerRange: nil,
            contentRange: contentStart..<range.upperBound
        )
    }

    // MARK: - Indent

    private static func indentEndIndex(text: String, range: Range<String.Index>) -> String.Index {
        var i = range.lowerBound
        while i < range.upperBound, text[i] == " " || text[i] == "\t" {
            i = text.index(after: i)
        }
        return i
    }

    private static func indentDepth(text: String, indentRange: Range<String.Index>) -> Int {
        var width = 0
        var i = indentRange.lowerBound
        while i < indentRange.upperBound {
            width += text[i] == "\t" ? 4 : 1
            i = text.index(after: i)
        }
        return width / 4
    }

    // MARK: - Markers

    private static func fenceMarkerEnd(
        text: String, from start: String.Index, upTo end: String.Index
    ) -> String.Index? {
        var i = start
        var count = 0
        while i < end, text[i] == "`" {
            count += 1
            i = text.index(after: i)
        }
        guard count >= 3 else { return nil }
        // Rest of the line (a language tag) can be any non-backtick text.
        return i
    }

    private static func bulletMarkerEnd(
        text: String, from start: String.Index, upTo end: String.Index
    ) -> String.Index? {
        guard start < end, text[start] == "-" || text[start] == "*" || text[start] == "+" else { return nil }
        let afterMarker = text.index(after: start)
        guard afterMarker < end, text[afterMarker] == " " else { return nil }
        return text.index(after: afterMarker)
    }

    private static func orderedMarker(
        text: String, from start: String.Index, upTo end: String.Index
    ) -> (number: Int, markerEnd: String.Index)? {
        var i = start
        var digits = ""
        while i < end, text[i].isASCII, text[i].isNumber {
            digits.append(text[i])
            i = text.index(after: i)
        }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        guard i < end, text[i] == "." else { return nil }
        let afterDot = text.index(after: i)
        guard afterDot < end, text[afterDot] == " " else { return nil }
        return (number, text.index(after: afterDot))
    }

    private static func checkboxMarker(
        text: String, from start: String.Index, upTo end: String.Index
    ) -> (done: Bool, markerEnd: String.Index)? {
        // "- [ ] " / "- [x] " / "- [X] "
        if start < end, text[start] == "-" {
            let afterDash = text.index(after: start)
            if afterDash < end, text[afterDash] == " " {
                let afterSpace = text.index(after: afterDash)
                if let box = boxMarker(text: text, from: afterSpace, upTo: end) {
                    return box
                }
            }
        }
        // bare "[] " / "[ ] " / "[x] " / "[X] "
        return boxMarker(text: text, from: start, upTo: end)
    }

    /// Matches "[ ]", "[]", "[x]", "[X]" followed by a space, starting at `start`.
    private static func boxMarker(
        text: String, from start: String.Index, upTo end: String.Index
    ) -> (done: Bool, markerEnd: String.Index)? {
        var i = start
        guard i < end, text[i] == "[" else { return nil }
        i = text.index(after: i)
        var done = false
        if i < end, text[i] == "x" || text[i] == "X" {
            done = true
            i = text.index(after: i)
        } else if i < end, text[i] == " " {
            i = text.index(after: i)
        }
        // else: "[]" with nothing inside is also valid (not done).
        guard i < end, text[i] == "]" else { return nil }
        i = text.index(after: i)
        guard i < end, text[i] == " " else { return nil }
        return (done, text.index(after: i))
    }

    private static func headingMarker(
        text: String, from start: String.Index, upTo end: String.Index
    ) -> (level: Int, markerEnd: String.Index)? {
        var i = start
        var count = 0
        while i < end, text[i] == "#" {
            count += 1
            i = text.index(after: i)
        }
        guard count >= 1, count <= 3 else { return nil } // 0 hashes, or 4+ (body)
        guard i < end, text[i] == " " else { return nil }
        return (count, text.index(after: i))
    }

    private static func quoteMarkerEnd(
        text: String, from start: String.Index, upTo end: String.Index
    ) -> String.Index? {
        guard start < end, text[start] == ">" else { return nil }
        let after = text.index(after: start)
        guard after < end, text[after] == " " else { return nil }
        return text.index(after: after)
    }

    private static func isRule(text: String, from start: String.Index, upTo end: String.Index) -> Bool {
        guard start < end else { return false }
        let ch = text[start]
        guard ch == "-" || ch == "*" || ch == "_" else { return false }
        var i = start
        var count = 0
        while i < end, text[i] == ch {
            count += 1
            i = text.index(after: i)
        }
        // Nothing but trailing whitespace may follow the run of rule characters.
        while i < end {
            guard text[i] == " " || text[i] == "\t" else { return false }
            i = text.index(after: i)
        }
        return count >= 3
    }
}
