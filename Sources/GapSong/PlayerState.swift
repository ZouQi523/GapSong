import Foundation
import SwiftUI
import Translation

@MainActor
final class PlayerState: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case notFound
        case failed(String)
    }

    @Published private(set) var snapshot: MusicSnapshot?
    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var hint: String?
    /// 歌词每变化一次 +1，供练习模式判断「要不要重建题库」
    @Published private(set) var lyricsGeneration: Int = 0

    let translator = TranslationEngine()
    var targetLanguage = Locale.Language(identifier: "zh-Hans")
    private(set) var translationEnabled = true

    private var loadTask: Task<Void, Never>?
    private var currentKey: String?

    // MARK: 输入

    func ingest(_ snap: MusicSnapshot?) {
        let newKey = snap?.track.cacheKey

        if newKey != currentKey {
            currentKey = newKey
            snapshot = snap
            if snap == nil {
                lyrics = nil
                loadState = .idle
                lyricsGeneration += 1
                loadTask?.cancel()
            } else if let snap {
                loadLyrics(for: snap.track)
            }
        } else {
            snapshot = snap
        }
    }

    func setHint(_ s: String?) { hint = s }

    func setTranslationEnabled(_ on: Bool) {
        translationEnabled = on
        guard on, let lyrics else { return }
        translator.request(lyrics.lines.map(\.text), target: targetLanguage)
    }

    func setTargetLanguage(_ lang: Locale.Language) {
        targetLanguage = lang
        translator.updateTarget(lang)
        guard translationEnabled, let lyrics else { return }
        translator.request(lyrics.lines.map(\.text), target: lang)
    }

    /// 演示/自测：模拟一首正在播放的歌
    func debugSimulate(track: Track, position: TimeInterval = 30) {
        currentKey = track.cacheKey
        snapshot = MusicSnapshot(track: track, position: position, playing: true, sampledAt: Date())
        loadLyrics(for: track, force: true)
    }

    func reload() {
        guard let track = snapshot?.track else { return }
        loadLyrics(for: track, force: true)
    }

    // MARK: 歌词

    private func loadLyrics(for track: Track, force: Bool = false) {
        loadTask?.cancel()
        loadState = .loading
        lyrics = nil
        lyricsGeneration += 1

        loadTask = Task { [weak self] in
            guard let self else { return }
            let result = await LyricsService.fetch(track: track, forceRefresh: force)
            if Task.isCancelled { return }

            guard let result else {
                self.loadState = .notFound
                Diag.log("lyrics: not found for \(track.title) - \(track.artist)")
                return
            }

            let parsed = LRCParser.parse(result.raw)
            if Task.isCancelled { return }

            let lines = parsed.lines
            guard !lines.isEmpty else {
                self.loadState = .notFound
                return
            }

            Diag.log("lyrics: \(lines.count) lines, synced=\(parsed.synced), source=\(result.source)")
            self.lyrics = Lyrics(lines: lines, synced: parsed.synced, source: result.source)
            self.lyricsGeneration += 1
            self.loadState = .loaded
            if self.translationEnabled {
                if let raw = ProcessInfo.processInfo.environment["GAPSONG_TRANSLATE_DELAY"],
                   let secs = Double(raw), secs > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
                    if Task.isCancelled { return }
                }
                self.translator.request(lines.map(\.text), target: self.targetLanguage)
            }
        }
    }

    // MARK: 取时间轴位置

    func position(at date: Date = Date()) -> TimeInterval {
        guard let snapshot, snapshot.playing else {
            return snapshot?.position ?? 0
        }
        return snapshot.position(at: date)
    }

    func lineIndex(at time: TimeInterval) -> Int? {
        guard let lyrics, lyrics.synced, !lyrics.lines.isEmpty else { return nil }
        var lo = 0, hi = lyrics.lines.count - 1, best: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lyrics.lines[mid].time <= time + 0.001 {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return best
    }
}

// MARK: - 调试/预览注入

extension PlayerState {
    func debugInject(track: Track, position: TimeInterval, playing: Bool, lines: [LyricLine], translations: [String: String]) {
        let snap = MusicSnapshot(track: track, position: position, playing: playing, sampledAt: Date())
        self.snapshot = snap
        self.lyrics = Lyrics(lines: lines, synced: true, source: "LRCLIB")
        self.lyricsGeneration += 1
        self.loadState = .loaded
        self.translator.debugSetTranslations(translations)
    }
}
