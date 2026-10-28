import Foundation

/// 题库里的一句：歌词原文 + 所属歌曲，练习时不需要音乐也能出题
struct BankQuestion: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    var translation: String?
    var title: String
    var artist: String
    /// 这句在原曲里的时间（秒），0 表示未知；只用于回看，不影响出题
    var lineTime: Double
    var addedAt: Date

    var sourceLabel: String {
        if artist.isEmpty { return title }
        if title.isEmpty { return artist }
        return "\(title) · \(artist)"
    }

    /// 去重口径：同一首歌的同一句只存一次（大小写、多余空格不计）
    var key: String { Self.key(text: text, title: title) }

    static func key(text: String, title: String) -> String {
        let t = text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let n = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(n)|\(t)"
    }
}

/// 旧版 `questions.json` 可能缺 artist/lineTime 等展示字段，缺了用安全默认值补上。
///
/// 但 `id` / `text` 是这条收藏的身份与原文：缺一个就无法解释这条记录。
/// 这时必须让整份文件按损坏文件处理（先备份再重建），不能凭空造一个随机 ID
/// 或空白原文把原始字节覆盖掉。
extension BankQuestion {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .text, in: c,
                debugDescription: "收藏条目缺少原文，不能重建身份"
            )
        }
        translation = try c.decodeIfPresent(String.self, forKey: .translation)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        lineTime = try c.decodeIfPresent(Double.self, forKey: .lineTime) ?? 0
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }
}

/// 一次收藏增删的结果：UI 必须据此给出真实提示，不能无条件说「已收藏」
enum BankMutation: Equatable {
    /// 新加入并已成功落盘（或当前会话内确实已在库里）
    case added
    /// 取消收藏并已成功落盘
    case removed
    /// 这句本来就在收藏里
    case duplicate
    /// 要取消/删除的条目已经不在了
    case notFound
    /// 落盘失败（只读保护 / 磁盘或权限异常），改动已回滚
    case failed(String)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    /// 界面提示文案：失败要如实说失败，不能一律显示「已收藏」
    func toastText(count: Int) -> String {
        switch self {
        case .added: return "已收藏 · 共 \(count) 句"
        case .removed: return "已取消收藏 · 共 \(count) 句"
        case .duplicate: return "这句已经在收藏里 · 共 \(count) 句"
        case .notFound: return "这句已经不在收藏里 · 共 \(count) 句"
        case .failed(let message): return "收藏未保存：\(message)"
        }
    }
}

/// 用户手动收藏的听写题库，落盘成 JSON（沿用旧文件名与裸数组格式）
@MainActor
final class QuestionBank: ObservableObject {
    @Published private(set) var items: [BankQuestion] = []
    /// 读取失败（原文件已备份或进入只读保护）
    @Published private(set) var loadError: String?
    /// 最近一次写入失败
    @Published private(set) var saveError: String?
    /// 读取失败时原始文件的备份位置
    @Published private(set) var backupURL: URL?

    private let url: URL
    /// 原文件无法备份时进入只读，绝不覆盖历史收藏
    private var readOnly = false

    /// 给 UI 的统一警告
    var storageWarning: String? { saveError ?? loadError }

    init(url: URL = Paths.bankURL) {
        self.url = url
        load()
    }

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    func contains(text: String, title: String) -> Bool {
        let key = BankQuestion.key(text: text, title: title)
        return items.contains { $0.key == key }
    }

    // MARK: 增删

    /// 返回 true = 新加入且已落盘；false = 已存在或写入失败（失败时 `storageWarning` 有说明）
    @discardableResult
    func add(
        text: String,
        translation: String?,
        title: String,
        artist: String,
        lineTime: TimeInterval
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !contains(text: trimmed, title: title) else { return false }

        let question = BankQuestion(
            id: UUID(),
            text: trimmed,
            translation: translation?.isEmpty == true ? nil : translation,
            title: title,
            artist: artist,
            lineTime: max(0, lineTime),
            addedAt: Date()
        )
        items.append(question)
        guard persist() else {
            // 写失败就把内存里的改动撤回：界面不能显示成一个并不存在的收藏
            items.removeAll { $0.id == question.id }
            Diag.log("bank: add rolled back \"\(trimmed)\"")
            return false
        }
        Diag.log("bank: add \"\(trimmed)\" from \(title) → \(items.count) 句")
        return true
    }

    /// 返回 true = 删除已落盘（条目不存在也算成功，因为没有需要写的改动）
    @discardableResult
    func remove(id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return true }
        let removed = items.remove(at: index)
        guard persist() else {
            items.insert(removed, at: min(index, items.count))
            Diag.log("bank: remove rolled back")
            return false
        }
        Diag.log("bank: remove → \(items.count) 句")
        return true
    }

    @discardableResult
    func remove(text: String, title: String) -> Bool {
        let key = BankQuestion.key(text: text, title: title)
        let before = items
        items.removeAll { $0.key == key }
        guard items.count != before.count else { return true }
        guard persist() else {
            items = before
            Diag.log("bank: remove-line rolled back")
            return false
        }
        Diag.log("bank: remove line → \(items.count) 句")
        return true
    }

    /// 点一次加入、再点一次移除。返回本次操作的真实结果（含写失败）
    @discardableResult
    func toggle(
        text: String,
        translation: String?,
        title: String,
        artist: String,
        lineTime: TimeInterval
    ) -> BankMutation {
        if contains(text: text, title: title) {
            return remove(text: text, title: title) ? .removed : .failed(saveError ?? "写入失败")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notFound }
        return add(
            text: trimmed, translation: translation, title: title,
            artist: artist, lineTime: lineTime
        ) ? .added : .failed(saveError ?? "写入失败")
    }

    @discardableResult
    func clear() -> Bool {
        guard !items.isEmpty else { return true }
        let before = items
        items.removeAll()
        guard persist() else {
            items = before
            Diag.log("bank: clear rolled back")
            return false
        }
        Diag.log("bank: clear")
        return true
    }

    // MARK: 落盘

    private func load() {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        // 「文件不存在」是正常的首次启动，不算读取失败
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        // 路径被目录占用：绝不能当成空库然后在后面“成功”写文件
        guard !isDirectory.boolValue else {
            readOnly = true
            loadError = "收藏路径是一个目录（\(url.lastPathComponent)），无法作为收藏文件读取；为避免破坏数据，本次运行不会写入收藏。"
            Diag.log("bank: load blocked (path is a directory) \(url.path)")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            protectCorruptFile(error, reason: "收藏读取失败")
            return
        }

        do {
            // 只认旧版的裸数组；格式不认识的一律按损坏文件保护，不静默改写。
            items = try decoder.decode([BankQuestion].self, from: data)
            loadError = nil
            Diag.log("bank: loaded \(items.count) 句")
        } catch {
            protectCorruptFile(error, reason: "收藏解析失败")
        }
    }

    /// 坏文件必须先备份成功（且逐字节核对一致），才允许后续写新文件；
    /// 备份不了就只读保护，绝不覆盖原始字节。
    private func protectCorruptFile(_ error: Error, reason: String) {
        let stamp = "\(Self.timestamp())-\(UUID().uuidString.prefix(6))"
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("questions.corrupt-\(stamp).json")
        do {
            let original = try Data(contentsOf: url)
            try FileManager.default.copyItem(at: url, to: backup)
            guard let copied = try? Data(contentsOf: backup), copied == original else {
                throw CocoaError(.fileWriteUnknown)
            }
            backupURL = backup
            loadError = "\(reason)，原始文件已备份为 \(backup.lastPathComponent)。后续收藏会写入新文件，旧记录不会丢失。"
            Diag.log("bank: load failed \(error); backed up to \(backup.path)")
        } catch {
            readOnly = true
            loadError = "\(reason)，且无法备份原始文件；为避免覆盖旧收藏，本次运行不会写入收藏。"
            Diag.log("bank: load failed \(error); backup failed \(error)")
        }
    }

    private func persist() -> Bool {
        guard !readOnly else {
            saveError = "收藏处于只读保护：原始文件无法备份，本次修改未写入"
            Diag.log("bank: save blocked (read-only)")
            return false
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(items)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            // 写完再读回核对：父路径不可写、被替换成目录等情况下不能“假报成功”
            guard let written = try? Data(contentsOf: url), written == data else {
                throw CocoaError(.fileWriteUnknown)
            }
            saveError = nil
            return true
        } catch {
            saveError = "收藏写入失败：\(error.localizedDescription)"
            Diag.log("bank: save failed \(error)")
            return false
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
