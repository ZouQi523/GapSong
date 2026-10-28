import Foundation

// MARK: - 一次错误提交

/// 一个空的判分快照。逐空保存，跳过的空也保留位置，
/// 这样部分填写后仍能把「第几个空 / 原句第几个词」对回去。
struct MistakeBlank: Codable, Equatable {
    /// 第几个空（0-based，按 blankIndices 顺序）
    var ordinal: Int
    /// 原句里的词下标
    var wordIndex: Int
    /// 期望的词（原文）
    var expected: String
    /// 用户这次填的内容（跳过为空）
    var actual: String
    /// 用户主动跳过 / 没填
    var skipped: Bool

    init(ordinal: Int, wordIndex: Int, expected: String, actual: String, skipped: Bool) {
        self.ordinal = ordinal
        self.wordIndex = wordIndex
        self.expected = expected
        self.actual = actual
        self.skipped = skipped
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ordinal = try c.decodeIfPresent(Int.self, forKey: .ordinal) ?? 0
        wordIndex = try c.decodeIfPresent(Int.self, forKey: .wordIndex) ?? -1
        expected = try c.decodeIfPresent(String.self, forKey: .expected) ?? ""
        actual = try c.decodeIfPresent(String.self, forKey: .actual) ?? ""
        skipped = try c.decodeIfPresent(Bool.self, forKey: .skipped) ?? actual.isEmpty
    }

    /// 这一空是否算填错（跳过不算错）。
    /// 必须复用整体判分的口径：4 / four、缩写撇号等被判分接受的写法不能在这里标成错。
    var isWrong: Bool {
        guard !skipped else { return false }
        return !DictationJudge.judge(expected: expected, actual: actual).isCorrect
    }
}

/// 一次「真正提交且判错」的历史记录
struct MistakeAttempt: Codable, Identifiable, Equatable {
    var id: UUID
    var submittedAt: Date
    /// song / bank / mistakes（原始来源，展示时再映射成中文）
    var source: String
    /// 当次填空比例 0...1
    var ratio: Double
    /// 用户原始输入缓冲（含用于跳空的空格标记）
    var rawInput: String
    /// 当时的译文
    var translation: String?
    /// 是否发生在「看答案后 → 再试试」之后（不计分，但仍然记录错误）
    var wasRetry: Bool
    /// 逐空快照
    var blanks: [MistakeBlank]

    init(
        id: UUID = UUID(),
        submittedAt: Date = Date(),
        source: String,
        ratio: Double,
        rawInput: String,
        translation: String?,
        wasRetry: Bool,
        blanks: [MistakeBlank]
    ) {
        self.id = id
        self.submittedAt = submittedAt
        self.source = source
        self.ratio = ratio
        self.rawInput = rawInput
        self.translation = translation
        self.wasRetry = wasRetry
        self.blanks = blanks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        submittedAt = try c.decodeIfPresent(Date.self, forKey: .submittedAt) ?? Date()
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "song"
        ratio = try c.decodeIfPresent(Double.self, forKey: .ratio) ?? 0
        rawInput = try c.decodeIfPresent(String.self, forKey: .rawInput) ?? ""
        translation = try c.decodeIfPresent(String.self, forKey: .translation)
        wasRetry = try c.decodeIfPresent(Bool.self, forKey: .wasRetry) ?? false
        blanks = try c.decodeIfPresent([MistakeBlank].self, forKey: .blanks) ?? []
    }

    var sourceLabel: String { MistakeBook.sourceLabel(source) }

    var wrongBlankCount: Int { blanks.filter(\.isWrong).count }

    var skippedBlankCount: Int { blanks.filter(\.skipped).count }

    var filledBlankCount: Int { blanks.filter { !$0.skipped }.count }

    /// 给列表/回看用的简短输入
    var inputSummary: String {
        let parts = blanks.filter { !$0.skipped }.map(\.actual)
        return parts.isEmpty ? "（未填写）" : parts.joined(separator: " / ")
    }
}

// MARK: - 一道错题（同一句合并）

struct MistakeEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    /// 最近一次记录时的译文
    var translation: String?
    var title: String
    var artist: String
    /// 原句时间（秒），没有时间轴时为 nil
    var lineTime: TimeInterval?
    var firstSeenAt: Date
    var lastSeenAt: Date
    /// 按提交顺序保存，不自动丢弃
    var attempts: [MistakeAttempt]

    init(
        id: UUID = UUID(),
        text: String,
        translation: String?,
        title: String,
        artist: String,
        lineTime: TimeInterval?,
        firstSeenAt: Date,
        lastSeenAt: Date,
        attempts: [MistakeAttempt]
    ) {
        self.id = id
        self.text = text
        self.translation = translation
        self.title = title
        self.artist = artist
        self.lineTime = lineTime
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.attempts = attempts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        translation = try c.decodeIfPresent(String.self, forKey: .translation)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        lineTime = try c.decodeIfPresent(TimeInterval.self, forKey: .lineTime)
        firstSeenAt = try c.decodeIfPresent(Date.self, forKey: .firstSeenAt) ?? Date()
        lastSeenAt = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt) ?? firstSeenAt
        attempts = try c.decodeIfPresent([MistakeAttempt].self, forKey: .attempts) ?? []
    }

    var key: String {
        MistakeBook.key(text: text, title: title, artist: artist)
    }

    var sourceLabel: String {
        if artist.isEmpty { return title }
        if title.isEmpty { return artist }
        return "\(title) · \(artist)"
    }

    var attemptCount: Int { attempts.count }

    var lastAttempt: MistakeAttempt? { attempts.last }

    var lastSeenLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: lastSeenAt)
    }
}

// MARK: - 持久化

/// 错题本：与用户主动收藏完全分开，只在真正提交且判错时写入。
@MainActor
final class MistakeBook: ObservableObject {
    @Published private(set) var entries: [MistakeEntry] = []
    /// 读取失败（原文件已备份或进入只读保护）
    @Published private(set) var loadError: String?
    /// 最近一次写入失败
    @Published private(set) var saveError: String?
    /// 读取失败时原始文件的备份位置
    @Published private(set) var backupURL: URL?

    private let url: URL
    /// 原文件无法备份时进入只读，绝不覆盖历史
    private var readOnly = false

    /// 给 UI 的统一警告
    var storageWarning: String? { saveError ?? loadError }

    init(url: URL = Paths.mistakesURL) {
        self.url = url
        load()
    }

    var count: Int { entries.count }

    var totalAttempts: Int { entries.reduce(0) { $0 + $1.attempts.count } }

    var isEmpty: Bool { entries.isEmpty }

    /// 最近错过的排在前面（只影响展示，不改存储顺序）
    var recentEntries: [MistakeEntry] {
        entries.sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    func entry(for question: PracticeQuestion?) -> MistakeEntry? {
        guard let question else { return nil }
        let key = Self.key(text: question.text, title: question.title, artist: question.artist)
        return entries.first { $0.key == key }
    }

    func attempts(for question: PracticeQuestion?) -> [MistakeAttempt] {
        entry(for: question)?.attempts ?? []
    }

    func attemptCount(for question: PracticeQuestion?) -> Int {
        entry(for: question)?.attempts.count ?? 0
    }

    func lastAttempt(for question: PracticeQuestion?) -> MistakeAttempt? {
        entry(for: question)?.attempts.last
    }

    /// 记录一次错误提交；同一句（歌手+歌名+原句）合并到同一个条目并追加历史。
    /// - Returns: 是否成功落盘（失败时 UI 会显示 `saveError`，不会假装已保存）
    @discardableResult
    func record(question: PracticeQuestion, translation: String?, attempt: MistakeAttempt) -> Bool {
        let key = Self.key(text: question.text, title: question.title, artist: question.artist)

        if let index = entries.firstIndex(where: { $0.key == key }) {
            entries[index].attempts.append(attempt)
            entries[index].lastSeenAt = attempt.submittedAt
            if let translation, !translation.isEmpty {
                entries[index].translation = translation
            }
            if entries[index].lineTime == nil {
                entries[index].lineTime = question.lineTime
            }
        } else {
            entries.append(
                MistakeEntry(
                    text: question.text,
                    translation: (translation?.isEmpty == true ? nil : translation),
                    title: question.title,
                    artist: question.artist,
                    lineTime: question.lineTime,
                    firstSeenAt: attempt.submittedAt,
                    lastSeenAt: attempt.submittedAt,
                    attempts: [attempt]
                )
            )
        }
        return save()
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        let before = entries.count
        entries.removeAll { $0.id == id }
        guard entries.count != before else { return true }
        return save()
    }

    @discardableResult
    func clear() -> Bool {
        guard !entries.isEmpty else { return true }
        entries.removeAll()
        return save()
    }

    // MARK: 身份

    /// 身份 = 歌手 + 歌名 + 原句；大小写/多余空白不计，避免同名不同歌手混淆。
    nonisolated static func key(text: String, title: String, artist: String) -> String {
        let t = text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let ti = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(ar)|\(ti)|\(t)"
    }

    nonisolated static func sourceLabel(_ raw: String) -> String {
        switch raw {
        case "song": return "当前歌曲"
        case "bank": return "收藏歌词"
        case "mistakes": return "错题本"
        default: return raw
        }
    }

    // MARK: 落盘

    private struct Store: Codable {
        var version: Int
        var entries: [MistakeEntry]
    }

    /// 只认当前版本；版本号不认识时按损坏文件保护，不静默改写历史
    private static let storeVersion = 1

    private func load() {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        guard !isDirectory.boolValue else {
            readOnly = true
            loadError = "错题本路径是一个目录，无法作为文件读取；为避免破坏历史，本次运行不会写入错题本。"
            Diag.log("mistakes: load blocked (path is a directory)")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try Data(contentsOf: url)
            if let store = try? decoder.decode(Store.self, from: data) {
                guard store.version == Self.storeVersion else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                entries = store.entries
            } else {
                // 兼容早期可能的裸数组格式
                entries = try decoder.decode([MistakeEntry].self, from: data)
            }
            loadError = nil
            Diag.log("mistakes: loaded \(entries.count) 条 / \(totalAttempts) 次")
        } catch {
            // 读失败：先复制一份原始文件并逐字节核对，再允许后续写新文件；备份失败则只读保护
            let stamp = "\(Self.timestamp())-\(UUID().uuidString.prefix(6))"
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("mistakes.corrupt-\(stamp).json")
            do {
                let original = try Data(contentsOf: url)
                try FileManager.default.copyItem(at: url, to: backup)
                guard let copied = try? Data(contentsOf: backup), copied == original else {
                    throw CocoaError(.fileWriteUnknown)
                }
                backupURL = backup
                loadError = "错题本读取失败，原始文件已备份为 \(backup.lastPathComponent)。后续错误会写入新文件，旧记录不会丢失。"
                Diag.log("mistakes: load failed \(error); backed up to \(backup.path)")
            } catch {
                readOnly = true
                loadError = "错题本读取失败，且无法备份原始文件；为避免覆盖历史，本次运行不会写入错题本。"
                Diag.log("mistakes: load failed \(error); backup failed \(error)")
            }
        }
    }

    private func save() -> Bool {
        guard !readOnly else {
            saveError = "错题本处于只读保护：原始文件无法备份，本次修改未写入"
            Diag.log("mistakes: save blocked (read-only)")
            return false
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let store = Store(version: Self.storeVersion, entries: entries)
            let data = try encoder.encode(store)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            // 写完读回核对：不能因为路径被占用/不可写而假报保存成功
            guard let written = try? Data(contentsOf: url), written == data else {
                throw CocoaError(.fileWriteUnknown)
            }
            saveError = nil
            return true
        } catch {
            saveError = "错题本写入失败：\(error.localizedDescription)"
            Diag.log("mistakes: save failed \(error)")
            return false
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
