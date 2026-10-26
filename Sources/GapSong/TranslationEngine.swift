import Foundation
import SwiftUI
import Translation
import NaturalLanguage

/// 用系统 Translation.framework 做端上翻译（免费、离线、不上传歌词）
///
/// 设计要点：`translationTask` 只在 Configuration 变化时重跑，而 Configuration 对
/// 相同语言对可能判等，导致换歌时不重新触发。这里改成“一个常驻会话”：
/// SwiftUI 给一次 session，我们就在里面循环取任务，直到视图消失。
@MainActor
final class TranslationEngine: ObservableObject {
    enum Status: Equatable {
        case idle
        case working(String)
        case ready
        case unavailable(String)
    }

    @Published private(set) var status: Status = .idle {
        didSet { if status != oldValue { Diag.log("translation: \(status)") } }
    }
    @Published private(set) var translations: [String: String] = [:]
    @Published private(set) var isNeeded = true
    /// 变更它会驱动 SwiftUI 的 translationTask 启动会话
    @Published var config: TranslationSession.Configuration?
    /// 需要用户确认下载语言包时回调（用于把歌词窗前置并激活 App）
    var onNeedsDownload: (() -> Void)?

    private var pending: [String] = []
    private var allTexts: [String] = []
    private var running = false
    private var target: Locale.Language = Locale.Language(identifier: "zh-Hans")
    private var source: Locale.Language?
    private var cache: [String: String] = [:]
    private var cacheLoaded = false
    private var saveTask: Task<Void, Never>?
    private var retryBudget = 2

    private let batchSize = 8
    private let idlePoll: UInt64 = 300_000_000

    // MARK: 对外

    /// 为一首歌的歌词行请求翻译
    func request(_ texts: [String], target: Locale.Language) {
        loadCacheIfNeeded()
        self.target = target

        let cleaned = texts.filter { !TextUtil.isBlankOrSymbol($0) }
        guard !cleaned.isEmpty else {
            status = .idle
            return
        }

        let detected = Self.detectLanguage(in: cleaned.joined(separator: "\n"))
        self.source = detected

        if let detected, detected.minimalIdentifier == target.minimalIdentifier {
            isNeeded = false
            status = .ready
            return
        }
        isNeeded = true

        var seen = Set<String>()
        let unique = cleaned.filter { seen.insert($0).inserted }
        allTexts = unique
        retryBudget = 2

        let missing = unique.filter { lookup($0) == nil }
        guard !missing.isEmpty else {
            status = .ready
            return
        }

        for t in missing where !pending.contains(t) { pending.append(t) }
        status = .working("准备翻译…")

        if !running {
            // 会话还没起来：触发一次 translationTask
            kick()
            // 兜底：5 秒还没人会话来处理，就再踢一次
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, self.status == .working("准备翻译…") else { return }
                self.kick()
            }
        }
    }

    func translation(for text: String) -> String? {
        guard isNeeded else { return nil }
        return lookup(text)
    }

    /// 查单个词（点词看含义）。插队到待翻队列头部，不影响整首歌的进度。
    func requestWord(_ raw: String) {
        loadCacheIfNeeded()
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !TextUtil.isBlankOrSymbol(word) else { return }
        guard lookup(word) == nil else { return }
        if !pending.contains(word) { pending.insert(word, at: 0) }
        if !running { kick() }
    }

    func retry() {
        let missing = allTexts.filter { lookup($0) == nil }
        guard !missing.isEmpty else {
            status = .ready
            return
        }
        retryBudget = 2
        for t in missing where !pending.contains(t) { pending.append(t) }
        status = .working("重试中…")
        if !running { kick() }
    }

    /// 切换目标语言：清掉旧语言的译文，重新排队列
    func updateTarget(_ lang: Locale.Language) {
        guard lang.minimalIdentifier != target.minimalIdentifier else { return }
        target = lang
        translations = [:]
        let missing = allTexts.filter { !TextUtil.isBlankOrSymbol($0) && lookup($0) == nil }
        guard !missing.isEmpty else { return }
        retryBudget = 2
        for t in missing where !pending.contains(t) { pending.append(t) }
        status = .working("准备翻译…")
        if !running { kick() }
    }

    // MARK: 会话

    private func kick() {
        var c = TranslationSession.Configuration(source: source, target: target)
        c.invalidate()
        config = c
    }

    /// 由 SwiftUI 的 translationTask 调用，session 在这里常驻
    func consume(_ session: TranslationSession) async {
        guard !running else { return }
        running = true
        Diag.log("session start")
        defer {
            running = false
            Diag.log("session end")
        }

        while !Task.isCancelled {
            if pending.isEmpty {
                try? await Task.sleep(nanoseconds: idlePoll)
                continue
            }

            let batch = Array(pending.prefix(batchSize))
            pending.removeFirst(batch.count)
            status = .working(translations.isEmpty ? "翻译中…" : "翻译中… \(translations.count) 行")

            let requests = batch.enumerated().map {
                TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
            }

            do {
                let responses = try await withTimeout(300) {
                    try await session.translations(from: requests)
                }
                var fresh: [String: String] = [:]
                for r in responses {
                    guard let idx = r.clientIdentifier.flatMap(Int.init), batch.indices.contains(idx) else { continue }
                    let text = r.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { fresh[batch[idx]] = text }
                }
                guard !fresh.isEmpty else {
                    status = .unavailable("翻译返回为空，稍后可重试")
                    continue
                }
                for (k, v) in fresh {
                    cache[cacheKey(k, target)] = v
                    translations[k] = v
                }
                scheduleSave()
                status = pending.isEmpty ? .ready : .working("翻译中… \(translations.count) 行")
            } catch {
                let ns = error as NSError
                let cancelled = ns.domain == NSCocoaErrorDomain && ns.code == 3072
                let notInstalled = "\(error)".lowercased().contains("notinstalled")

                // 把这一批放回队首，别丢
                pending.insert(contentsOf: batch, at: 0)

                if cancelled || notInstalled {
                    if retryBudget > 0 {
                        retryBudget -= 1
                        status = .working("等待语言包就绪，20 秒后自动重试…")
                        onNeedsDownload?()
                        try? await Task.sleep(nanoseconds: 20_000_000_000)
                        continue
                    }
                    status = .unavailable("翻译被取消：需要在系统弹窗中允许下载语言包")
                    pending.removeAll()
                    continue
                }

                status = .unavailable("翻译未完成：\(TextUtil.short("\(error)", limit: 70))")
                pending.removeAll()
                continue
            }
        }
    }

    // MARK: 缓存

    private func lookup(_ text: String) -> String? {
        translations[text] ?? cache[cacheKey(text, target)]
    }

    private func cacheKey(_ text: String, _ lang: Locale.Language) -> String {
        "\(lang.minimalIdentifier)|\(text)"
    }

    private var cacheURL: URL? {
        Paths.base.appendingPathComponent("translations.json")
    }

    private func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let obj = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        cache = obj
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        guard let url = cacheURL else { return }
        var trimmed = cache
        if trimmed.count > 6000 {
            trimmed = Dictionary(uniqueKeysWithValues: Array(trimmed.prefix(6000)))
        }
        if let data = try? JSONEncoder().encode(trimmed) {
            try? data.write(to: url)
        }
    }

    // MARK: 工具

    private func label(_ l: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: l.minimalIdentifier) ?? l.minimalIdentifier
    }

    nonisolated static func detectLanguage(in text: String) -> Locale.Language? {
        let sample = String(text.prefix(1200))
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let code = recognizer.dominantLanguage?.rawValue else { return nil }
        return Locale.Language(identifier: code)
    }

    private struct TimeoutError: Error {}

    private func withTimeout<T>(_ seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            guard let first = try await group.next() else { throw TimeoutError() }
            group.cancelAll()
            return first
        }
    }
}

extension TranslationEngine {
    func debugSetTranslations(_ dict: [String: String]) {
        translations = dict
        status = .ready
        isNeeded = true
    }
}
