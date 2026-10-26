import Foundation
import AppKit

// MARK: - 筛出适合听写的句子

enum PracticeFilter {
    /// 太短的句子听不清，不适合听写
    static let minLineSpan: TimeInterval = 1.2

    /// 一句唱到哪里算完。
    ///
    /// LRC 只给行首时间，所以「这一句的结束」= 下一句的开始。
    /// 这里刻意**不设上限**：早期版本给每句封顶 8 秒，慢歌和拖长音的句子
    /// 会被直接切断，听起来就是「还没唱完就暂停了」。
    static func endTime(lines: [LyricLine], index: Int, trackDuration: TimeInterval) -> TimeInterval {
        guard lines.indices.contains(index) else { return 0 }
        let start = lines[index].time

        var end: TimeInterval
        if index + 1 < lines.count {
            end = lines[index + 1].time
        } else {
            // 最后一句没有下一句可参考，用这首歌的平均行距估一个
            let gaps = zip(lines, lines.dropFirst())
                .map { $0.1.time - $0.0.time }
                .filter { $0 > 0.3 }
            let average = gaps.isEmpty ? 5 : gaps.reduce(0, +) / Double(gaps.count)
            end = start + min(max(average, 2), 12)
        }

        if trackDuration > start + 0.5 { end = min(end, trackDuration) }
        return max(end, start + 0.5)
    }

    /// 返回可以拿来听写的行下标（升序）
    static func practiceableIndices(lines: [LyricLine], trackDuration: TimeInterval) -> [Int] {
        var result: [Int] = []
        var previousKey: String?

        for i in lines.indices {
            let line = lines[i]
            // 「♪」「(間奏)」「Oh oh oh」这类没有信息量的行直接跳过
            guard !TextUtil.isBlankOrSymbol(line.text) else { continue }
            // 只练英文：拉丁字母占比不足的（中文/日文/韩文行）跳过
            guard latinRatio(line.text) >= 0.9 else { continue }

            let words = line.text.split(whereSeparator: { $0.isWhitespace })
            guard words.count >= 3 else { continue }
            guard Set(words.map { $0.lowercased() }).count >= 2 else { continue }

            let span = endTime(lines: lines, index: i, trackDuration: trackDuration) - line.time
            guard span >= minLineSpan else { continue }

            // 连续重复的同一句只练一次
            let key = line.text.lowercased().trimmingCharacters(in: .whitespaces)
            if key == previousKey { continue }
            previousKey = key

            result.append(i)
        }
        return result
    }

    static func latinRatio(_ text: String) -> Double {
        var letters = 0
        var latin = 0
        for ch in text where ch.isLetter {
            letters += 1
            if let v = ch.unicodeScalars.first?.value, isLatin(v) { latin += 1 }
        }
        guard letters > 0 else { return 0 }
        return Double(latin) / Double(letters)
    }

    private static func isLatin(_ v: UInt32) -> Bool {
        if v >= 0x41 && v <= 0x5A { return true }       // A-Z
        if v >= 0x61 && v <= 0x7A { return true }       // a-z
        if v >= 0xC0 && v <= 0x24F { return true }      // Latin-1 Supplement / Extended-A,B
        if v >= 0x1E00 && v <= 0x1EFF { return true }   // Latin Extended Additional
        return false
    }
}

// MARK: - 一道题

/// 题目与来源解耦：歌曲模式带时间轴（要播放/暂停），题库模式只有文本（离线作答）
struct PracticeQuestion: Identifiable, Equatable {
    let id = UUID()
    var text: String
    /// 收藏时存下的译文；没有就现场查翻译缓存
    var translation: String?
    var title: String
    var artist: String
    /// 歌曲模式：这一句的起止时间（秒）
    var start: TimeInterval?
    var end: TimeInterval?
    /// 原句时间（歌曲/收藏/错题都有，用于收藏与错题记录）
    var lineTime: TimeInterval?
    /// 收藏歌词模式下对应的条目
    var bankID: UUID?
    /// 错题本模式下对应的条目
    var mistakeID: UUID?

    var sourceLabel: String {
        if artist.isEmpty { return title }
        if title.isEmpty { return artist }
        return "\(title) · \(artist)"
    }
}

// MARK: - 听写状态机

/// 练习流程：
///
/// 1. 进入练习 → `.setup`：选填空比例（30%–100%）和题目来源；
/// 2. 歌曲模式：播放 → 唱到句末自动暂停并回到句首 → 答题 → 判分 →（可重听）→ 揭示 → 下一句；
/// 3. 题库模式：完全不碰音乐，直接从收藏的句子里出题。
@MainActor
final class PracticeEngine: ObservableObject {

    enum Phase: Equatable {
        case setup
        case idle
        case listening
        case asking
        case revealed
    }

    enum Source: String, CaseIterable, Identifiable {
        case song
        case bank
        case mistakes

        var id: String { rawValue }

        var label: String {
            switch self {
            case .song: return "当前歌曲"
            case .bank: return "收藏歌词"
            case .mistakes: return "错题本"
            }
        }

        var badge: String {
            switch self {
            case .song: return ""
            case .bank: return "收藏歌词"
            case .mistakes: return "错题本"
            }
        }
    }

    struct Stats: Equatable {
        var correct = 0
        var wrong = 0
    }

    @Published private(set) var phase: Phase = .setup
    @Published private(set) var source: Source = .song
    @Published private(set) var verdict: DictationJudge.Result?
    @Published private(set) var notice: String?
    /// 当前正在练的题（答题阶段也保留，用于取译文做语义提示）
    @Published private(set) var current: PracticeQuestion?
    /// 揭示答案后展示的题
    @Published private(set) var revealed: PracticeQuestion?
    @Published private(set) var progress = ""
    @Published private(set) var stats = Stats()
    @Published private(set) var score = 0
    @Published private(set) var streak = 0
    /// 刚看过答案又点了「再试试」：这次只验证，不计分
    @Published private(set) var isRetry = false
    /// 当前这句要用户填的词下标（基于空格分词）
    @Published private(set) var blankIndices: [Int] = []
    /// 连续输入缓冲：整句按每个空的词长自动切分（空格作为“跳过当前空”的标记）
    @Published var input = "" {
        didSet {
            // 用户一改答案，上一轮的「听错了」提示就该消失
            if verdict != nil, input != oldValue { verdict = nil }
        }
    }

    /// 需要键盘输入时回调（由 OverlayController 抢焦点）
    var onRequestFocus: (() -> Void)?

    private let state: PlayerState
    private let watcher: MusicControlling
    private let settings: Settings
    private let bank: QuestionBank
    private let mistakeBook: MistakeBook

    private var enabled = false
    private var questions: [PracticeQuestion] = []
    private var cursor = 0
    /// 本次会话是否只练某一条（收藏/错题），用于「再来一遍」
    private var sessionOnlyID: UUID?
    private var lyricsLines: [LyricLine] = []
    private var tickTask: Task<Void, Never>?
    private var autoTask: Task<Void, Never>?
    /// 刚下发过命令，等一个「命令之后」的采样再做边界判断，避免用旧位置误触
    private var lastCommandAt: Date?
    private var pausedByUs = false
    private var lastTrackKey: String?
    private var lastGeneration = -1
    /// 采样消失（歌播完了 / Music 退出）的起点，用来避免卡在「正在听」
    private var missingSince: Date?

    init(
        state: PlayerState,
        watcher: MusicControlling,
        settings: Settings,
        bank: QuestionBank,
        mistakes: MistakeBook
    ) {
        self.state = state
        self.watcher = watcher
        self.settings = settings
        self.bank = bank
        self.mistakeBook = mistakes
    }

    // MARK: 对外状态

    var ratio: Double { settings.practiceRatio }
    var isSongMode: Bool { source == .song }
    var sourceTitle: String { current?.title ?? "" }
    var sourceArtist: String { current?.artist ?? "" }

    /// 当前题目的判分期望：所有被挖空的词按顺序拼回去
    var expectedAnswer: String {
        PracticeBlanks.expectedAnswer(in: current?.text ?? "", blankIndices: blankIndices)
    }

    var blankWordCount: Int { blankIndices.count }

    /// 当前空的下标：输入按每个空的词长切分，填满一个就自动“跳”到下一个
    var activeBlank: Int { parseBlanks().active }

    /// 已经填了内容的横线数量
    var filledBlankCount: Int {
        parseBlanks().slices.filter { !$0.isEmpty }.count
    }

    /// 某个横线当前要显示的字符
    func typedChars(forBlank ordinal: Int) -> [Character] {
        let slices = parseBlanks().slices
        guard slices.indices.contains(ordinal) else { return [] }
        return Array(slices[ordinal])
    }

    private struct BlankParse {
        var slices: [String]
        var active: Int
        var overflow: String
    }

    private func blankLengths() -> [Int] {
        let words = PracticeBlanks.words(in: current?.text ?? "")
        return blankIndices.map { words.indices.contains($0) ? words[$0].chars.count : 0 }
    }

    /// 把连续输入切成每个空的内容：
    /// - 字母按词长依次填进当前空，填满自动进入下一个空；
    /// - 空格是手动“跳过当前空”的标记（填了一半也能跳过）。
    private func parseBlanks() -> BlankParse {
        let lengths = blankLengths()
        guard !lengths.isEmpty else { return BlankParse(slices: [], active: 0, overflow: "") }

        var tokens: [Character] = []
        for ch in input {
            if ch == " " {
                tokens.append(" ")
                continue
            }
            let lower = ch.lowercased()
            guard lower.count == 1, let c = lower.first,
                  c.isASCII, c.isLetter || c.isNumber || c == "-" else { continue }
            tokens.append(c)
        }

        var slices = Array(repeating: "", count: lengths.count)
        var ti = 0
        var bi = 0
        while bi < lengths.count {
            if ti < tokens.count, tokens[ti] == " " {
                ti += 1
                bi += 1
                continue
            }
            let need = lengths[bi]
            var s = ""
            while ti < tokens.count, tokens[ti] != " ", s.count < need {
                s.append(tokens[ti])
                ti += 1
            }
            slices[bi] = s
            if s.count < need {
                if ti < tokens.count, tokens[ti] == " " {
                    ti += 1
                    bi += 1
                    continue
                }
                return BlankParse(slices: slices, active: bi, overflow: "")
            }
            bi += 1
        }
        let rest = String(tokens[ti...]).replacingOccurrences(of: " ", with: "")
        return BlankParse(slices: slices, active: max(0, lengths.count - 1), overflow: rest)
    }

    /// 第 ordinal 个空对应的原文词
    func expectedWord(atBlank ordinal: Int) -> String {
        guard blankIndices.indices.contains(ordinal), let text = current?.text else { return "" }
        let words = PracticeBlanks.words(in: text)
        let wordIndex = blankIndices[ordinal]
        guard words.indices.contains(wordIndex) else { return "" }
        return words[wordIndex].raw
    }

    var eligibleWordCount: Int {
        PracticeBlanks.words(in: current?.text ?? "").filter(\.isEligible).count
    }

    var isCurrentInBank: Bool {
        guard let current else { return false }
        return bank.contains(text: current.text, title: current.title)
    }

    func translation(for question: PracticeQuestion?) -> String? {
        guard let question else { return nil }
        if let stored = question.translation, !stored.isEmpty { return stored }
        return state.translator.translation(for: question.text)
    }

    func mistakeEntry(for question: PracticeQuestion?) -> MistakeEntry? {
        mistakeBook.entry(for: question)
    }

    func mistakeAttemptCount(for question: PracticeQuestion?) -> Int {
        mistakeBook.attemptCount(for: question)
    }

    func lastMistakeAttempt(for question: PracticeQuestion?) -> MistakeAttempt? {
        mistakeBook.lastAttempt(for: question)
    }

    var mistakeBookCount: Int { mistakeBook.count }

    // MARK: 开关

    /// 进入/退出练习模式。进入时先停在设置页，让用户选强度
    func setEnabled(_ on: Bool) {
        if on {
            endSession()
            enabled = false
            phase = .setup
            stats = Stats()
            score = 0
            streak = 0
            Diag.log("practice: setup")
        } else {
            endSession()
            enabled = false
            phase = .idle
            Diag.log("practice: disabled")
        }
    }

    /// 回到设置页重新选强度/来源（不动 practiceMode）
    func returnToSetup() {
        endSession()
        enabled = false
        phase = .setup
        stats = Stats()
        score = 0
        streak = 0
        Diag.log("practice: back to setup")
    }

    /// 从设置页 / 菜单 / 管理窗口开始一次练习。
    /// - Parameter onlyID: 只练收藏/错题里的某一条；nil 表示练整个库。
    func begin(source: Source, ratio: Double, onlyID: UUID? = nil) {
        // 切换来源前先彻底结束旧会话：停止计时、取消自动下一题、恢复被我们暂停的音乐
        stopTick()
        autoTask?.cancel()
        autoTask = nil
        if pausedByUs {
            watcher.send(.play)
            pausedByUs = false
        }
        lastCommandAt = nil
        missingSince = nil

        settings.practiceRatio = ratio
        self.source = source
        self.sessionOnlyID = onlyID
        enabled = true
        stats = Stats()
        score = 0
        streak = 0
        isRetry = false
        current = nil
        revealed = nil
        verdict = nil
        notice = nil
        progress = ""
        input = ""
        blankIndices = []
        Diag.log("practice: begin source=\(source.rawValue) ratio=\(Int(ratio * 100))% only=\(onlyID?.uuidString ?? "all")")

        switch source {
        case .song:
            startTick()
            loadSong(fromBeginning: true)
        case .bank:
            loadBank(onlyID: onlyID)
        case .mistakes:
            loadMistakes(onlyID: onlyID)
        }
    }

    private func endSession() {
        stopTick()
        autoTask?.cancel()
        autoTask = nil
        // 练习时是我们把歌停下的，退出要还回去
        if pausedByUs {
            watcher.send(.play)
            pausedByUs = false
        }
        lastCommandAt = nil
        missingSince = nil
        sessionOnlyID = nil
        resetContent()
    }

    private func resetContent() {
        current = nil
        revealed = nil
        verdict = nil
        notice = nil
        progress = ""
        input = ""
        blankIndices = []
    }

    // MARK: 题库

    /// 歌曲模式：按播放位置把可用于听写的行变成题目
    private func loadSong(fromBeginning: Bool) {
        lastTrackKey = state.snapshot?.track.cacheKey
        lastGeneration = state.lyricsGeneration

        autoTask?.cancel()
        verdict = nil
        revealed = nil
        input = ""

        guard let lyrics = state.lyrics, !lyrics.lines.isEmpty else {
            phase = .idle
            notice = "这首歌还没有歌词，匹配到之后会自动开始"
            return
        }

        lyricsLines = lyrics.lines
        let duration = state.snapshot?.track.duration ?? 0
        var indices = PracticeFilter.practiceableIndices(lines: lyricsLines, trackDuration: duration)

        guard !indices.isEmpty else {
            phase = .idle
            notice = "这首歌没有适合听写的英文句子"
            Diag.log("practice: no practiceable lines (\(lyricsLines.count) total)")
            return
        }

        if !fromBeginning {
            let now = state.position()
            if let first = indices.firstIndex(where: { lyricsLines[$0].time >= now - 1.0 }) {
                indices = Array(indices[first...])
            }
        }

        let track = state.snapshot?.track
        questions = indices.map { index in
            PracticeQuestion(
                text: lyricsLines[index].text,
                translation: nil,
                title: track?.title ?? "",
                artist: track?.artist ?? "",
                start: lyricsLines[index].time,
                end: PracticeFilter.endTime(lines: lyricsLines, index: index, trackDuration: duration),
                lineTime: lyricsLines[index].time
            )
        }
        cursor = 0
        Diag.log("practice: song session \(questions.count) 句, start at line \(indices.first ?? -1)")
        beginListening()
    }

    /// 收藏歌词模式：不读音乐、不发命令，直接出题
    private func loadBank(onlyID: UUID? = nil) {
        autoTask?.cancel()
        var items = bank.items
        if let onlyID {
            items = items.filter { $0.id == onlyID }
        } else {
            items.shuffle()
        }

        guard !items.isEmpty else {
            phase = .idle
            progress = ""
            current = nil
            revealed = nil
            notice = onlyID == nil
                ? "收藏歌词还是空的：播放时点歌词右侧的书签就能收藏"
                : "这句已经不在收藏里了"
            Diag.log("practice: favorites empty (only=\(onlyID?.uuidString ?? "all"))")
            return
        }

        questions = items.map { item in
            PracticeQuestion(
                text: item.text,
                translation: item.translation,
                title: item.title,
                artist: item.artist,
                start: nil,
                end: nil,
                lineTime: item.lineTime > 0 ? item.lineTime : nil,
                bankID: item.id
            )
        }
        cursor = 0
        stats = Stats()
        score = 0
        streak = 0
        isRetry = false
        requestTranslations()
        setCurrent(0)
        phase = .asking
        onRequestFocus?()
        Diag.log("practice: favorites session \(questions.count) 句")
    }

    /// 错题本模式：同样完全离线
    private func loadMistakes(onlyID: UUID? = nil) {
        autoTask?.cancel()
        var items = mistakeBook.entries
        if let onlyID {
            items = items.filter { $0.id == onlyID }
        } else {
            items.shuffle()
        }

        guard !items.isEmpty else {
            phase = .idle
            progress = ""
            current = nil
            revealed = nil
            notice = onlyID == nil
                ? "错题本还是空的：提交错误答案后会自动记录"
                : "这条错题已经不存在了"
            Diag.log("practice: mistakes empty (only=\(onlyID?.uuidString ?? "all"))")
            return
        }

        questions = items.map { item in
            PracticeQuestion(
                text: item.text,
                translation: item.translation,
                title: item.title,
                artist: item.artist,
                start: nil,
                end: nil,
                lineTime: item.lineTime,
                bankID: nil,
                mistakeID: item.id
            )
        }
        cursor = 0
        stats = Stats()
        score = 0
        streak = 0
        isRetry = false
        requestTranslations()
        setCurrent(0)
        phase = .asking
        onRequestFocus?()
        Diag.log("practice: mistakes session \(questions.count) 条")
    }

    /// 收藏/错题句子可能是在没开翻译时保存的，练之前补齐译文（离线、走本机翻译）
    private func requestTranslations() {
        let missing = questions
            .filter { ($0.translation ?? "").isEmpty }
            .map(\.text)
        guard !missing.isEmpty else { return }
        state.translator.request(missing, target: state.targetLanguage)
    }

    // MARK: 逐句流程

    private func setCurrent(_ index: Int) {
        guard questions.indices.contains(index) else { return }
        let question = questions[index]
        current = question
        blankIndices = PracticeBlanks.blankIndices(in: question.text, ratio: settings.practiceRatio)
        input = ""
        verdict = nil
        revealed = nil
        notice = nil
        isRetry = false
        updateProgress()
    }

    private func beginListening() {
        autoTask?.cancel()
        guard cursor < questions.count else {
            finish()
            return
        }

        setCurrent(cursor)
        phase = .listening
        missingSince = nil

        guard let start = current?.start else {
            // 没有时间轴就退化成直接答题（题库模式正常走不到这里）
            phase = .asking
            onRequestFocus?()
            return
        }

        watcher.seek(to: start, play: true)
        lastCommandAt = Date()
        pausedByUs = true
    }

    // MARK: 主循环

    private func startTick() {
        stopTick()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                // 听的时候要精确，闲着的时候别耗电
                let interval: UInt64 = (self?.phase == .listening) ? 50_000_000 : 400_000_000
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                self?.tick()
            }
        }
    }

    private func stopTick() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        guard enabled, source == .song else { return }
        checkContext()

        guard phase == .listening, cursor < questions.count,
              let question = current, let end = question.end else { return }

        // 歌播完 / Music 退出时采样会消失，别把界面永远卡在「正在听」。
        // 阈值给到 2.5s：流媒体缓冲时 player state 会短暂变 stopped，别误判。
        guard let snapshot = state.snapshot else {
            if let since = missingSince {
                if Date().timeIntervalSince(since) > 2.5 { finish(reason: "播放已结束") }
            } else {
                missingSince = Date()
            }
            return
        }
        missingSince = nil

        guard snapshot.playing else { return }
        if let issuedAt = lastCommandAt {
            // 留 0.2s 余量：命令下发瞬间可能有一个已经在路上的旧采样
            guard snapshot.sampledAt > issuedAt.addingTimeInterval(0.2) else { return }
            lastCommandAt = nil
        }

        // 句末延迟：正数是「多放一点再停」，负数是「提前停」。
        // 默认延后，宁可多听一个音，也不要把这一句的最后半拍切掉。
        guard state.position(at: Date()) >= end + settings.practiceTail else { return }

        // 停下来，并回到句首：之后无论是重播还是续播都从已知锚点出发
        pausedByUs = true
        watcher.send(.pause)
        if let start = question.start {
            watcher.seek(to: start, play: false)
        }
        lastCommandAt = Date()

        verdict = nil
        phase = .asking
        onRequestFocus?()
        Diag.log("practice: line \(cursor + 1)/\(questions.count) paused at \(String(format: "%.2f", end)) tail=\(settings.practiceTail)")
    }

    private func checkContext() {
        guard source == .song else { return }
        guard state.snapshot?.track.cacheKey != lastTrackKey
            || state.lyricsGeneration != lastGeneration else { return }
        loadSong(fromBeginning: false)
    }

    // MARK: 答题

    func submit() {
        guard phase == .asking, cursor < questions.count else { return }
        let parse = parseBlanks()

        // 只判用户真正填过的空：跳过/留空的横线不参与判错
        var expectedParts: [String] = []
        var actualParts: [String] = []
        for ordinal in parse.slices.indices {
            let actual = parse.slices[ordinal]
            guard !actual.isEmpty else { continue }
            expectedParts.append(expectedWord(atBlank: ordinal))
            actualParts.append(actual)
        }
        guard !expectedParts.isEmpty else { return }

        let result = DictationJudge.judge(
            expected: expectedParts.joined(separator: " "),
            actual: actualParts.joined(separator: " ")
        )
        verdict = result

        // 只有真正提交且判错才记错题；逐字红色提示、跳过、空提交、看答案都不算
        if !result.isCorrect, let question = current {
            recordMistake(question: question, parse: parse, wasRetry: isRetry)
        }

        if result.isCorrect {
            if isRetry {
                // 看过答案后的重试：只验证一次，不计分、不计连对
                reveal(advanceAfter: 1.2)
            } else {
                stats.correct += 1
                streak += 1
                // 填得越多分越高；跳过的空不扣分，但也不给分
                let full = 6 + Int((settings.practiceRatio * 6).rounded())
                let fillRatio = Double(expectedParts.count) / Double(max(1, blankIndices.count))
                let base = max(1, Int((Double(full) * fillRatio).rounded()))
                let bonus = min(max(streak - 1, 0), 3) * 2
                score += base + bonus
                reveal(advanceAfter: 1.8)
            }
        } else if !isRetry {
            stats.wrong += 1
            streak = 0
        }
        // 答错不锁输入、不揭示：重听之后再改、再交都可以
    }

    /// 把这次错误提交写进错题本：同句合并，逐次追加历史。
    private func recordMistake(question: PracticeQuestion, parse: BlankParse, wasRetry: Bool) {
        let words = PracticeBlanks.words(in: question.text)
        let blanks: [MistakeBlank] = blankIndices.enumerated().map { ordinal, wordIndex in
            let expected = words.indices.contains(wordIndex) ? words[wordIndex].raw : ""
            let actual = parse.slices.indices.contains(ordinal) ? parse.slices[ordinal] : ""
            return MistakeBlank(
                ordinal: ordinal,
                wordIndex: wordIndex,
                expected: expected,
                actual: actual,
                skipped: actual.isEmpty
            )
        }
        // 没有填任何空时不记（与 submit 的早退保持一致）
        guard blanks.contains(where: { !$0.skipped }) else { return }

        let translation = translation(for: question)
        let attempt = MistakeAttempt(
            source: source.rawValue,
            ratio: settings.practiceRatio,
            rawInput: input,
            translation: translation,
            wasRetry: wasRetry,
            blanks: blanks
        )
        let saved = mistakeBook.record(question: question, translation: translation, attempt: attempt)
        if saved {
            Diag.log("mistakes: recorded \(question.title) / \(question.text) attempts=\(mistakeBook.attemptCount(for: question))")
        } else {
            notice = "这次错误未能保存到错题本：\(mistakeBook.saveError ?? "写入失败")"
            Diag.log("mistakes: record FAILED \(question.title) / \(question.text)")
        }
    }

    /// 空格：结束当前空（已填的部分保留），跳到下一个。
    /// 输入缓冲里用空格做边界标记，切空不改写输入框，避免和输入框/输入法抢状态。
    func advanceBlank() {
        guard phase == .asking, !blankIndices.isEmpty else { return }
        input.append(" ")
        verdict = nil
    }

    /// 重听这一句：次数不限，已输入的内容保留（题库模式没有音频，按钮不出现）
    func replay() {
        guard source == .song else { return }
        guard phase == .asking || phase == .listening, cursor < questions.count else { return }
        guard let start = current?.start else { return }
        // 重听不清空输入缓冲：用户已经填的字在重听期间和回来后都保留
        verdict = nil
        missingSince = nil
        phase = .listening
        watcher.seek(to: start, play: true)
        lastCommandAt = Date()
        pausedByUs = true
        Diag.log("practice: replay line \(cursor + 1)")
    }

    func reveal(advanceAfter seconds: Double? = nil) {
        guard cursor < questions.count else { return }
        revealed = questions[cursor]
        phase = .revealed

        guard let seconds else { return }
        autoTask?.cancel()
        autoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.next()
        }
    }

    /// 直接看答案（放弃这一句）：连对清零，不扣分
    func giveUp() {
        guard phase == .asking else { return }
        streak = 0
        isRetry = false
        reveal()
    }

    /// 看过答案后再试一次：回到答题态、清空输入，这次不计分
    func retryAfterReveal() {
        guard phase == .revealed, cursor < questions.count else { return }
        autoTask?.cancel()
        autoTask = nil
        revealed = nil
        verdict = nil
        input = ""
        isRetry = true
        phase = .asking
        onRequestFocus?()
        Diag.log("practice: retry line \(cursor + 1)")
    }

    func next() {
        autoTask?.cancel()
        cursor += 1
        if cursor >= questions.count {
            finish()
        } else if source == .song {
            beginListening()
        } else {
            setCurrent(cursor)
            phase = .asking
            onRequestFocus?()
        }
    }

    func skip() {
        guard phase == .asking || phase == .listening else { return }
        streak = 0
        next()
    }

    /// 练完之后从头再来
    func restartSession() {
        guard enabled else { return }
        isRetry = false
        stats = Stats()
        score = 0
        streak = 0
        if source == .song {
            loadSong(fromBeginning: true)
        } else if source == .bank {
            loadBank(onlyID: sessionOnlyID)
        } else {
            loadMistakes(onlyID: sessionOnlyID)
        }
    }

    /// 练习中改强度：只影响「从下一句起」？不，当前这句也立刻按新强度重挖，输入清空
    func changeRatio(_ ratio: Double) {
        settings.practiceRatio = ratio
        guard let question = current else { return }
        blankIndices = PracticeBlanks.blankIndices(in: question.text, ratio: settings.practiceRatio)
        input = ""
        if phase == .asking { verdict = nil }
        Diag.log("practice: ratio \(Int(settings.practiceRatio * 100))% blanks=\(blankIndices.count)/\(eligibleWordCount)")
    }

    /// 题库模式下把正在练的这句从题库删掉（本次会话里仍然保留题目）
    func removeCurrentFromBank() {
        guard let id = current?.bankID else { return }
        bank.remove(id: id)
        notice = "已取消收藏这句"
    }

    private func finish(reason: String? = nil) {
        isRetry = false
        phase = .idle
        current = nil
        revealed = nil
        verdict = nil
        progress = ""
        missingSince = nil
        notice = reason ?? "练完了 · 得分 \(score) · 答对 \(stats.correct) 句，答错 \(stats.wrong) 句"
        if pausedByUs {
            watcher.send(.play)
            pausedByUs = false
        }
        Diag.log("practice: finished score=\(score) correct=\(stats.correct) wrong=\(stats.wrong) reason=\(reason ?? "done")")
    }

    // MARK: 工具

    private func updateProgress() {
        guard !questions.isEmpty else {
            progress = ""
            return
        }
        progress = "\(cursor + 1) / \(questions.count)"
    }
}

// MARK: - 离屏预览注入

extension PracticeEngine {
    func debugShow(
        phase: Phase,
        input: String,
        verdict: DictationJudge.Result?,
        current: PracticeQuestion?,
        revealed: PracticeQuestion?,
        progress: String,
        score: Int,
        streak: Int,
        retry: Bool = false,
        source: Source? = nil
    ) {
        self.phase = phase
        if let source { self.source = source }
        self.input = input
        self.verdict = verdict
        self.current = current
        self.revealed = revealed
        self.progress = progress
        self.score = score
        self.streak = streak
        self.isRetry = retry
        if let current {
            self.blankIndices = PracticeBlanks.blankIndices(
                in: current.text, ratio: settings.practiceRatio
            )
            // 预览传入的是带空格的整句；真实输入里空格表示“跳过”，先去掉
            self.input = input.replacingOccurrences(of: " ", with: "")
            self.verdict = verdict
        }
    }

    /// 调试用（`--practice-ask`）：跳过播放，直接进答题态（不碰真实音乐）
    func debugForceAsking(ratio: Double = 0.6) {
        guard let lyrics = state.lyrics, !lyrics.lines.isEmpty else { return }
        enabled = true
        source = .song
        settings.practiceRatio = ratio
        phase = .asking
        lyricsLines = lyrics.lines
        let duration = state.snapshot?.track.duration ?? 0
        let track = state.snapshot?.track
        let indices = PracticeFilter.practiceableIndices(lines: lyricsLines, trackDuration: duration)
        questions = indices.map { index in
            PracticeQuestion(
                text: lyricsLines[index].text,
                translation: nil,
                title: track?.title ?? "",
                artist: track?.artist ?? "",
                start: lyricsLines[index].time,
                end: PracticeFilter.endTime(lines: lyricsLines, index: index, trackDuration: duration),
                lineTime: lyricsLines[index].time
            )
        }
        guard !questions.isEmpty else { return }
        cursor = 0
        setCurrent(0)
        phase = .asking
        onRequestFocus?()
        Diag.log("practice: forced asking")
    }
}
