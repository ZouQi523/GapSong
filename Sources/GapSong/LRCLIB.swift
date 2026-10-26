import Foundation
import CryptoKit

/// 歌词来源：LRCLIB（免费、开源、无需 API Key，带 LRC 时间轴）
enum LyricsService {

    struct Result {
        var raw: String
        var synced: Bool
        var source: String
    }

    private struct Cached: Codable {
        var raw: String
        var synced: Bool
        var source: String
        var savedAt: Date
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 20
        cfg.httpAdditionalHeaders = [
            "User-Agent": "GapSong/0.4 (macOS; lyrics overlay)"
        ]
        if AppRuntime.isIsolated {
            // 自检/快照不碰真实网络缓存，避免在用户的 Cache.db 里落数据
            cfg.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        }
        return URLSession(configuration: cfg)
    }()

    // MARK: 缓存

    private static var cacheDir: URL? {
        let dir = Paths.base.appendingPathComponent("Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cacheURL(for track: Track) -> URL? {
        guard let dir = cacheDir else { return nil }
        let digest = SHA256.hash(data: Data(track.cacheKey.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name + ".json")
    }

    private static func loadCache(_ track: Track) -> Result? {
        guard let url = cacheURL(for: track),
              let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(Cached.self, from: data),
              Date().timeIntervalSince(c.savedAt) < 60 * 60 * 24 * 90,
              !c.raw.isEmpty
        else { return nil }
        return Result(raw: c.raw, synced: c.synced, source: c.source + " · 缓存")
    }

    private static func saveCache(_ track: Track, _ r: Result) {
        guard let url = cacheURL(for: track) else { return }
        let c = Cached(raw: r.raw, synced: r.synced, source: r.source, savedAt: Date())
        if let data = try? JSONEncoder().encode(c) { try? data.write(to: url) }
    }

    // MARK: 网络

    static func fetch(track: Track, forceRefresh: Bool = false) async -> Result? {
        if !forceRefresh, let hit = loadCache(track) { return hit }

        let exact = await exactMatch(track)
        if let exact, exact.synced {
            saveCache(track, exact)
            return exact
        }
        // 精确匹配只拿到纯文本时，再找一次带时间轴的版本
        if let searched = await search(track) {
            saveCache(track, searched)
            return searched
        }
        if let exact {
            saveCache(track, exact)
            return exact
        }
        return nil
    }

    private static func exactMatch(_ track: Track) async -> Result? {
        func attempt(album: String?) async -> Result? {
            var comps = URLComponents(string: "https://lrclib.net/api/get")!
            var items: [URLQueryItem] = [
                .init(name: "track_name", value: track.title),
                .init(name: "artist_name", value: track.artist),
                .init(name: "duration", value: String(Int(track.duration.rounded())))
            ]
            if let album, !album.isEmpty {
                items.insert(.init(name: "album_name", value: album), at: 2)
            }
            comps.queryItems = items
            guard let url = comps.url, let obj = await getJSON(url) as? [String: Any] else { return nil }
            return makeResult(obj, source: "LRCLIB")
        }

        if let r = await attempt(album: track.album) { return r }
        return await attempt(album: nil)
    }

    private static func search(_ track: Track) async -> Result? {
        func run(_ items: [URLQueryItem]) async -> Result? {
            var comps = URLComponents(string: "https://lrclib.net/api/search")!
            comps.queryItems = items
            guard let url = comps.url,
                  let arr = await getJSON(url) as? [[String: Any]],
                  !arr.isEmpty else { return nil }

            func delta(_ obj: [String: Any]) -> Double {
                abs(((obj["duration"] as? Double) ?? 0) - track.duration)
            }
            let synced = arr.filter { ($0["syncedLyrics"] as? String)?.isEmpty == false }
                .sorted { delta($0) < delta($1) }
            let plain = arr.filter { ($0["plainLyrics"] as? String)?.isEmpty == false }
                .sorted { delta($0) < delta($1) }

            if let best = synced.first, delta(best) <= 15 {
                return makeResult(best, source: "LRCLIB · 搜索")
            }
            if let best = plain.first, delta(best) <= 6 {
                return makeResult(best, source: "LRCLIB · 搜索")
            }
            if let best = synced.first {
                return makeResult(best, source: "LRCLIB · 搜索")
            }

            return plain.first.flatMap { makeResult($0, source: "LRCLIB · 搜索") }
        }

        if let r = await run([
            .init(name: "track_name", value: track.title),
            .init(name: "artist_name", value: track.artist)
        ]) { return r }

        return await run([.init(name: "q", value: "\(track.title) \(track.artist)")])
    }

    private static func makeResult(_ obj: [String: Any], source: String) -> Result? {
        if let synced = obj["syncedLyrics"] as? String, !synced.isEmpty {
            return Result(raw: synced, synced: true, source: source)
        }
        if let plain = obj["plainLyrics"] as? String, !plain.isEmpty {
            return Result(raw: plain, synced: false, source: source)
        }
        if (obj["instrumental"] as? Bool) == true {
            return Result(raw: "♪ 纯音乐", synced: false, source: source)
        }
        return nil
    }

    private static func getJSON(_ url: URL) async -> Any? {
        for attempt in 0..<3 {
            do {
                let (data, resp) = try await session.data(from: url)
                guard let http = resp as? HTTPURLResponse else { return nil }
                if (200..<300).contains(http.statusCode) {
                    return try JSONSerialization.jsonObject(with: data)
                }
                Diag.log("lrclib HTTP \(http.statusCode) \(url.path) (try \(attempt + 1))")
                if http.statusCode == 404 { return nil }
                if http.statusCode == 429 || http.statusCode >= 500 {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    continue
                }
                return nil
            } catch {
                Diag.log("lrclib error: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        return nil
    }
}
