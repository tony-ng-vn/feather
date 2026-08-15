import Foundation

/// The result of a pure text edit: the new text and where the caret/selection lands.
public struct EditResult: Equatable {
    public let text: String
    public let selection: Range<String.Index>

    public init(text: String, selection: Range<String.Index>) {
        self.text = text
        self.selection = selection
    }
}

/// Which way `moveLine` moves a line.
public enum Direction {
    case up, down
}

/// The list style `setList` converts touched lines to.
public enum ListStyle {
    case bullet, ordered, checkbox, none
}

extension Markup {
    // MARK: - Line/column bookkeeping
    //
    // All edit helpers work in terms of a plain [String] split on "\n" plus a
    // (line, column) caret position. Doing the edit as array surgery, then
    // rejoining, is far simpler than threading String.Index through every
    // insertion; String.Index is only used at the public boundary.

    fileprivate struct Pos {
        var line: Int
        var col: Int
    }

    fileprivate static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    fileprivate static func charOffset(_ index: String.Index, in text: String) -> Int {
        text.distance(from: text.startIndex, to: index)
    }

    fileprivate static func stringIndex(_ offset: Int, in text: String) -> String.Index {
        let capped = max(0, min(offset, text.count))
        return text.index(text.startIndex, offsetBy: capped)
    }

    fileprivate static func lineStarts(_ lines: [String]) -> [Int] {
        var starts: [Int] = []
        var total = 0
        for line in lines {
            starts.append(total)
            total += line.count + 1
        }
        return starts
    }

    fileprivate static func position(ofOffset offset: Int, lines: [String], starts: [Int]) -> Pos {
        var idx = 0
        for i in 0..<lines.count {
            if starts[i] <= offset { idx = i } else { break }
        }
        return Pos(line: idx, col: min(offset - starts[idx], lines[idx].count))
    }

    fileprivate static func offset(of pos: Pos, lines: [String]) -> Int {
        var total = 0
        for i in 0..<pos.line { total += lines[i].count + 1 }
        return total + pos.col
    }

    /// Joins `lines` back into text and converts a (line, col) start/end pair
    /// into a String.Index selection on the new text.
    fileprivate static func result(lines: [String], start: Pos, end: Pos) -> EditResult {
        let text = lines.joined(separator: "\n")
        let startOffset = offset(of: start, lines: lines)
        let endOffset = offset(of: end, lines: lines)
        return EditResult(
            text: text,
            selection: stringIndex(startOffset, in: text)..<stringIndex(endOffset, in: text)
        )
    }

    /// Every line index the selection touches. A selection whose end sits at
    /// column 0 of a later line does not pull that line in (mirrors how
    /// dragging a selection to the start of the next line usually behaves).
    fileprivate static func touchedLineRange(startPos: Pos, endPos: Pos) -> ClosedRange<Int> {
        var endLine = endPos.line
        if endPos.col == 0, endLine > startPos.line {
            endLine -= 1
        }
        return startPos.line...endLine
    }

    fileprivate static func deleteSelection(_ text: String, _ selection: Range<String.Index>) -> String {
        guard !selection.isEmpty else { return text }
        var t = text
        t.removeSubrange(selection)
        return t
    }

    // MARK: - Single-line classification

    fileprivate struct LinePieces {
        let indent: String
        let kind: LineKind
        let depth: Int
        let markerLength: Int
        let content: String
    }

    /// Classifies a single line (no surrounding document context, so this never
    /// reports `.codeLine`; callers that care about fences check `fullInfo` first).
    fileprivate static func pieces(of line: String) -> LinePieces {
        let info = Markup.lines(in: line)[0]
        let indent = String(line[info.indentRange])
        let content = String(line[info.contentRange])
        let markerLength = info.markerRange.map { line.distance(from: $0.lowerBound, to: $0.upperBound) } ?? 0
        return LinePieces(indent: indent, kind: info.kind, depth: info.depth, markerLength: markerLength, content: content)
    }

    fileprivate static func isListKind(_ kind: LineKind) -> Bool {
        switch kind {
        case .bullet, .ordered, .checkbox: return true
        default: return false
        }
    }

    /// Length of a line's marker-and-indent prefix, used to remap a caret column
    /// when a line's marker changes width (renumbering, depth change, etc).
    fileprivate static func prefixLength(of line: String) -> Int {
        let p = pieces(of: line)
        return p.indent.count + p.markerLength
    }

    fileprivate static func remapColumn(old: String, oldCol: Int, new: String) -> Int {
        guard old != new else { return oldCol }
        let oldPrefix = prefixLength(of: old)
        let newPrefix = prefixLength(of: new)
        if oldCol >= oldPrefix {
            return max(0, oldCol - oldPrefix + newPrefix)
        }
        return min(oldCol, newPrefix)
    }

    // MARK: - Marker text builders

    fileprivate static func indentText(depth: Int) -> String { String(repeating: " ", count: depth * 4) }
    fileprivate static func bulletMarkerText() -> String { "- " }
    fileprivate static func checkboxMarkerText(done: Bool) -> String { done ? "- [x] " : "- [ ] " }
    fileprivate static func headingMarkerText(_ level: Int) -> String { String(repeating: "#", count: level) + " " }

    /// Marker text for continuing/reflowing a line of the same list kind.
    /// Ordered numbers are placeholders; `renumberLines` fixes them up afterward.
    fileprivate static func markerText(for kind: LineKind) -> String {
        switch kind {
        case .bullet: return bulletMarkerText()
        case .checkbox: return checkboxMarkerText(done: false)
        case .ordered: return "1. "
        default: return ""
        }
    }

    // MARK: - Ordered list renumbering

    fileprivate static func renumberLines(_ lines: [String]) -> [String] {
        var result = lines
        var counters: [Int: Int] = [:]
        for i in 0..<result.count {
            let p = pieces(of: result[i])
            switch p.kind {
            case .ordered:
                let depth = p.depth
                let n = (counters[depth] ?? 0) + 1
                counters[depth] = n
                for d in counters.keys where d > depth { counters[d] = 0 }
                result[i] = p.indent + "\(n). " + p.content
            case .blank:
                counters.removeAll()
            default:
                let depth = p.depth
                for d in counters.keys where d >= depth { counters[d] = 0 }
            }
        }
        return result
    }

    /// Renumbers every ordered list in `text` so each run of siblings at the
    /// same depth counts 1, 2, 3; a blank line or a non-ordered line resets.
    public static func renumber(text: String) -> String {
        renumberLines(splitLines(text)).joined(separator: "\n")
    }

    // MARK: - Title

    /// The note's title: the first non-blank line with markers and surrounding
    /// whitespace stripped, or "New note" if the text has no content.
    public static func title(of text: String) -> String {
        for info in Markup.lines(in: text) {
            let content = String(text[info.contentRange]).trimmingCharacters(in: .whitespaces)
            if !content.isEmpty { return content }
        }
        return "New note"
    }

    // MARK: - Return

    /// Continues lists, outdents/exits empty items, keeps plain indentation,
    /// and auto-closes an unterminated code fence.
    public static func insertNewline(text: String, selection: Range<String.Index>) -> EditResult {
        let caretOffset = charOffset(selection.lowerBound, in: text)
        let text0 = deleteSelection(text, selection)
        var lines = splitLines(text0)
        let starts = lineStarts(lines)
        let pos = position(ofOffset: caretOffset, lines: lines, starts: starts)
        let fullInfo = Markup.lines(in: text0)
        let curInfo = fullInfo[pos.line]

        if curInfo.kind == .codeLine {
            let indent = String(text0[curInfo.indentRange])
            let line = lines[pos.line]
            let colIdx = line.index(line.startIndex, offsetBy: pos.col)
            lines[pos.line] = String(line[..<colIdx])
            lines.insert(indent + String(line[colIdx...]), at: pos.line + 1)
            let newPos = Pos(line: pos.line + 1, col: indent.count)
            return result(lines: lines, start: newPos, end: newPos)
        }

        if curInfo.kind == .fenceDelimiter,
           isOpeningFence(fullInfo, at: pos.line),
           !hasLaterFenceDelimiter(fullInfo, after: pos.line) {
            lines.insert("", at: pos.line + 1)
            lines.insert("```", at: pos.line + 2)
            let newPos = Pos(line: pos.line + 1, col: 0)
            return result(lines: lines, start: newPos, end: newPos)
        }

        let line = lines[pos.line]
        let p = pieces(of: line)
        let colIdx = line.index(line.startIndex, offsetBy: pos.col)
        let before = String(line[..<colIdx])
        let after = String(line[colIdx...])

        switch p.kind {
        case .bullet, .checkbox, .ordered:
            if p.content.isEmpty {
                if p.depth > 0 {
                    let newDepth = p.depth - 1
                    lines[pos.line] = indentText(depth: newDepth) + markerText(for: p.kind)
                    lines = renumberLines(lines)
                    let newPos = Pos(line: pos.line, col: lines[pos.line].count)
                    return result(lines: lines, start: newPos, end: newPos)
                } else {
                    lines[pos.line] = p.indent
                    let newPos = Pos(line: pos.line, col: p.indent.count)
                    return result(lines: lines, start: newPos, end: newPos)
                }
            } else {
                lines[pos.line] = before
                let marker = p.indent + markerText(for: p.kind)
                lines.insert(marker + after, at: pos.line + 1)
                lines = renumberLines(lines)
                let newMarkerLength = prefixLength(of: lines[pos.line + 1])
                let newPos = Pos(line: pos.line + 1, col: newMarkerLength)
                return result(lines: lines, start: newPos, end: newPos)
            }
        default:
            // Plain (and heading/quote/rule) lines: no marker to continue,
            // but a plain indented line keeps its indentation.
            lines[pos.line] = before
            lines.insert(p.indent + after, at: pos.line + 1)
            let newPos = Pos(line: pos.line + 1, col: p.indent.count)
            return result(lines: lines, start: newPos, end: newPos)
        }
    }

    fileprivate static func isOpeningFence(_ info: [LineInfo], at index: Int) -> Bool {
        var count = 0
        for i in 0...index where info[i].kind == .fenceDelimiter { count += 1 }
        return count % 2 == 1
    }

    fileprivate static func hasLaterFenceDelimiter(_ info: [LineInfo], after index: Int) -> Bool {
        guard index + 1 < info.count else { return false }
        return info[(index + 1)...].contains { $0.kind == .fenceDelimiter }
    }

    // MARK: - Indent / outdent

    public static func indent(text: String, selection: Range<String.Index>) -> EditResult {
        applyIndent(text: text, selection: selection, delta: 1)
    }

    public static func outdent(text: String, selection: Range<String.Index>) -> EditResult {
        applyIndent(text: text, selection: selection, delta: -1)
    }

    fileprivate static func applyIndent(text: String, selection: Range<String.Index>, delta: Int) -> EditResult {
        var lines = splitLines(text)
        let starts = lineStarts(lines)
        let fullInfo = Markup.lines(in: text)
        var startPos = position(ofOffset: charOffset(selection.lowerBound, in: text), lines: lines, starts: starts)
        var endPos = position(ofOffset: charOffset(selection.upperBound, in: text), lines: lines, starts: starts)
        let range = touchedLineRange(startPos: startPos, endPos: endPos)
        let oldStartLine = lines[startPos.line]
        let oldEndLine = lines[endPos.line]

        for i in range {
            let line = lines[i]
            if fullInfo[i].kind == .codeLine {
                lines[i] = adjustCodeIndent(line, delta: delta)
                continue
            }
            let p = pieces(of: line)
            if isListKind(p.kind) {
                let newDepth = max(0, min(6, p.depth + delta))
                lines[i] = indentText(depth: newDepth) + markerText(for: p.kind) + p.content
            } else {
                lines[i] = adjustLiteralIndent(line, delta: delta)
            }
        }
        lines = renumberLines(lines)

        startPos.col = remapColumn(old: oldStartLine, oldCol: startPos.col, new: lines[startPos.line])
        endPos.col = remapColumn(old: oldEndLine, oldCol: endPos.col, new: lines[endPos.line])
        return result(lines: lines, start: startPos, end: endPos)
    }

    fileprivate static func adjustLiteralIndent(_ line: String, delta: Int) -> String {
        if delta > 0 { return "    " + line }
        return removeOneIndentUnit(line)
    }

    /// Inside a code fence, Tab/Shift-Tab inserts or removes a literal tab character.
    fileprivate static func adjustCodeIndent(_ line: String, delta: Int) -> String {
        if delta > 0 { return "\t" + line }
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        return removeOneIndentUnit(line)
    }

    fileprivate static func removeOneIndentUnit(_ line: String) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        var toRemove = 0
        for ch in line where toRemove < 4 && ch == " " { toRemove += 1 }
        return String(line.dropFirst(toRemove))
    }

    // MARK: - Checkbox toggle

    /// Toggles or creates a checkbox on every touched line. Bullets become
    /// unchecked boxes, non-empty plain lines gain one, blank/heading/code lines
    /// are left alone.
    public static func toggleCheckbox(text: String, selection: Range<String.Index>) -> EditResult {
        var lines = splitLines(text)
        let starts = lineStarts(lines)
        let fullInfo = Markup.lines(in: text)
        var startPos = position(ofOffset: charOffset(selection.lowerBound, in: text), lines: lines, starts: starts)
        var endPos = position(ofOffset: charOffset(selection.upperBound, in: text), lines: lines, starts: starts)
        let range = touchedLineRange(startPos: startPos, endPos: endPos)
        let oldStartLine = lines[startPos.line]
        let oldEndLine = lines[endPos.line]

        for i in range {
            guard fullInfo[i].kind != .codeLine, fullInfo[i].kind != .fenceDelimiter else { continue }
            let p = pieces(of: lines[i])
            switch p.kind {
            case .bullet:
                lines[i] = p.indent + checkboxMarkerText(done: false) + p.content
            case .checkbox(let done):
                lines[i] = p.indent + checkboxMarkerText(done: !done) + p.content
            case .body where !p.content.isEmpty:
                lines[i] = p.indent + checkboxMarkerText(done: false) + p.content
            default:
                break
            }
        }
        startPos.col = remapColumn(old: oldStartLine, oldCol: startPos.col, new: lines[startPos.line])
        endPos.col = remapColumn(old: oldEndLine, oldCol: endPos.col, new: lines[endPos.line])
        return result(lines: lines, start: startPos, end: endPos)
    }

    // MARK: - Heading

    /// Sets every touched line to heading `level` (1...3), or clears it with 0.
    /// A line already at that level toggles back to body.
    public static func setHeading(text: String, selection: Range<String.Index>, level: Int) -> EditResult {
        var lines = splitLines(text)
        let starts = lineStarts(lines)
        let fullInfo = Markup.lines(in: text)
        var startPos = position(ofOffset: charOffset(selection.lowerBound, in: text), lines: lines, starts: starts)
        var endPos = position(ofOffset: charOffset(selection.upperBound, in: text), lines: lines, starts: starts)
        let range = touchedLineRange(startPos: startPos, endPos: endPos)
        let oldStartLine = lines[startPos.line]
        let oldEndLine = lines[endPos.line]

        for i in range {
            guard fullInfo[i].kind != .codeLine, fullInfo[i].kind != .fenceDelimiter else { continue }
            let p = pieces(of: lines[i])
            if p.kind == .blank { continue }
            var target = level
            if case .heading(let existing) = p.kind, existing == level {
                target = 0
            }
            lines[i] = target == 0 ? (p.indent + p.content) : (headingMarkerText(target) + p.content)
        }
        startPos.col = remapColumn(old: oldStartLine, oldCol: startPos.col, new: lines[startPos.line])
        endPos.col = remapColumn(old: oldEndLine, oldCol: endPos.col, new: lines[endPos.line])
        return result(lines: lines, start: startPos, end: endPos)
    }

    // MARK: - List style

    /// Converts every touched line to `kind`, preserving depth; ordered numbers
    /// are fixed up by `renumberLines` so they continue the previous sibling.
    public static func setList(text: String, selection: Range<String.Index>, kind: ListStyle) -> EditResult {
        var lines = splitLines(text)
        let starts = lineStarts(lines)
        let fullInfo = Markup.lines(in: text)
        var startPos = position(ofOffset: charOffset(selection.lowerBound, in: text), lines: lines, starts: starts)
        var endPos = position(ofOffset: charOffset(selection.upperBound, in: text), lines: lines, starts: starts)
        let range = touchedLineRange(startPos: startPos, endPos: endPos)
        let oldStartLine = lines[startPos.line]
        let oldEndLine = lines[endPos.line]

        for i in range {
            guard fullInfo[i].kind != .codeLine, fullInfo[i].kind != .fenceDelimiter else { continue }
            let p = pieces(of: lines[i])
            if p.kind == .blank { continue }
            switch kind {
            case .bullet:
                lines[i] = indentText(depth: p.depth) + bulletMarkerText() + p.content
            case .checkbox:
                lines[i] = indentText(depth: p.depth) + checkboxMarkerText(done: false) + p.content
            case .ordered:
                lines[i] = indentText(depth: p.depth) + "1. " + p.content
            case .none:
                lines[i] = p.indent + p.content
            }
        }
        lines = renumberLines(lines)
        startPos.col = remapColumn(old: oldStartLine, oldCol: startPos.col, new: lines[startPos.line])
        endPos.col = remapColumn(old: oldEndLine, oldCol: endPos.col, new: lines[endPos.line])
        return result(lines: lines, start: startPos, end: endPos)
    }

    // MARK: - Wrap

    /// Wraps the selection in `marker` ("**", "*", "\`", "~~", or "=="). With no
    /// selection, inserts an empty pair and places the caret inside it, or
    /// removes the pair if the caret already sits inside an empty one.
    public static func wrap(text: String, selection: Range<String.Index>, marker: String) -> EditResult {
        let startOff = charOffset(selection.lowerBound, in: text)
        let endOff = charOffset(selection.upperBound, in: text)
        let mLen = marker.count

        if startOff == endOff {
            let beforeStart = startOff - mLen
            let afterEnd = startOff + mLen
            if beforeStart >= 0, afterEnd <= text.count {
                let beforeRange = stringIndex(beforeStart, in: text)..<stringIndex(startOff, in: text)
                let afterRange = stringIndex(startOff, in: text)..<stringIndex(afterEnd, in: text)
                if String(text[beforeRange]) == marker, String(text[afterRange]) == marker {
                    var newText = text
                    newText.removeSubrange(afterRange)
                    newText.removeSubrange(beforeRange)
                    let caret = stringIndex(beforeStart, in: newText)
                    return EditResult(text: newText, selection: caret..<caret)
                }
            }
            let caretIndex = stringIndex(startOff, in: text)
            let newText = String(text[text.startIndex..<caretIndex]) + marker + marker + String(text[caretIndex...])
            let caret = stringIndex(startOff + mLen, in: newText)
            return EditResult(text: newText, selection: caret..<caret)
        }

        let before = String(text[text.startIndex..<selection.lowerBound])
        let selected = String(text[selection])
        let after = String(text[selection.upperBound...])
        let newText = before + marker + selected + marker + after
        let newStart = stringIndex(startOff + mLen, in: newText)
        let newEnd = stringIndex(endOff + mLen, in: newText)
        return EditResult(text: newText, selection: newStart..<newEnd)
    }

    // MARK: - Move / duplicate / delete line

    /// Moves the caret's line up or down, carrying along any list children
    /// nested more deeply than it. No-op at the document's bounds.
    public static func moveLine(text: String, selection: Range<String.Index>, direction: Direction) -> EditResult {
        var lines = splitLines(text)
        let starts = lineStarts(lines)
        var startPos = position(ofOffset: charOffset(selection.lowerBound, in: text), lines: lines, starts: starts)
        var endPos = position(ofOffset: charOffset(selection.upperBound, in: text), lines: lines, starts: starts)
        let caretLine = startPos.line

        let p = pieces(of: lines[caretLine])
        var blockEnd = caretLine
        if isListKind(p.kind) {
            while blockEnd + 1 < lines.count {
                let nextP = pieces(of: lines[blockEnd + 1])
                guard isListKind(nextP.kind), nextP.depth > p.depth else { break }
                blockEnd += 1
            }
        }
        let blockStart = caretLine
        let block = Array(lines[blockStart...blockEnd])
        let oldLine = lines[startPos.line]

        switch direction {
        case .up:
            guard blockStart > 0 else { return result(lines: lines, start: startPos, end: endPos) }
            let target = lines[blockStart - 1]
            var newLines = Array(lines[0..<(blockStart - 1)])
            newLines.append(contentsOf: block)
            newLines.append(target)
            newLines.append(contentsOf: lines[(blockEnd + 1)...])
            lines = newLines
            startPos.line -= 1
            endPos.line -= 1
        case .down:
            guard blockEnd < lines.count - 1 else { return result(lines: lines, start: startPos, end: endPos) }
            let target = lines[blockEnd + 1]
            var newLines = Array(lines[0..<blockStart])
            newLines.append(target)
            newLines.append(contentsOf: block)
            newLines.append(contentsOf: lines[(blockEnd + 2)...])
            lines = newLines
            startPos.line += 1
            endPos.line += 1
        }
        lines = renumberLines(lines)
        startPos.col = remapColumn(old: oldLine, oldCol: startPos.col, new: lines[startPos.line])
        endPos.col = min(endPos.col, lines[endPos.line].count)
        return result(lines: lines, start: startPos, end: endPos)
    }

    /// Duplicates the touched lines directly below themselves; the caret follows.
    public static func duplicateLine(text: String, selection: Range<String.Index>) -> EditResult {
        var lines = splitLines(text)
        let starts = lineStarts(lines)
        var startPos = position(ofOffset: charOffset(selection.lowerBound, in: text), lines: lines, starts: starts)
        var endPos = position(ofOffset: charOffset(selection.upperBound, in: text), lines: lines, starts: starts)
        let range = touchedLineRange(startPos: startPos, endPos: endPos)
        let block = Array(lines[range])
        lines.insert(contentsOf: block, at: range.upperBound + 1)
        let shift = block.count
        startPos.line += shift
        endPos.line += shift
        lines = renumberLines(lines)
        return result(lines: lines, start: startPos, end: endPos)
    }

    /// Deletes the touched lines. Deleting the document's last line removes the
    /// newline before it rather than leaving a dangling blank line.
    public static func deleteLine(text: String, selection: Range<String.Index>) -> EditResult {
        var lines = splitLines(text)
        let starts = lineStarts(lines)
        let startPos = position(ofOffset: charOffset(selection.lowerBound, in: text), lines: lines, starts: starts)
        let endPos = position(ofOffset: charOffset(selection.upperBound, in: text), lines: lines, starts: starts)
        let range = touchedLineRange(startPos: startPos, endPos: endPos)
        lines.removeSubrange(range)
        if lines.isEmpty { lines = [""] }
        lines = renumberLines(lines)
        let newLineIndex = min(range.lowerBound, lines.count - 1)
        let pos = Pos(line: newLineIndex, col: 0)
        return result(lines: lines, start: pos, end: pos)
    }
}
