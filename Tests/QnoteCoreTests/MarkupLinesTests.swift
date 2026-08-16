import XCTest
@testable import QnoteCore

final class MarkupLinesTests: XCTestCase {
    private func kinds(_ text: String) -> [LineKind] {
        Markup.lines(in: text).map(\.kind)
    }

    private func text(of line: LineInfo, in source: String) -> String {
        String(source[line.range])
    }

    // MARK: Empty input

    func testEmptyStringYieldsOneBlankLine() {
        let lines = Markup.lines(in: "")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].kind, .blank)
        XCTAssertEqual(lines[0].range, "".startIndex..<"".endIndex)
    }

    // MARK: Headings

    func testHeadingLevels() {
        XCTAssertEqual(kinds("# Title"), [.heading(level: 1)])
        XCTAssertEqual(kinds("## H2"), [.heading(level: 2)])
        XCTAssertEqual(kinds("### H3"), [.heading(level: 3)])
    }

    func testFourHashesIsBody() {
        XCTAssertEqual(kinds("#### not a heading"), [.body])
    }

    func testHeadingWithLeadingSpaceIsBody() {
        XCTAssertEqual(kinds("  # not a heading"), [.body])
    }

    func testHashWithoutSpaceIsBody() {
        XCTAssertEqual(kinds("#tag"), [.body])
    }

    // MARK: Lists

    func testBulletMarkers() {
        XCTAssertEqual(kinds("- a"), [.bullet])
        XCTAssertEqual(kinds("* a"), [.bullet])
        XCTAssertEqual(kinds("+ a"), [.bullet])
    }

    func testOrderedMarker() {
        XCTAssertEqual(kinds("1. first"), [.ordered(number: 1)])
        XCTAssertEqual(kinds("42. big"), [.ordered(number: 42)])
    }

    func testCheckboxMarkers() {
        XCTAssertEqual(kinds("- [ ] todo"), [.checkbox(done: false)])
        XCTAssertEqual(kinds("- [x] done"), [.checkbox(done: true)])
        XCTAssertEqual(kinds("- [X] done"), [.checkbox(done: true)])
        XCTAssertEqual(kinds("[] bare"), [.checkbox(done: false)])
        XCTAssertEqual(kinds("[ ] bare"), [.checkbox(done: false)])
        XCTAssertEqual(kinds("[x] bare"), [.checkbox(done: true)])
    }

    func testMixedBulletsAndCheckboxes() {
        let src = "- one\n- [ ] two\n- [x] three\n* four"
        XCTAssertEqual(kinds(src), [.bullet, .checkbox(done: false), .checkbox(done: true), .bullet])
    }

    func testNestedDepthWithSpacesAndTabs() {
        let lines = Markup.lines(in: "- a\n    - b\n\t- c\n        - d")
        XCTAssertEqual(lines.map(\.depth), [0, 1, 1, 2])
    }

    func testDepthCappedAtSix() {
        let deeplyIndented = String(repeating: " ", count: 40) + "- deep"
        let lines = Markup.lines(in: deeplyIndented)
        XCTAssertEqual(lines[0].depth, 6)
    }

    // MARK: Quote, rule, blank

    func testQuote() {
        XCTAssertEqual(kinds("> quoted"), [.quote])
    }

    func testRule() {
        XCTAssertEqual(kinds("---"), [.rule])
        XCTAssertEqual(kinds("***"), [.rule])
        XCTAssertEqual(kinds("___"), [.rule])
        XCTAssertEqual(kinds("-----"), [.rule])
    }

    func testBlank() {
        XCTAssertEqual(kinds(""), [.blank])
        XCTAssertEqual(kinds("   "), [.blank])
        XCTAssertEqual(kinds("\t"), [.blank])
    }

    // MARK: Fences

    func testFenceState() {
        let src = "```\ncode here\nstill code\n```\nafter"
        XCTAssertEqual(kinds(src), [.fenceDelimiter, .codeLine, .codeLine, .fenceDelimiter, .body])
    }

    func testFenceWithLanguage() {
        let src = "```swift\nlet x = 1\n```"
        let lines = Markup.lines(in: src)
        XCTAssertEqual(lines[0].kind, .fenceDelimiter)
        XCTAssertEqual(text(of: lines[0], in: src), "```swift")
    }

    func testUnclosedFenceMakesRestOfDocumentCode() {
        let src = "```\nline one\nline two"
        XCTAssertEqual(kinds(src), [.fenceDelimiter, .codeLine, .codeLine])
    }

    // MARK: Ranges

    func testMarkerRangeExcludesContent() {
        let src = "## Header text"
        let line = Markup.lines(in: src)[0]
        XCTAssertEqual(src[line.markerRange!], "## ")
        XCTAssertEqual(src[line.contentRange], "Header text")
    }

    func testCheckboxMarkerRangeIncludesTrailingSpace() {
        let src = "- [ ] task"
        let line = Markup.lines(in: src)[0]
        XCTAssertEqual(src[line.markerRange!], "- [ ] ")
        XCTAssertEqual(src[line.contentRange], "task")
    }

    func testOrderedMarkerRange() {
        let src = "1. first item"
        let line = Markup.lines(in: src)[0]
        XCTAssertEqual(src[line.markerRange!], "1. ")
    }

    func testQuoteMarkerRange() {
        let src = "> hello"
        let line = Markup.lines(in: src)[0]
        XCTAssertEqual(src[line.markerRange!], "> ")
    }

    func testBodyHasNoMarker() {
        let src = "just text"
        let line = Markup.lines(in: src)[0]
        XCTAssertNil(line.markerRange)
    }

    func testIndentedPlainLineIsBody() {
        let src = "    indented plain text"
        let line = Markup.lines(in: src)[0]
        XCTAssertEqual(line.kind, .body)
        XCTAssertEqual(line.depth, 1)
        XCTAssertEqual(src[line.indentRange], "    ")
    }
}
