import Foundation

/// 一首歌的静态信息（来自 Music.app）
struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval

    var cacheKey: String {
        "\(title)|\(artist)|\(album)|\(Int(duration.rounded()))"
    }
}

/// Music.app 的一次采样
struct MusicSnapshot {
    var track: Track
    var position: TimeInterval
    var playing: Bool
    var sampledAt: Date

    /// 结合本地时间推进播放位置，避免 UI 只能按采样频率跳动
    func position(at date: Date) -> TimeInterval {
        var p = position
        if playing {
            p += date.timeIntervalSince(sampledAt)
        }
        return min(max(p, 0), max(track.duration, 0))
    }
}

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    var time: TimeInterval
    var text: String
    var translation: String?
}

struct Lyrics: Equatable {
    var lines: [LyricLine]
    var synced: Bool
    var source: String

    var isEmpty: Bool { lines.isEmpty }
}

// MARK: - LRC 解析

enum LRCParser {
    private static let timeRegex = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
    )
    private static let metaRegex = try! NSRegularExpression(
        pattern: #"^\[(ti|ar|al|by|offset|length|re|ve):(.*)\]$"#
    )

    /// 返回值：synced=true 表示带时间轴
    static func parse(_ raw: String) -> (lines: [LyricLine], synced: Bool) {
        var offset: TimeInterval = 0
        var timed: [(TimeInterval, String)] = []
        var plain: [String] = []

        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if let m = metaRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let keyRange = Range(m.range(at: 1), in: line),
               let valRange = Range(m.range(at: 2), in: line) {
                let key = String(line[keyRange]).lowercased()
                let val = String(line[valRange])
                if key == "offset" { offset = (Double(val.trimmingCharacters(in: .whitespaces)) ?? 0) / 1000.0 }
                continue
            }

            let ns = line as NSString
            let matches = timeRegex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty {
                plain.append(line)
                continue
            }

            var text = line
            for m in matches.reversed() {
                if let r = Range(m.range, in: text) { text.removeSubrange(r) }
            }
            text = text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for m in matches {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac: Double = 0
                if m.range(at: 3).location != NSNotFound {
                    let s = ns.substring(with: m.range(at: 3))
                    frac = (Double(s) ?? 0) / pow(10, Double(s.count))
                }
                let t = mm * 60 + ss + frac
                timed.append((t, text))
            }
        }

        if timed.isEmpty {
            let lines = plain
                .filter { !$0.isEmpty }
                .map { LyricLine(time: -1, text: $0) }
            return (lines, false)
        }

        var merged: [(TimeInterval, String)] = []
        for item in timed.sorted(by: { $0.0 < $1.0 }) {
            if let last = merged.last, abs(last.0 - item.0) < 0.01 {
                if !last.1.contains(item.1) {
                    merged[merged.count - 1].1 = last.1 + " " + item.1
                }
            } else {
                merged.append(item)
            }
        }

        let lines = merged.map { LyricLine(time: max(0, $0.0 + offset), text: $0.1) }
        return (lines, true)
    }
}

// MARK: - 小工具

enum TextUtil {
    static func isBlankOrSymbol(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let meaningful = trimmed.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return meaningful.isEmpty
    }

    static func short(_ s: String, limit: Int) -> String {
        if s.count <= limit { return s }
        return String(s.prefix(limit)) + "…"
    }
}
