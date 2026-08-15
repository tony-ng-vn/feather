import XCTest
@testable import FeatherCore

final class MarkupEditsTests: XCTestCase {
    /// Builds a caret selection at `offset` characters into `text`.
    private func caret(_ offset: Int, in text: String) -> Range<String.Index> {
        let idx = text.index(text.startIndex, offsetBy: offset)
        return idx..<idx
    }

    private func selection(_ range: Range<Int>, in text: String) -> Range<String.Index> {
        let lo = text.index(text.startIndex, offsetBy: range.lowerBound)
        let hi = text.index(text.startIndex, offsetBy: range.upperBound)
        return lo..<hi
    }

    private func caretOffset(_ result: EditResult) -> Int {
        result.text.distance(from: result.text.startIndex, to: result.selection.lowerBound)
    }

    // MARK: Empty input

    func testEmptyInputDoesNotCrash() {
        let empty = ""
        _ = Markup.insertNewline(text: empty, selection: caret(0, in: empty))
        _ = Markup.indent(text: empty, selection: caret(0, in: empty))
        _ = Markup.outdent(text: empty, selection: caret(0, in: empty))
        _ = Markup.toggleCheckbox(text: empty, selection: caret(0, in: empty))
        _ = Markup.setHeading(text: empty, selection: caret(0, in: empty), level: 1)
        _ = Markup.setList(text: empty, selection: caret(0, in: empty), kind: .bullet)
        _ = Markup.wrap(text: empty, selection: caret(0, in: empty), marker: "**")
        _ = Markup.moveLine(text: empty, selection: caret(0, in: empty), direction: .up)
        _ = Markup.duplicateLine(text: empty, selection: caret(0, in: empty))
        _ = Markup.deleteLine(text: empty, selection: caret(0, in: empty))
        XCTAssertEqual(Markup.renumber(text: empty), "")
        XCTAssertEqual(Markup.title(of: empty), "New note")
    }

    // MARK: insertNewline: list continuation

    func testInsertNewlineContinuesBullet() {
        let text = "- one"
        let r = Markup.insertNewline(text: text, selection: caret(text.count, in: text))
        XCTAssertEqual(r.text, "- one\n- ")
        XCTAssertEqual(caretOffset(r), r.text.count)
    }

    func testInsertNewlineContinuesOrderedAndRenumbers() {
        let text = "1. one\n2. two"
        let r = Markup.insertNewline(text: text, selection: caret(6, in: text)) // end of "1. one"
        XCTAssertEqual(r.text, "1. one\n2. \n3. two")
    }

    func testInsertNewlineChecklistContinuationAlwaysUnchecked() {
        let text = "- [x] done"
        let r = Markup.insertNewline(text: text, selection: caret(text.count, in: text))
        XCTAssertEqual(r.text, "- [x] done\n- [ ] ")
    }

    func testInsertNewlineEmptyNestedItemOutdents() {
        let text = "- parent\n    - "
        let r = Markup.insertNewline(text: text, selection: caret(text.count, in: text))
        XCTAssertEqual(r.text, "- parent\n- ")
    }

    func testInsertNewlineEmptyTopLevelItemExits() {
        let text = "- "
        let r = Markup.insertNewline(text: text, selection: caret(text.count, in: text))
        XCTAssertEqual(r.text, "")
    }

    func testInsertNewlinePlainIndentedLineKeepsIndentation() {
        let text = "    plain"
        let r = Markup.insertNewline(text: text, selection: caret(text.count, in: text))
        XCTAssertEqual(r.text, "    plain\n    ")
    }

    func testInsertNewlineInsideCodeFenceIsPlain() {
        let text = "```\ncode line\n```"
        let r = Markup.insertNewline(text: text, selection: caret(4 + "code".count, in: text))
        // caret after "code" inside "code line"
        XCTAssertEqual(r.text, "```\ncode\n line\n```")
    }

    func testInsertNewlineAutoClosesUnterminatedFence() {
        let text = "```"
        let r = Markup.insertNewline(text: text, selection: caret(text.count, in: text))
        XCTAssertEqual(r.text, "```\n\n```")
        XCTAssertEqual(caretOffset(r), 4) // on the empty middle line
    }

    func testInsertNewlineReplacesSelectionFirst() {
        let text = "- one two"
        let r = Markup.insertNewline(text: text, selection: selection(6..<9, in: text)) // "two"
        XCTAssertEqual(r.text, "- one \n- ")
    }

    // MARK: indent / outdent

    func testIndentAndOutdentMultiLineSelection() {
        let text = "- a\n- b\n- c"
        let sel = selection(0..<text.count, in: text)
        let indented = Markup.indent(text: text, selection: sel)
        XCTAssertEqual(indented.text, "    - a\n    - b\n    - c")
        let outdented = Markup.outdent(text: indented.text, selection: selection(0..<indented.text.count, in: indented.text))
        XCTAssertEqual(outdented.text, "- a\n- b\n- c")
    }

    func testIndentOrderedRenumbers() {
        let text = "1. a\n2. b\n3. c"
        // Indent the middle line only.
        let sel = selection(5..<5, in: text) // caret at start of "2. b"
        let r = Markup.indent(text: text, selection: sel)
        XCTAssertEqual(r.text, "1. a\n    1. b\n2. c")
    }

    func testOutdentCapsAtZero() {
        let text = "- top"
        let r = Markup.outdent(text: text, selection: caret(0, in: text))
        XCTAssertEqual(r.text, "- top")
    }

    func testIndentCodeLineInsertsLiteralTab() {
        let text = "```\ncode\n```"
        let r = Markup.indent(text: text, selection: caret(4, in: text)) // start of "code"
        XCTAssertEqual(r.text, "```\n\tcode\n```")
    }

    // MARK: toggleCheckbox

    func testToggleCheckboxOnPlainLine() {
        let text = "buy milk"
        let r = Markup.toggleCheckbox(text: text, selection: caret(0, in: text))
        XCTAssertEqual(r.text, "- [ ] buy milk")
    }

    func testToggleCheckboxOnBullet() {
        let text = "- buy milk"
        let r = Markup.toggleCheckbox(text: text, selection: caret(0, in: text))
        XCTAssertEqual(r.text, "- [ ] buy milk")
    }

    func testToggleCheckboxFlipsDoneState() {
        let text = "- [ ] buy milk"
        let r = Markup.toggleCheckbox(text: text, selection: caret(0, in: text))
        XCTAssertEqual(r.text, "- [x] buy milk")
        let r2 = Markup.toggleCheckbox(text: r.text, selection: caret(0, in: r.text))
        XCTAssertEqual(r2.text, "- [ ] buy milk")
    }

    func testToggleCheckboxLeavesHeadingAndBlankUnchanged() {
        let text = "# Title\n\ncode"
        let sel = selection(0..<text.count, in: text)
        let r = Markup.toggleCheckbox(text: text, selection: sel)
        XCTAssertEqual(r.text, "# Title\n\n- [ ] code")
    }

    // MARK: setHeading

    func testSetHeadingAppliesLevel() {
        let text = "hello"
        let r = Markup.setHeading(text: text, selection: caret(0, in: text), level: 2)
        XCTAssertEqual(r.text, "## hello")
    }

    func testSetHeadingTogglesOffWhenSameLevel() {
        let text = "## hello"
        let r = Markup.setHeading(text: text, selection: caret(0, in: text), level: 2)
        XCTAssertEqual(r.text, "hello")
    }

    func testSetHeadingSwitchesLevel() {
        let text = "## hello"
        let r = Markup.setHeading(text: text, selection: caret(0, in: text), level: 1)
        XCTAssertEqual(r.text, "# hello")
    }

    // MARK: setList

    func testSetListConvertsToOrderedAndRenumbers() {
        let text = "- a\n- b"
        let sel = selection(0..<text.count, in: text)
        let r = Markup.setList(text: text, selection: sel, kind: .ordered)
        XCTAssertEqual(r.text, "1. a\n2. b")
    }

    func testSetListNoneStripsMarker() {
        let text = "- a"
        let r = Markup.setList(text: text, selection: caret(0, in: text), kind: .none)
        XCTAssertEqual(r.text, "a")
    }

    // MARK: wrap

    func testWrapWithSelection() {
        let text = "hello world"
        let sel = selection(0..<5, in: text)
        let r = Markup.wrap(text: text, selection: sel, marker: "**")
        XCTAssertEqual(r.text, "**hello** world")
        XCTAssertEqual(String(r.text[r.selection]), "hello")
    }

    func testWrapWithEmptySelectionInsertsPairAndPlacesCaretInside() {
        let text = "hello"
        let r = Markup.wrap(text: text, selection: caret(5, in: text), marker: "`")
        XCTAssertEqual(r.text, "hello``")
        XCTAssertEqual(caretOffset(r), 6)
    }

    func testWrapRemovesEmptyPairWhenCaretInside() {
        let text = "hello``world"
        let r = Markup.wrap(text: text, selection: caret(6, in: text), marker: "`")
        XCTAssertEqual(r.text, "helloworld")
        XCTAssertEqual(caretOffset(r), 5)
    }

    // MARK: moveLine

    func testMoveLineUpCarriesChildren() {
        let text = "- parent\n    - child\n- sibling"
        let r = Markup.moveLine(text: text, selection: caret(0, in: text), direction: .up)
        // No-op: already at the top.
        XCTAssertEqual(r.text, text)
    }

    func testMoveLineDownCarriesChildren() {
        let text = "- parent\n    - child\n- sibling"
        let r = Markup.moveLine(text: text, selection: caret(0, in: text), direction: .down)
        XCTAssertEqual(r.text, "- sibling\n- parent\n    - child")
    }

    func testMoveLineNoOpAtBounds() {
        let text = "- only"
        let up = Markup.moveLine(text: text, selection: caret(0, in: text), direction: .up)
        let down = Markup.moveLine(text: text, selection: caret(0, in: text), direction: .down)
        XCTAssertEqual(up.text, text)
        XCTAssertEqual(down.text, text)
    }

    // MARK: duplicate / delete

    func testDuplicateLine() {
        let text = "hello"
        let r = Markup.duplicateLine(text: text, selection: caret(0, in: text))
        XCTAssertEqual(r.text, "hello\nhello")
    }

    func testDeleteLineOnLastLineRemovesPrecedingNewline() {
        let text = "one\ntwo"
        let r = Markup.deleteLine(text: text, selection: caret(text.count, in: text)) // caret on "two"
        XCTAssertEqual(r.text, "one")
    }

    func testDeleteOnlyLineLeavesEmptyDocument() {
        let text = "only"
        let r = Markup.deleteLine(text: text, selection: caret(0, in: text))
        XCTAssertEqual(r.text, "")
    }

    // MARK: renumber

    func testRenumberResetsOnBlankLine() {
        let text = "1. a\n2. b\n\n1. c"
        XCTAssertEqual(Markup.renumber(text: text), "1. a\n2. b\n\n1. c")
    }

    func testRenumberResetsOnNonListLine() {
        let text = "1. a\n2. b\nplain\n1. c"
        XCTAssertEqual(Markup.renumber(text: text), "1. a\n2. b\nplain\n1. c")
    }

    func testRenumberFixesOutOfOrderNumbers() {
        let text = "5. a\n1. b\n9. c"
        XCTAssertEqual(Markup.renumber(text: text), "1. a\n2. b\n3. c")
    }

    // MARK: title

    func testTitleStripsHeadingMarker() {
        XCTAssertEqual(Markup.title(of: "# My Note\nbody"), "My Note")
    }

    func testTitleStripsListMarker() {
        XCTAssertEqual(Markup.title(of: "- groceries\nmilk"), "groceries")
    }

    func testTitleStripsCheckboxMarker() {
        XCTAssertEqual(Markup.title(of: "- [x] done thing"), "done thing")
    }

    func testTitleFallsBackToNewNote() {
        XCTAssertEqual(Markup.title(of: ""), "New note")
        XCTAssertEqual(Markup.title(of: "\n\n   \n"), "New note")
    }
}
