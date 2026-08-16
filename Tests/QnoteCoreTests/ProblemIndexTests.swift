import XCTest
@testable import QnoteCore

final class ProblemIndexTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("QnoteTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("leetcode.json")
    }

    private let twoSum = Problem(number: 1, title: "Two Sum", slug: "two-sum", difficulty: .easy)

    // MARK: Lookup and URLs

    func testKnownProblemResolvesRealURL() {
        let index = ProblemIndex(problems: [twoSum])
        XCTAssertEqual(index.problem(number: 1), twoSum)
        XCTAssertEqual(index.url(for: 1).absoluteString, "https://leetcode.com/problems/two-sum/")
    }

    func testUnknownProblemResolvesSearchURL() {
        let index = ProblemIndex(problems: [])
        XCTAssertNil(index.problem(number: 9999))
        XCTAssertEqual(index.url(for: 9999).absoluteString, "https://leetcode.com/problemset/?search=9999")
    }

    func testMarkdownLinkKnown() {
        let index = ProblemIndex(problems: [twoSum])
        XCTAssertEqual(index.markdownLink(for: 1), "[1. Two Sum](https://leetcode.com/problems/two-sum/)")
    }

    func testMarkdownLinkUnknown() {
        let index = ProblemIndex(problems: [])
        XCTAssertEqual(index.markdownLink(for: 9999), "[LeetCode 9999](https://leetcode.com/problemset/?search=9999)")
    }

    // MARK: Compact round trip

    func testCompactDataRoundTrips() throws {
        let index = ProblemIndex(problems: [twoSum, Problem(number: 2, title: "Add Two Numbers", slug: "add-two-numbers", difficulty: .medium)])
        let data = try index.compactData()
        let reloaded = try ProblemIndex.load(from: data)
        XCTAssertEqual(reloaded.problem(number: 1), twoSum)
        XCTAssertEqual(reloaded.problem(number: 2)?.title, "Add Two Numbers")
    }

    func testCompactDataIsSortedByNumber() throws {
        let index = ProblemIndex(problems: [
            Problem(number: 3, title: "c", slug: "c", difficulty: .hard),
            Problem(number: 1, title: "a", slug: "a", difficulty: .easy),
        ])
        let data = try index.compactData()
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.range(of: "\"a\"")!.lowerBound < json.range(of: "\"c\"")!.lowerBound)
    }

    // MARK: Raw API parsing

    func testParseLeetCodeAPIWithIntegerID() throws {
        let json = """
        {"stat_status_pairs":[{"stat":{"frontend_question_id":1,"question__title":"Two Sum","question__title_slug":"two-sum"},"difficulty":{"level":1}}]}
        """.data(using: .utf8)!
        let problems = try ProblemIndex.parseLeetCodeAPI(json)
        XCTAssertEqual(problems, [twoSum])
    }

    func testParseLeetCodeAPIWithStringID() throws {
        let json = """
        {"stat_status_pairs":[{"stat":{"frontend_question_id":"1","question__title":"Two Sum","question__title_slug":"two-sum"},"difficulty":{"level":1}}]}
        """.data(using: .utf8)!
        let problems = try ProblemIndex.parseLeetCodeAPI(json)
        XCTAssertEqual(problems, [twoSum])
    }

    // MARK: Bundled

    func testBundledIndexLoadsAndResolvesTwoSum() {
        let bundled = ProblemIndex.bundled
        XCTAssertEqual(bundled.problem(number: 1)?.slug, "two-sum")
    }

    // MARK: Refresh and cache

    func testRefreshedIndexWritesCacheAndCanBeReloaded() throws {
        let json = """
        {"stat_status_pairs":[{"stat":{"frontend_question_id":1,"question__title":"Two Sum","question__title_slug":"two-sum"},"difficulty":{"level":1}}]}
        """.data(using: .utf8)!
        let cacheURL = tempURL()
        let index = try ProblemIndex.refreshedIndex(apiData: json, cacheURL: cacheURL)
        XCTAssertEqual(index.problem(number: 1), twoSum)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))

        let reloaded = ProblemIndex.loadCache(at: cacheURL, maxAge: 60)
        XCTAssertEqual(reloaded?.problem(number: 1), twoSum)
    }

    func testLoadCacheReturnsNilWhenMissing() {
        XCTAssertNil(ProblemIndex.loadCache(at: tempURL(), maxAge: 60))
    }

    func testLoadCacheReturnsNilWhenStale() throws {
        let json = """
        {"stat_status_pairs":[{"stat":{"frontend_question_id":1,"question__title":"Two Sum","question__title_slug":"two-sum"},"difficulty":{"level":1}}]}
        """.data(using: .utf8)!
        let cacheURL = tempURL()
        _ = try ProblemIndex.refreshedIndex(apiData: json, cacheURL: cacheURL)
        XCTAssertNil(ProblemIndex.loadCache(at: cacheURL, maxAge: -1))
    }
}
