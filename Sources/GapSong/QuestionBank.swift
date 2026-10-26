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

/// 用户手动收藏的听写题库，落盘成 JSON
@MainActor
final class QuestionBank: ObservableObject {
    @Published private(set) var items: [BankQuestion] = []

    private let url: URL

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

    /// 返回 true = 新加入；false = 已经在题库里
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

        items.append(
            BankQuestion(
                id: UUID(),
                text: trimmed,
                translation: translation?.isEmpty == true ? nil : translation,
                title: title,
                artist: artist,
                lineTime: max(0, lineTime),
                addedAt: Date()
            )
        )
        save()
        Diag.log("bank: add \"\(trimmed)\" from \(title) → \(items.count) 句")
        return true
    }

    func remove(id: UUID) {
        let before = items.count
        items.removeAll { $0.id == id }
        guard items.count != before else { return }
        save()
        Diag.log("bank: remove → \(items.count) 句")
    }

    func remove(text: String, title: String) {
        let key = BankQuestion.key(text: text, title: title)
        let before = items.count
        items.removeAll { $0.key == key }
        guard items.count != before else { return }
        save()
        Diag.log("bank: remove line → \(items.count) 句")
    }

    /// 点一次加入、再点一次移除。返回 true = 现在在题库里
    @discardableResult
    func toggle(
        text: String,
        translation: String?,
        title: String,
        artist: String,
        lineTime: TimeInterval
    ) -> Bool {
        if contains(text: text, title: title) {
            remove(text: text, title: title)
            return false
        }
        return add(text: text, translation: translation, title: title, artist: artist, lineTime: lineTime)
    }

    func clear() {
        guard !items.isEmpty else { return }
        items.removeAll()
        save()
        Diag.log("bank: clear")
    }

    // MARK: 落盘

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            items = try decoder.decode([BankQuestion].self, from: data)
            Diag.log("bank: loaded \(items.count) 句")
        } catch {
            Diag.log("bank: load failed \(error)")
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(items)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            Diag.log("bank: save failed \(error)")
        }
    }
}
