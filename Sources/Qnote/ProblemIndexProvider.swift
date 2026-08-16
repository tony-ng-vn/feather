import Foundation
import QnoteCore

/// The live LeetCode index, shared by every editor so one background refresh
/// reaches all of them (spec 3.7).
///
/// Networking lives here; parsing, caching, and resolution stay pure in
/// `QnoteCore.ProblemIndex`.
final class ProblemIndexProvider {
    private(set) var index: ProblemIndex

    private let cacheURL: URL
    /// True when the cache was missing or older than a week at launch.
    private let needsRefresh: Bool

    private static let maxCacheAge: TimeInterval = 7 * 24 * 3600
    private static let apiURL = URL(string: "https://leetcode.com/api/problems/all/")

    init(cacheURL: URL = NoteStore.defaultDirectory().appendingPathComponent("leetcode.json")) {
        self.cacheURL = cacheURL
        let cached = ProblemIndex.loadCache(at: cacheURL, maxAge: ProblemIndexProvider.maxCacheAge)
        self.index = cached ?? .bundled
        self.needsRefresh = cached == nil
    }

    /// At most one fetch per launch. Any failure is logged and ignored: the
    /// bundled snapshot keeps references resolving offline.
    func refreshIfNeeded() {
        guard needsRefresh, let url = ProblemIndexProvider.apiURL else { return }
        var request = URLRequest(url: url)
        request.setValue("Qnote", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            if let error {
                NSLog("Qnote: problem index refresh failed: \(error)")
                return
            }
            guard let data else { return }
            do {
                let refreshed = try ProblemIndex.refreshedIndex(apiData: data, cacheURL: self.cacheURL)
                DispatchQueue.main.async { self.index = refreshed }
            } catch {
                NSLog("Qnote: problem index refresh failed: \(error)")
            }
        }.resume()
    }
}
