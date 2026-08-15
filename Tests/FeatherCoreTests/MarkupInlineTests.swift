import XCTest
@testable import FeatherCore

final class MarkupInlineTests: XCTestCase {
    private func spans(_ text: String) -> [(InlineKind, String)] {
        let line = Markup.lines(in: text)[0]
        return Markup.inlineSpans(in: text, line: line).map { ($0.kind, String(text[$0.range])) }
    }

    // MARK: Empty input

    func testEmptyStringHasNoSpans() {
        let line = Markup.lines(in: "")[0]
        XCTAssertEqual(Markup.inlineSpans(in: "", line: line), [])
    }

    // MARK: Every marker kind

    func testBold() {
        let result = spans("this is **bold** text")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].0, .bold)
        XCTAssertEqual(result[0].1, "**bold**")
    }

    func testItalicStar() {
        let result = spans("this is *italic* text")
        XCTAssertEqual(result[0].0, .italic)
        XCTAssertEqual(result[0].1, "*italic*")
    }

    func testItalicUnderscore() {
        let result = spans("this is _italic_ text")
        XCTAssertEqual(result[0].0, .italic)
        XCTAssertEqual(result[0].1, "_italic_")
    }

    func testCode() {
        let result = spans("this is `code` text")
        XCTAssertEqual(result[0].0, .code)
        XCTAssertEqual(result[0].1, "`code`")
    }

    func testStrike() {
        let result = spans("this is ~~struck~~ text")
        XCTAssertEqual(result[0].0, .strike)
        XCTAssertEqual(result[0].1, "~~struck~~")
    }

    func testHighlight() {
        let result = spans("this is ==marked== text")
        XCTAssertEqual(result[0].0, .highlight)
        XCTAssertEqual(result[0].1, "==marked==")
    }

    func testLink() {
        let result = spans("see [feather](https://example.com) here")
        XCTAssertEqual(result[0].0, .link(url: "https://example.com"))
        XCTAssertEqual(result[0].1, "[feather](https://example.com)")
    }

    func testBareURL() {
        let result = spans("visit https://example.com now")
        XCTAssertEqual(result[0].0, .bareURL(url: "https://example.com"))
    }

    // MARK: Italic whitespace rule

    func testItalicNotAdjacentToWhitespaceInside() {
        XCTAssertEqual(spans("* not italic *").count, 0)
    }

    func testItalicAdjacentToNonWhitespace() {
        let result = spans("*yes*")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].0, .italic)
    }

    // MARK: Unterminated markers

    func testUnterminatedBoldProducesNoSpan() {
        XCTAssertEqual(spans("this is **not closed").count, 0)
    }

    func testUnterminatedCodeProducesNoSpan() {
        XCTAssertEqual(spans("this is `not closed").count, 0)
    }

    func testUnterminatedLinkProducesNoSpan() {
        XCTAssertEqual(spans("this is [not closed").count, 0)
        XCTAssertEqual(spans("this is [text](not closed").count, 0)
    }

    // MARK: Priority

    func testCodeBeatsBold() {
        let result = spans("`**not bold**`")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].0, .code)
        XCTAssertEqual(result[0].1, "`**not bold**`")
    }

    func testSpansDoNotOverlap() {
        let result = spans("**bold** and *italic*")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].0, .bold)
        XCTAssertEqual(result[1].0, .italic)
    }

    // MARK: Bare URL trailing punctuation

    func testBareURLTrailingPeriodStripped() {
        let result = spans("go to https://example.com.")
        XCTAssertEqual(result[0].1, "https://example.com")
    }

    func testBareURLTrailingParenStripped() {
        let result = spans("(see https://example.com) for more")
        XCTAssertEqual(result[0].1, "https://example.com")
    }

    func testBareURLTrailingCommaStripped() {
        let result = spans("read https://example.com, then continue")
        XCTAssertEqual(result[0].1, "https://example.com")
    }

    // MARK: Line kind exclusions

    func testCodeLineHasNoSpans() {
        let src = "```\n**not styled**\n```"
        let lines = Markup.lines(in: src)
        XCTAssertEqual(Markup.inlineSpans(in: src, line: lines[1]), [])
    }

    func testFenceDelimiterLineHasNoSpans() {
        let src = "```swift"
        let line = Markup.lines(in: src)[0]
        XCTAssertEqual(Markup.inlineSpans(in: src, line: line), [])
    }

    // MARK: Marker and content ranges

    func testBoldContentRangeExcludesMarkers() {
        let src = "**bold**"
        let line = Markup.lines(in: src)[0]
        let span = Markup.inlineSpans(in: src, line: line)[0]
        XCTAssertEqual(src[span.contentRange], "bold")
        XCTAssertEqual(span.markerRanges.map { String(src[$0]) }, ["**", "**"])
    }
}
