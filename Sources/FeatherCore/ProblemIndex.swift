import Foundation

/// How hard a problem is, matching the LeetCode API's `difficulty.level`.
public enum Difficulty: Int, Codable {
    case easy = 1
    case medium = 2
    case hard = 3
}

/// A single LeetCode problem, as resolved from a `problemRef` reference.
public struct Problem: Codable, Equatable {
    public let number: Int
    public let title: String
    public let slug: String
    public let difficulty: Difficulty

    public init(number: Int, title: String, slug: String, difficulty: Difficulty) {
        self.number = number
        self.title = title
        self.slug = slug
        self.difficulty = difficulty
    }
}

/// Resolves a problem number to its title, URL, and a copyable markdown link.
///
/// Deterministic and offline: this never makes a network call. Loading the
/// bundled snapshot and refreshing the on-disk cache are pure functions of
/// data the caller (the AppKit shell) fetched itself.
public final class ProblemIndex {
    private let byNumber: [Int: Problem]

    public init(problems: [Problem]) {
        var map: [Int: Problem] = [:]
        for problem in problems { map[problem.number] = problem }
        self.byNumber = map
    }

    public func problem(number: Int) -> Problem? {
        byNumber[number]
    }

    /// The problem's page when known; otherwise a search that always resolves
    /// to something, so a reference never links to a dead page.
    public func url(for number: Int) -> URL {
        if let problem = byNumber[number] {
            return URL(string: "https://leetcode.com/problems/\(problem.slug)/")!
        }
        return URL(string: "https://leetcode.com/problemset/?search=\(number)")!
    }

    /// A real markdown link for copying elsewhere, e.g. `[1. Two Sum](https://leetcode.com/problems/two-sum/)`,
    /// or `[LeetCode 9999](...)` for a number the index does not know.
    public func markdownLink(for number: Int) -> String {
        let target = url(for: number).absoluteString
        if let problem = byNumber[number] {
            return "[\(problem.number). \(problem.title)](\(target))"
        }
        return "[LeetCode \(number)](\(target))"
    }

    // MARK: - Compact on-disk format

    private struct CompactProblem: Codable {
        let n: Int
        let t: String
        let s: String
        let d: Int
    }

    /// Loads the compact form: `[{"n":1,"t":"Two Sum","s":"two-sum","d":1}, ...]`.
    public static func load(from data: Data) throws -> ProblemIndex {
        let compact = try JSONDecoder().decode([CompactProblem].self, from: data)
        let problems = compact.compactMap { c -> Problem? in
            guard let difficulty = Difficulty(rawValue: c.d) else { return nil }
            return Problem(number: c.n, title: c.t, slug: c.s, difficulty: difficulty)
        }
        return ProblemIndex(problems: problems)
    }

    /// Encodes to the compact form, sorted by number for a stable, diffable file.
    public func compactData() throws -> Data {
        let compact = byNumber.values
            .sorted { $0.number < $1.number }
            .map { CompactProblem(n: $0.number, t: $0.title, s: $0.slug, d: $0.difficulty.rawValue) }
        return try JSONEncoder().encode(compact)
    }

    // MARK: - Raw LeetCode API format

    // `frontend_question_id` is documented as a number but the API has shipped
    // it as a string too; decode either.
    private enum FlexibleInt: Decodable {
        case int(Int)
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Int.self) {
                self = .int(value)
            } else {
                self = .string(try container.decode(String.self))
            }
        }

        var intValue: Int? {
            switch self {
            case .int(let value): return value
            case .string(let value): return Int(value)
            }
        }
    }

    private struct APIStat: Decodable {
        let frontend_question_id: FlexibleInt
        let question__title: String
        let question__title_slug: String
    }

    private struct APIDifficulty: Decodable {
        let level: Int
    }

    private struct APIPair: Decodable {
        let stat: APIStat
        let difficulty: APIDifficulty
    }

    private struct APIRoot: Decodable {
        let stat_status_pairs: [APIPair]
    }

    /// Parses the raw shape of `https://leetcode.com/api/problems/all/`.
    public static func parseLeetCodeAPI(_ data: Data) throws -> [Problem] {
        let root = try JSONDecoder().decode(APIRoot.self, from: data)
        return root.stat_status_pairs.compactMap { pair -> Problem? in
            guard let number = pair.stat.frontend_question_id.intValue,
                  let difficulty = Difficulty(rawValue: pair.difficulty.level) else { return nil }
            return Problem(
                number: number,
                title: pair.stat.question__title,
                slug: pair.stat.question__title_slug,
                difficulty: difficulty
            )
        }
    }

    // MARK: - Bundled snapshot

    /// The snapshot shipped with the app. Never throws or crashes: a bad or
    /// missing resource just means references resolve as "unknown" until the
    /// weekly refresh runs.
    public static let bundled: ProblemIndex = {
        guard let url = Bundle.module.url(forResource: "leetcode-problems", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? ProblemIndex.load(from: data) else {
            return ProblemIndex(problems: [])
        }
        return index
    }()

    // MARK: - Refresh and cache

    /// Parses freshly-fetched API data, writes it as the compact cache at
    /// `cacheURL` (atomically), and returns the resulting index. The caller
    /// (AppKit) does the networking; this stays a pure function of bytes.
    public static func refreshedIndex(apiData: Data, cacheURL: URL) throws -> ProblemIndex {
        let problems = try parseLeetCodeAPI(apiData)
        let index = ProblemIndex(problems: problems)
        let compact = try index.compactData()
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try compact.write(to: cacheURL, options: .atomic)
        return index
    }

    /// Loads the cache at `cacheURL` if it exists and is no older than `maxAge`.
    public static func loadCache(at cacheURL: URL, maxAge: TimeInterval) -> ProblemIndex? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: cacheURL.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) <= maxAge,
              let data = try? Data(contentsOf: cacheURL),
              let index = try? ProblemIndex.load(from: data) else {
            return nil
        }
        return index
    }
}
