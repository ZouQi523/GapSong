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

// MARK: - 播放异常

/// 歌曲练习里可解释、可恢复的播放问题。
///
/// 关键约定：出现这些问题时**不结束练习、不清输入、不自动恢复播放**，
/// 只把状态交给界面，由用户点「继续播放 / 重试 / 跳过 / 结束练习」。
enum PlaybackIssue: Equatable {
    case unauthorized
    case controlFailed(Int)
    case readFailed(Int)
    /// 用户在「音乐」里手动暂停，或播放被系统中断
    case paused
    /// 采样消失：歌可能播完了、被切走，或 Music 退出/不再播放。
    /// 这三种在采样层无法可靠区分，所以文案只陈述「没有在播放」并给出结束/重试，
    /// 绝不冒充「练完了」。
    case musicStopped
    /// 采样还在但长时间没有更新
    case stalled

    var title: String {
        switch self {
        case .unauthorized: return "还没有获得控制「音乐」的权限"
        case .controlFailed: return "控制「音乐」失败"
        case .readFailed: return "读不到「音乐」的播放状态"
        case .paused: return "「音乐」被暂停了"
        case .musicStopped: return "「音乐」没有在播放"
        case .stalled: return "播放状态停止更新"
        }
    }

    var detail: String {
        switch self {
        case .unauthorized:
            return "到 系统设置 › 隐私与安全性 › 自动化 里允许 GapSong 控制「音乐」，然后点「重试播放」。"
        case .controlFailed(let code):
            return "「音乐」拒绝了播放命令（错误 \(code)）。可以重试，或跳过这一句。"
        case .readFailed(let code):
            return "读取播放位置失败（错误 \(code)）。练习没有判失败，已经输入的内容还在。"
        case .paused:
            return "可能是在「音乐」里手动暂停了。点「继续播放」从这句的句首继续；输入不会丢。"
        case .musicStopped:
            return "歌曲可能已经播完或被切走，也可能「音乐」已经退出。点「重试播放」，或结束/跳过这一句。"
        case .stalled:
            return "最近几秒没有拿到新的播放位置。点「重试播放」重新对齐，输入会保留。"
        }
    }

    var offersSettings: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    /// 这类问题通常意味着这首歌不会再继续了
    var suggestsStopping: Bool {
        switch self {
        case .musicStopped: return true
        case .paused, .stalled, .unauthorized, .controlFailed, .readFailed: return false
        }
    }

    /// 异常卡片的主操作：缺权限时先把人带到系统设置，其余先给可恢复的重试。
    /// 界面据此把「能解决问题的那一个」放在最前面，而不是先突出重试。
    var primaryAction: PlaybackIssueAction {
        offersSettings ? .openSettings : .retry
    }

    /// 缺权限时仍保留一个次要的「重试播放」（授权后回到练习用），
    /// 其余异常只留一个重试入口，避免同屏出现两个重试按钮。
    var offersSecondaryRetry: Bool { offersSettings }

    /// 重试按钮的文案：手动暂停说「继续播放」，其余说「重试播放」
    var retryActionLabel: String {
        if case .paused = self { return "继续播放" }
        return "重试播放"
    }
}

/// 播放异常卡片里的主操作
enum PlaybackIssueAction: Equatable {
    /// 打开系统设置（自动化权限）
    case openSettings
    /// 重试/继续播放
    case retry
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
        /// 答对的句子数
        var correct = 0
        /// 判错的**次数**（同一句可以错多次）
        var wrong = 0
    }

    @Published private(set) var phase: Phase = .setup
    @Published private(set) var source: Source = .song
    /// 设置页正在选的来源。放在引擎里，键盘数字命令和界面按钮才能共用一份判定。
    @Published private(set) var setupSource: Source = .song
    @Published private(set) var verdict: DictationJudge.Result?
    @Published private(set) var notice: String?
    /// 空提交之类的轻提示（不是错误，不写入任何数据）
    @Published private(set) var coaching: String?
    /// 当前播放异常；出现时练习暂停在这一句，等用户决定
    @Published private(set) var playbackIssue: PlaybackIssue?
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
    /// 逐空输入缓冲：与 `blankIndices` 一一对应。
    ///
    /// 上一版是一个「按词长自动切分」的连续字符串，空格只能把当前空跳过，
    /// 之后无法回到前面的空。用户实际遇到的是「跳过 But → 填完后面 → 只剩 But
    /// 却补不进去」。现在每个空各自保存内容，空格只负责切换当前空。
    @Published private(set) var blankInputs: [String] = []
    /// 当前正在编辑的空（0-based）
    @Published private(set) var activeBlankIndex = 0

    /// 兼容旧调用/旧快照的连续字符串视图：读取时按「空」序列化，赋值时仍按
    /// 旧规则从第一个空开始分配。真实键盘输入走 `typeCharacter` 等逐空接口。
    var input: String {
        get { serializeInput() }
        set { applyLegacyInput(newValue) }
    }

    /// 需要键盘输入时回调（由 OverlayController 抢焦点）
    var onRequestFocus: (() -> Void)?
    /// 每次请求输入焦点 +1；界面据此把第一响应者拉回隐藏输入视图
    @Published private(set) var focusTick = 0

    /// 可注入时钟：自检可以推进时间，不依赖真实等待
    var clock: () -> Date = Date.init
    /// 可注入打字机音效（自检/隔离默认静音）
    var typingSoundPlayer: TypingSoundPlaying = SilentTypingSoundPlayer()
    /// 可观测的音效事件（验收可注入 spy；只在真实单字母输入时调用）
    var onTypingSoundEvent: ((Character) -> Void)?

    /// 本地朗读状态机：默认静默，正常 App 在 AppDelegate 里注入 Apple 原生朗读。
    /// 自检/快照/隔离运行永远不会因此发出真实语音。
    private let speech = SpeechReader()

    private let state: PlayerState
    private let watcher: MusicControlling
    private let settings: Settings
    private let bank: QuestionBank
    private let mistakeBook: MistakeBook

    private var enabled = false
    private var questions: [PracticeQuestion] = []

    /// 本次会话的题目数量（自检/界面只读用）
    var questionCount: Int { questions.count }
    private var cursor = 0
    /// 本次会话是否只练某一条（收藏/错题），用于「再来一遍」
    private var sessionOnlyID: UUID?
    private var lyricsLines: [LyricLine] = []
    private var tickTask: Task<Void, Never>?
    private var autoTask: Task<Void, Never>?
    /// 刚下发过命令，等一个「命令之后」的采样再做边界判断，避免用旧位置误触
    private var lastCommandAt: Date?
    /// 只表示「是我们按下的暂停，而且暂停仍然成立」。
    /// 下发 seek(play:true) 不代表暂停，所以绝不能在这里置位——
    /// 否则用户手动暂停后离开练习，会被我们擅自恢复播放。
    private var pausedByUs = false
    private var lastTrackKey: String?
    private var lastGeneration = -1
    /// 采样消失（歌播完了 / Music 退出）的起点
    private var missingSince: Date?
    /// 采样存在但显示暂停的起点
    private var pausedSince: Date?
    private var lastMusicProblem: MusicProblem?
    private var lastIssueAt: Date?
    /// 最近一次可信的播放位置/曲长：用来区分「歌播完了」和「状态读不到」
    /// 播放命令下发后等第一条新采样的上限；超时按「读不到状态」提示，不判失败
    private static let commandConfirmTimeout: TimeInterval = 5.0
    /// 判错过的句子 id：汇总时区分「错几次」和「错几句」
    private var wrongQuestionIDs: Set<UUID> = []
    /// 当前句已提前填对，等音乐真正唱到句末再推进（不抢跑、不提前 seek）。
    /// 公开为 published：界面据此给出「全部正确、等句末」的明确反馈，
    /// 而不是在六个空都变绿后仍只说「正在听这一句」。
    @Published private(set) var pendingAutoAdvance = false
    /// 当前句已经因「全填对」推进过一次，防止重复计分/记录/推进
    private var autoAdvanceConsumed = false

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
        speech.onChange = { [weak self] in self?.objectWillChange.send() }
    }

    // MARK: 对外状态

    var ratio: Double { settings.practiceRatio }
    var isSongMode: Bool { source == .song }
    var sourceTitle: String { current?.title ?? "" }
    var sourceArtist: String { current?.artist ?? "" }

    /// 练习界面要显示的播放/授权提示：只有歌曲模式才有播放链路
    var playbackNotice: PlaybackIssue? {
        guard source == .song else { return nil }
        return playbackIssue
    }

    /// 已经提前填全对、正在等音乐唱到句末（界面显示「全部正确」确认）。
    ///
    /// 只由真实状态派生：仍在收听态、没有播放异常、且这次等待还没被消费。
    /// 手动暂停/授权失败等异常期间、以及改错答案之后都不会成立。
    var isWaitingForLineEnd: Bool {
        pendingAutoAdvance
            && !autoAdvanceConsumed
            && phase == .listening
            && source == .song
            && playbackIssue == nil
    }

    /// 当前这句的句级播放进度（0…1）。只有歌曲模式、拿到可信时间轴时才有值。
    ///
    /// LRC 只提供句级时间，这里只用「句首/句末」两个锚点，
    /// 不据此编造逐词时序。
    func currentLineProgress(at date: Date = Date()) -> Double? {
        guard phase == .listening, source == .song, playbackIssue == nil,
              let start = current?.start, let end = current?.end, end > start
        else { return nil }
        let value = (state.position(at: date) - start) / (end - start)
        return min(max(value, 0), 1)
    }

    /// 全对等待句末时给用户看的确认文案（界面直接使用，自检可断言）。
    /// 只承诺「已经全对」和「唱完这句再继续」，不承诺任何提前跳题。
    static let allCorrectWaitingText = "✓ 全部正确，唱完这句后继续"

    /// 答题态回车是否可用：决定底部那句低调的「回车继续」。
    /// 答题阶段不再有数字 3 的提交按钮；提交只走回车，避免与回车重复。
    /// 收听中不显示：提交要等音乐到句末，时序仍由播放边界决定。
    var showsReturnHint: Bool {
        phase == .asking && enabled && cursor < questions.count && !blankIndices.isEmpty
    }

    /// 底部操作区是否还要放「重试/继续播放」。
    /// 异常时重试和系统设置只出现在状态卡片里，避免同屏两个重试入口。
    var showsRetryInActionBar: Bool { playbackNotice == nil }

    /// 异常卡片的主操作（缺权限 → 打开系统设置；其余 → 重试播放）
    var playbackIssuePrimaryAction: PlaybackIssueAction? {
        playbackNotice?.primaryAction
    }

    // MARK: 设置页来源

    /// 当前歌曲里可听写的句数（设置页来源胶囊与数字 3「开始」共用）
    var songPracticeLineCount: Int {
        guard let lyrics = state.lyrics, !lyrics.lines.isEmpty else { return 0 }
        return PracticeFilter.practiceableIndices(
            lines: lyrics.lines,
            trackDuration: state.snapshot?.track.duration ?? 0
        ).count
    }

    func canUseSource(_ value: Source) -> Bool {
        switch value {
        case .song: return songPracticeLineCount > 0
        case .bank: return bank.count > 0
        case .mistakes: return mistakeBook.count > 0
        }
    }

    /// 设置页选择来源：只接受有内容的来源（空来源保持原选择）
    func selectSetupSource(_ value: Source) {
        guard canUseSource(value) else { return }
        setupSource = value
    }

    /// 进入设置页时给一个有内容的默认来源：歌曲 → 收藏 → 错题
    private func chooseDefaultSetupSource() {
        if canUseSource(.song) {
            setupSource = .song
        } else if canUseSource(.bank) {
            setupSource = .bank
        } else {
            setupSource = .mistakes
        }
    }

    // MARK: 本地朗读

    /// 只有离线来源（收藏/错题）的答题与揭示页可以朗读。
    /// 歌曲练习保留原来的「重听」逻辑，不在这里同时出声。
    var canReadAloud: Bool {
        guard source == .bank || source == .mistakes else { return false }
        switch phase {
        case .asking, .listening: return current != nil
        case .revealed: return revealed != nil
        case .setup, .idle: return false
        }
    }

    var readAloudText: String? {
        switch phase {
        case .revealed: return revealed?.text
        default: return current?.text
        }
    }

    var isSpeaking: Bool { speech.isSpeaking }
    var speechNotice: String? { speech.notice }

    /// 朗读 / 停止当前英文原句。重复点击不叠音；无英语音色时给一句可恢复提示。
    func toggleReadAloud() {
        guard canReadAloud, let text = readAloudText, !text.isEmpty else { return }
        let lineID = (phase == .revealed ? revealed?.id : current?.id)
        guard let lineID else { return }
        speech.toggle(text: text, lineID: lineID)
    }

    /// 换题/重试/切来源/结束练习/退出练习/隐藏窗口时停掉旧句
    func stopReading() { speech.cancel() }

    /// 正常 App 注入 Apple 原生朗读；自检/快照保持默认静默
    func installSpeechSpeaker(_ speaker: SpeechSpeaking) {
        speech.install(speaker)
    }

    // MARK: 数字命令 1…6

    /// 当前阶段该数字动作的按钮标题；nil = 阶段不适用（按键仍会被消费）。
    /// 可见按钮与键盘共用这一份判定，避免标签/事件不一致。
    func commandTitle(_ command: PracticeCommand) -> String? {
        switch command {
        case .replayOrRead:
            if isSongMode {
                guard phase == .asking || phase == .listening, showsRetryInActionBar,
                      current?.start != nil else { return nil }
                return "1 重听"
            }
            guard canReadAloud else { return nil }
            return isSpeaking ? "1 停止" : "1 朗读"

        case .revealOrRetry:
            if phase == .asking { return "2 看答案" }
            if phase == .revealed { return "2 再试" }
            return nil

        case .primary:
            switch phase {
            case .setup:
                return canUseSource(setupSource) ? "3 开始" : nil
            case .asking:
                // 提交只走回车；答题阶段不再显示数字 3 的提交按钮
                return nil
            case .revealed:
                return "3 下一句"
            case .idle:
                return stats.correct + stats.wrong > 0 ? "3 再来一遍" : nil
            case .listening:
                // 收听中不提前强制提交，时序仍由音乐句末决定
                return nil
            }

        case .skip:
            return (phase == .asking || phase == .listening) ? "4 跳过" : nil

        case .backToSetup:
            return phase == .setup ? nil : "5 设置"

        case .exitPractice:
            return "6 返回"
        }
    }

    /// 执行数字命令。无动作的阶段直接忽略，但调用方（键盘）仍会消费按键。
    func perform(_ command: PracticeCommand) {
        guard commandTitle(command) != nil else { return }
        switch command {
        case .replayOrRead:
            if isSongMode {
                replay()
            } else {
                toggleReadAloud()
            }
        case .revealOrRetry:
            if phase == .asking {
                giveUp()
            } else if phase == .revealed {
                retryAfterReveal()
            }
        case .primary:
            switch phase {
            case .setup:
                guard canUseSource(setupSource) else { return }
                begin(source: setupSource, ratio: settings.practiceRatio)
            case .asking:
                // 3 在答题阶段不提交；回车仍走 primaryAction/submit 的原逻辑
                break
            case .revealed:
                next()
            case .idle:
                restartSession()
            case .listening:
                break
            }
        case .skip:
            skip()
        case .backToSetup:
            returnToSetup()
        case .exitPractice:
            exitPractice()
        }
    }

    /// 6：退出练习回歌词，不退出整个 App
    func exitPractice() {
        stopReading()
        settings.practiceMode = false
    }

    /// 汇总文案：次数与句数分开说，避免「错两次 = 错两句」
    var summary: String {
        "得分 \(score) · 答对 \(stats.correct) 句，答错 \(stats.wrong) 次（\(wrongQuestionIDs.count) 句）"
    }

    /// 判错过的句子数（与错误提交次数区分开）
    var wrongQuestionCount: Int { wrongQuestionIDs.count }

    /// 当前题目的判分期望：所有被挖空的词按顺序拼回去
    var expectedAnswer: String {
        PracticeBlanks.expectedAnswer(in: current?.text ?? "", blankIndices: blankIndices)
    }

    var blankWordCount: Int { blankIndices.count }

    /// 当前空的下标
    var activeBlank: Int {
        guard !blankIndices.isEmpty else { return 0 }
        return min(max(activeBlankIndex, 0), blankIndices.count - 1)
    }

    /// 已经填了内容的横线数量
    var filledBlankCount: Int {
        (0..<blankIndices.count).filter { !blankText($0).isEmpty }.count
    }

    /// 某个横线当前要显示的字符
    func typedChars(forBlank ordinal: Int) -> [Character] {
        Array(blankText(ordinal))
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

    private func blankText(_ ordinal: Int) -> String {
        blankInputs.indices.contains(ordinal) ? blankInputs[ordinal] : ""
    }

    /// 逐空缓冲直接就是判分/展示用的切片；overflow 仅用于统计超长输入
    private func parseBlanks() -> BlankParse {
        let lengths = blankLengths()
        guard !lengths.isEmpty else { return BlankParse(slices: [], active: 0, overflow: "") }
        var slices = Array(repeating: "", count: lengths.count)
        var overflow = ""
        for index in slices.indices {
            let value = blankText(index)
            slices[index] = value
            if value.count > lengths[index] {
                overflow += String(value.dropFirst(lengths[index]))
            }
        }
        return BlankParse(slices: slices, active: activeBlank, overflow: overflow)
    }

    // MARK: 逐空编辑

    /// 真实键盘输入一个字符。返回是否真的写入了某个空。
    /// - Parameter playSound: 只有用户直接敲入的单个拉丁字母才播放一次；
    ///   粘贴、替换、程序性同步都传 false。
    @discardableResult
    func typeCharacter(_ ch: Character, playSound: Bool = true) -> Bool {
        guard prepareEditing(), let c = normalizedInputCharacter(ch) else { return false }
        guard append(c) else { return false }
        if playSound, c.isLetter, settings.typingSound {
            typingSoundPlayer.playTick()
            onTypingSoundEvent?(c)
        }
        checkAutoAdvance()
        return true
    }

    /// 粘贴 / 输入法提交等批量文本：逐字落空，但绝不成串播放音效。
    ///
    /// 词间空格全部忽略：`append` 在填满一个空时已经自动进入下一个空，
    /// 再把空格当成「跳空」会隔一个空漏一个空。整句粘贴因此与连续键入
    /// （不带跳空空格）得到同一组逐空内容。
    func insertBulk(_ text: String, playSound: Bool = false) {
        guard prepareEditing() else { return }
        var inserted = false
        for ch in text {
            if ch.isWhitespace {
                continue
            }
            if let c = normalizedInputCharacter(ch) {
                inserted = append(c) || inserted
            }
        }
        if inserted, playSound, settings.typingSound {
            // 批量输入最多响一次；当前调用方都传 false，保留给未来的显式入口
            typingSoundPlayer.playTick()
        }
        checkAutoAdvance()
    }

    /// 退格：删当前空的最后一个字符；当前空已空时退回上一个空再删。
    func deleteBackward() {
        guard prepareEditing() else { return }
        if blankText(activeBlank).isEmpty {
            guard activeBlank > 0 else { return }
            activeBlankIndex = activeBlank - 1
        }
        guard !blankText(activeBlank).isEmpty else { return }
        blankInputs[activeBlank].removeLast()
        verdict = nil
        coaching = nil
        checkAutoAdvance()
    }

    /// 点击某个横线，或空格循环切换
    func selectBlank(_ ordinal: Int) {
        guard blankIndices.indices.contains(ordinal) else { return }
        activeBlankIndex = ordinal
    }

    /// 空格：切到下一个空；到了最后一个空就回到第一个还没填的空（没有则回到开头）。
    /// 这样跳过第一个空、填完后面之后，可以直接按空格回到第一个空补填。
    func advanceBlank() {
        guard prepareEditing() else { return }
        moveToNextBlank()
        verdict = nil
    }

    /// 只移动当前空，不改内容；批量粘贴里的空格也走这里，避免清掉判分提示
    private func moveToNextBlank() {
        let count = blankIndices.count
        guard count > 0 else { return }
        var next = activeBlank + 1
        if next >= count {
            next = (0..<count).first(where: { blankText($0).isEmpty }) ?? 0
        }
        activeBlankIndex = next
    }

    /// 焦点请求：窗口置前 + 界面把隐藏输入视图设为第一响应者
    func requestInputFocus() {
        onRequestFocus?()
        focusTick &+= 1
    }

    private func prepareEditing() -> Bool {
        guard enabled, phase == .asking || phase == .listening, !blankIndices.isEmpty else {
            return false
        }
        normalizeBlankInputs()
        return true
    }

    private func normalizeBlankInputs() {
        let count = blankIndices.count
        if blankInputs.count < count {
            blankInputs.append(contentsOf: Array(repeating: "", count: count - blankInputs.count))
        } else if blankInputs.count > count {
            blankInputs.removeLast(blankInputs.count - count)
        }
        if count > 0, activeBlankIndex >= count {
            activeBlankIndex = count - 1
        } else if count == 0 {
            activeBlankIndex = 0
        }
    }

    private func normalizedInputCharacter(_ ch: Character) -> Character? {
        let lower = ch.lowercased()
        guard lower.count == 1, let c = lower.first,
              c.isASCII, c.isLetter || c.isNumber || c == "-" else { return nil }
        return c
    }

    /// 写入当前空；填满后优先跳到后面第一个未填空。允许少量超长字符，
    /// 让多打的字母进入判分（而不是被悄悄吞掉）。
    private func append(_ c: Character) -> Bool {
        let lengths = blankLengths()
        guard lengths.indices.contains(activeBlank) else { return false }
        let need = lengths[activeBlank]
        guard blankText(activeBlank).count < need + 8 else { return false }
        blankInputs[activeBlank].append(c)
        if blankText(activeBlank).count >= need {
            if let next = ((activeBlank + 1)..<blankIndices.count)
                .first(where: { blankText($0).isEmpty }) {
                activeBlankIndex = next
            } else if activeBlank + 1 < blankIndices.count {
                activeBlankIndex = activeBlank + 1
            }
        }
        verdict = nil
        coaching = nil
        return true
    }

    /// 兼容旧调用/快照注入：按词长从第一个空开始分配。
    /// 空格仍表示「跳过当前空」，但不触发自动推进、音效或计分。
    private func applyLegacyInput(_ raw: String) {
        let lengths = blankLengths()
        guard !lengths.isEmpty else {
            blankInputs = []
            activeBlankIndex = 0
            return
        }

        var tokens: [Character] = []
        for ch in raw {
            if ch == " " {
                tokens.append(" ")
                continue
            }
            if let c = normalizedInputCharacter(ch) { tokens.append(c) }
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
                break
            }
            bi += 1
        }
        blankInputs = slices
        activeBlankIndex = (0..<lengths.count).first(where: { slices[$0].isEmpty })
            ?? max(0, lengths.count - 1)
        pendingAutoAdvance = false
        verdict = nil
        coaching = nil
    }

    /// 连续字符串视图：只序列化到最后一个已填的空；
    /// 中间的空位用空格表示「跳过的空」，末尾未填的空不补空格。
    /// 这样旧测试里的 `input += "kept"` 仍然按顺序落到下一个空。
    private func serializeInput() -> String {
        let values = (0..<blankIndices.count).map(blankText)
        guard let lastFilled = values.lastIndex(where: { !$0.isEmpty }) else { return "" }
        var out = ""
        for index in 0...lastFilled {
            if values[index].isEmpty {
                out.append(" ")
            } else {
                out += values[index]
            }
        }
        return out
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
            resetStats()
            chooseDefaultSetupSource()
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
        resetStats()
        chooseDefaultSetupSource()
        Diag.log("practice: back to setup")
    }

    private func resetStats() {
        stats = Stats()
        score = 0
        streak = 0
        wrongQuestionIDs = []
    }

    /// 从设置页 / 菜单 / 管理窗口开始一次练习。
    /// - Parameter onlyID: 只练收藏/错题里的某一条；nil 表示练整个库。
    func begin(source: Source, ratio: Double, onlyID: UUID? = nil) {
        // 切换来源前先彻底结束旧会话：停止计时、取消自动下一题、恢复被我们暂停的音乐
        stopReading()
        stopTick()
        autoTask?.cancel()
        autoTask = nil
        if pausedByUs {
            watcher.send(.play)
            pausedByUs = false
        }
        lastCommandAt = nil
        missingSince = nil
        pausedSince = nil
        playbackIssue = nil
        lastMusicProblem = nil
        lastIssueAt = nil
        coaching = nil

        settings.practiceRatio = ratio
        self.source = source
        self.sessionOnlyID = onlyID
        enabled = true
        resetStats()
        isRetry = false
        current = nil
        revealed = nil
        verdict = nil
        notice = nil
        progress = ""
        blankIndices = []
        resetBlankInputs()
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
        pausedSince = nil
        playbackIssue = nil
        lastMusicProblem = nil
        lastIssueAt = nil
        sessionOnlyID = nil
        resetContent()
    }

    private func resetContent() {
        stopReading()
        current = nil
        revealed = nil
        verdict = nil
        notice = nil
        coaching = nil
        progress = ""
        blankIndices = []
        resetBlankInputs()
    }

    private func resetBlankInputs() {
        blankInputs = []
        activeBlankIndex = 0
        pendingAutoAdvance = false
        autoAdvanceConsumed = false
    }

    // MARK: 题库

    /// 歌曲模式：按播放位置把可用于听写的行变成题目
    private func loadSong(fromBeginning: Bool) {
        lastTrackKey = state.snapshot?.track.cacheKey
        lastGeneration = state.lyricsGeneration

        autoTask?.cancel()
        verdict = nil
        revealed = nil
        resetBlankInputs()

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
            notice = onlyID == nil ? "收藏还是空的" : "这句已经不在收藏里了"
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
        resetStats()
        isRetry = false
        requestTranslations()
        setCurrent(0)
        phase = .asking
        requestInputFocus()
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
            notice = onlyID == nil ? "错题本还是空的" : "这条错题已经不存在了"
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
        resetStats()
        isRetry = false
        requestTranslations()
        setCurrent(0)
        phase = .asking
        requestInputFocus()
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
        stopReading()
        let question = questions[index]
        current = question
        blankIndices = PracticeBlanks.blankIndices(in: question.text, ratio: settings.practiceRatio)
        resetBlankInputs()
        verdict = nil
        revealed = nil
        notice = nil
        coaching = nil
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
        pausedSince = nil
        playbackIssue = nil
        lastMusicProblem = nil

        guard let start = current?.start else {
            // 没有时间轴就退化成直接答题（题库模式正常走不到这里）
            phase = .asking
            requestInputFocus()
            return
        }

        watcher.seek(to: start, play: true)
        lastCommandAt = clock()
        // 我们刚刚发起播放：手上没有任何暂停，退出练习也不该替用户按播放
        pausedByUs = false
        // 边听边填：开始播放就允许输入，不等句末暂停
        requestInputFocus()
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

        // 已经给出明确原因：停在这里等用户决定，既不自动恢复，也不自动判失败
        guard playbackIssue == nil else { return }

        let now = clock()

        // 采样消失：可能是歌播完了，也可能是 Music 退出/被切走。
        // 不再直接当成「播放已结束」——那会把授权失败说成正常结束。
        guard let snapshot = state.snapshot else {
            pausedSince = nil
            // 命令还在等确认但长时间没有采样：同样给可恢复提示
            if let issuedAt = lastCommandAt,
               now.timeIntervalSince(issuedAt) > Self.commandConfirmTimeout {
                lastCommandAt = nil
                raise(.stalled)
                return
            }
            if let since = missingSince {
                if now.timeIntervalSince(since) > 2.5 {
                    raise(.musicStopped)
                }
            } else {
                missingSince = now
            }
            return
        }
        missingSince = nil

        guard snapshot.playing else {
            // 刚下发过 seek(play:)，给系统 2 秒把状态翻过来
            if let issuedAt = lastCommandAt, now.timeIntervalSince(issuedAt) < 2.0 { return }
            lastCommandAt = nil
            if let since = pausedSince {
                if now.timeIntervalSince(since) > 1.5 { raise(.paused) }
            } else {
                pausedSince = now
            }
            return
        }
        pausedSince = nil

        if let issuedAt = lastCommandAt {
            // 留 0.2s 余量：命令下发瞬间可能有一个已经在路上的旧采样
            if snapshot.sampledAt > issuedAt.addingTimeInterval(0.2) {
                lastCommandAt = nil
            } else {
                // 「等第一条新采样」本身也要有超时：否则一直没被确认的命令会让
                // 后面的卡住检测永远走不到，界面就永远停在「正在听这一句」。
                if now.timeIntervalSince(issuedAt) > Self.commandConfirmTimeout {
                    lastCommandAt = nil
                    raise(.stalled)
                }
                return
            }
        }

        // 采样长时间不更新（Music 卡住 / 权限被撤）：这是「读不到状态」，
        // 不是「这句播完了」，所以只提示、不判失败。
        // 正常的慢歌/长句/间奏位置一直在推进，不会走到这里。
        if now.timeIntervalSince(snapshot.sampledAt) > 4.0 {
            raise(.stalled)
            return
        }

        let position = state.position(at: now)

        // 句末延迟：正数是「多放一点再停」，负数是「提前停」。
        // 默认延后，宁可多听一个音，也不要把这一句的最后半拍切掉。
        guard position >= end + settings.practiceTail else { return }

        // 已经提前填全对：等音乐真正走到句末再切下一句。
        // 这里不暂停、不 seek 回句首，避免把这一句的尾巴截断。
        if pendingAutoAdvance, !autoAdvanceConsumed, playbackIssue == nil {
            completeAndAdvance()
            return
        }

        // 停下来，并回到句首：之后无论是重播还是续播都从已知锚点出发
        pausedByUs = true
        watcher.send(.pause)
        if let start = question.start {
            watcher.seek(to: start, play: false)
        }
        lastCommandAt = clock()

        verdict = nil
        phase = .asking
        requestInputFocus()
        Diag.log("practice: line \(cursor + 1)/\(questions.count) paused at \(String(format: "%.2f", end)) tail=\(settings.practiceTail)")
    }

    /// 记录播放异常：不结束练习、不清输入，只把原因交给界面
    private func raise(_ issue: PlaybackIssue) {
        guard playbackIssue == nil else { return }
        if let problem = lastMusicProblem {
            switch problem {
            case .unauthorized:
                playbackIssue = .unauthorized
            case .controlFailed(let code):
                playbackIssue = issue == .paused || issue == .musicStopped
                    ? .controlFailed(code)
                    : issue
            case .readFailed(let code):
                playbackIssue = issue == .stalled ? .readFailed(code) : issue
            }
        } else {
            playbackIssue = issue
        }
        lastIssueAt = clock()
        Diag.log("practice: playback issue \(playbackIssue!) (raw=\(issue)) input kept=\(!input.isEmpty)")
    }

    /// 由 MusicWatcher 转发：授权/控制失败要能带进练习界面
    func reportMusicProblem(_ problem: MusicProblem) {
        lastMusicProblem = problem
        guard enabled, source == .song else { return }
        guard phase == .listening || phase == .asking else { return }
        switch problem {
        case .unauthorized: playbackIssue = .unauthorized
        case .controlFailed(let code): playbackIssue = .controlFailed(code)
        case .readFailed(let code): playbackIssue = .readFailed(code)
        }
        lastIssueAt = clock()
        Diag.log("practice: music problem \(problem) in \(phase)")
    }

    /// 判断「要不要按新上下文重建题库」。
    ///
    /// 三种情况必须分开：
    /// 1. 暂时没有采样（Music 退出/被切走/刚启动）：什么都不做。绝不在这里清题、
    ///    清输入，也不用 nil 歌名重建一份「无歌名」的题目——那会把用户已经填的字和
    ///    当前题一起弄丢；缺采样的解释交给 tick 的计时逻辑。
    /// 2. 明确换成了另一首歌：按来源切换规则重建（清输入）。
    /// 3. 同一首歌的歌词/翻译刷新：保留当前题与已输入内容，只在还没有题目时重建。
    private func checkContext() {
        guard source == .song else { return }
        guard let snapshot = state.snapshot else { return }
        let key = snapshot.track.cacheKey
        if key != lastTrackKey {
            Diag.log("practice: context switched track -> rebuild")
            loadSong(fromBeginning: false)
            return
        }
        guard state.lyricsGeneration != lastGeneration else { return }
        if questions.isEmpty {
            loadSong(fromBeginning: false)
        } else {
            lastGeneration = state.lyricsGeneration
            if let lyrics = state.lyrics { lyricsLines = lyrics.lines }
            Diag.log("practice: same track lyrics refreshed, keeping \(questions.count) questions")
        }
    }

    // MARK: 答题

    /// 每次落字/删除/粘贴后检查一次：所有被挖空都填了且整体判分正确，
    /// 才允许自动通过。部分正确、只填部分、空提交、错误、揭示态都不走这里。
    private func checkAutoAdvance() {
        guard !autoAdvanceConsumed, phase == .asking || phase == .listening else {
            pendingAutoAdvance = false
            return
        }
        guard !blankIndices.isEmpty else {
            pendingAutoAdvance = false
            return
        }
        normalizeBlankInputs()
        let lengths = blankLengths()
        // 「已填」只看每个空有没有输入，不额外用原文字符数拦人：
        // four / 4 这类判分器已认可的等价写法必须能通过；
        // 只填了半个词时，下面的同一个 DictationJudge 仍会判错。
        let allFilled = lengths.count == blankIndices.count
            && lengths.indices.allSatisfy { !blankText($0).isEmpty }
        guard allFilled else {
            pendingAutoAdvance = false
            return
        }

        let expected = lengths.indices.map { expectedWord(atBlank: $0) }.joined(separator: " ")
        let actual = lengths.indices.map { blankText($0) }.joined(separator: " ")
        guard DictationJudge.judge(expected: expected, actual: actual).isCorrect else {
            pendingAutoAdvance = false
            return
        }

        // 歌曲播放异常/手动暂停时只保留现场：这里不发播放命令，也不推进；
        // 用户显式重试后可以再输入一次，或按 ⏎ 走原来的提交流程。
        if source == .song, playbackIssue != nil {
            pendingAutoAdvance = false
            return
        }

        if phase == .listening {
            // 已提前填对：等 tick 在真实句末边界推进，不在这里 seek / 暂停
            pendingAutoAdvance = true
        } else {
            completeAndAdvance()
        }
    }

    /// 全填对后的唯一推进路径：计分一次、推进一句。
    private func completeAndAdvance() {
        guard !autoAdvanceConsumed, cursor < questions.count else { return }
        autoAdvanceConsumed = true
        pendingAutoAdvance = false
        let wasListening = phase == .listening
        if !isRetry {
            awardCorrectScore(filledCount: blankIndices.count)
        }
        if wasListening, source == .song {
            // 歌曲正在自然播放、只是这一句提前填对了：在真实句末只切题目，
            // 不 pause、不 seek（seek 到下一句句首会倒退 practiceTail 秒重唱），
            // 让音乐连续往下走。
            advanceKeepingPlayback()
        } else {
            Diag.log("practice: auto advance line \(cursor + 1) retry=\(isRetry) score=\(score)")
            next()
        }
    }

    /// 边听边填全对后的推进：只换题目，不向音乐发任何命令。
    private func advanceKeepingPlayback() {
        autoTask?.cancel()
        autoTask = nil
        cursor += 1
        if cursor >= questions.count {
            Diag.log("practice: auto finished at line \(cursor) without seek")
            finish()
            return
        }
        setCurrent(cursor)
        phase = .listening
        missingSince = nil
        pausedSince = nil
        playbackIssue = nil
        lastMusicProblem = nil
        lastIssueAt = nil
        // 没有下发新命令，也就没有等待确认的命令；音乐保持原样继续
        lastCommandAt = nil
        requestInputFocus()
        Diag.log("practice: auto next line \(cursor + 1) without seek (continuous)")
    }

    private func awardCorrectScore(filledCount: Int) {
        stats.correct += 1
        streak += 1
        // 填得越多分越高；跳过的空不扣分，但也不给分
        let full = 6 + Int((settings.practiceRatio * 6).rounded())
        let fillRatio = Double(filledCount) / Double(max(1, blankIndices.count))
        let base = max(1, Int((Double(full) * fillRatio).rounded()))
        let bonus = min(max(streak - 1, 0), 3) * 2
        score += base + bonus
    }

    /// ⏎ 的统一入口：答题提交、揭示后下一句、结束后再来一遍。
    /// 收听态不主动提交（还没到句末），把时序留给音乐边界。
    func primaryAction() {
        switch phase {
        case .asking:
            submit()
        case .revealed:
            next()
        case .idle:
            if stats.correct + stats.wrong > 0 { restartSession() }
        case .listening, .setup:
            break
        }
    }

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
        guard !expectedParts.isEmpty else {
            // 一个空都没填：只给一次轻提示，不判错、不记错题
            coaching = "先填几个词"
            Diag.log("practice: empty submit ignored")
            return
        }
        coaching = nil

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
                awardCorrectScore(filledCount: expectedParts.count)
                reveal(advanceAfter: 1.8)
            }
        } else if !isRetry {
            // 统计口径：wrong 是「次数」，wrongQuestionIDs 是「句数」，两者都要如实
            stats.wrong += 1
            if let question = current { wrongQuestionIDs.insert(question.id) }
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

    /// 重听这一句：次数不限，已输入的内容保留（题库模式没有音频，按钮不出现）
    func replay() {
        guard source == .song else { return }
        guard phase == .asking || phase == .listening, cursor < questions.count else { return }
        guard let start = current?.start else { return }
        stopReading()
        // 重听不清空输入缓冲：用户已经填的字在重听期间和回来后都保留
        verdict = nil
        coaching = nil
        missingSince = nil
        pausedSince = nil
        // 用户主动要求重听：清掉上一次的播放异常，重新给一次机会
        playbackIssue = nil
        lastMusicProblem = nil
        phase = .listening
        watcher.seek(to: start, play: true)
        lastCommandAt = clock()
        pausedByUs = false
        requestInputFocus()
        // 输入可能在异常/暂停期间已经填全对：恢复后重新建立「等句末推进」标记，
        // 但不在这里抢跑，也不额外发命令。
        checkAutoAdvance()
        Diag.log("practice: replay line \(cursor + 1)")
    }

    /// 出现播放异常后的显式重试：从这一句的句首重新播放。
    /// 只有用户点了按钮才会走这里——显示提示时绝不自动恢复用户暂停。
    func resumePlayback() {
        guard source == .song, cursor < questions.count, let question = current else { return }
        guard let start = question.start else { return }
        stopReading()
        playbackIssue = nil
        lastMusicProblem = nil
        lastIssueAt = nil
        missingSince = nil
        pausedSince = nil
        coaching = nil
        phase = .listening
        watcher.seek(to: start, play: true)
        lastCommandAt = clock()
        pausedByUs = false
        requestInputFocus()
        // 异常期间可能已经填全对：用户显式恢复后重新评估，仍然只在可信句末推进。
        checkAutoAdvance()
        Diag.log("practice: resume playback line \(cursor + 1) input kept=\(!input.isEmpty)")
    }

    /// 播放在这一句彻底回不来时，体面地提前结束并如实汇总
    func stopSession() {
        guard enabled else { return }
        let reason: String
        switch playbackIssue {
        case .unauthorized: reason = "没有控制「音乐」的权限，练习提前结束"
        default: reason = "播放在这一句停住了，练习提前结束"
        }
        finish(reason: reason)
    }

    func reveal(advanceAfter seconds: Double? = nil) {
        guard cursor < questions.count else { return }
        stopReading()
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

    /// 看过答案后再试一次：清空输入；歌曲来源从当前句句首重新播放，离线来源回到答题态。
    /// 这次不计分（保持现有规则）。
    func retryAfterReveal() {
        guard phase == .revealed, cursor < questions.count else { return }
        stopReading()
        autoTask?.cancel()
        autoTask = nil
        revealed = nil
        verdict = nil
        coaching = nil
        resetBlankInputs()
        isRetry = true
        notice = nil

        if source == .song, let start = current?.start {
            playbackIssue = nil
            lastMusicProblem = nil
            lastIssueAt = nil
            missingSince = nil
            pausedSince = nil
            phase = .listening
            watcher.seek(to: start, play: true)
            lastCommandAt = clock()
            pausedByUs = false
            Diag.log("practice: retry replay line \(cursor + 1) from \(String(format: "%.2f", start))")
        } else {
            phase = .asking
            Diag.log("practice: retry line \(cursor + 1) offline")
        }
        requestInputFocus()
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
            requestInputFocus()
        }
    }

    func skip() {
        guard phase == .asking || phase == .listening else { return }
        streak = 0
        playbackIssue = nil
        next()
    }

    /// 练完之后从头再来
    func restartSession() {
        guard enabled else { return }
        stopReading()
        isRetry = false
        resetStats()
        if source == .song {
            loadSong(fromBeginning: true)
        } else if source == .bank {
            loadBank(onlyID: sessionOnlyID)
        } else {
            loadMistakes(onlyID: sessionOnlyID)
        }
    }

    /// 练习中改强度：当前这句立刻按新强度重挖，输入清空
    func changeRatio(_ ratio: Double) {
        stopReading()
        settings.practiceRatio = ratio
        guard let question = current else { return }
        blankIndices = PracticeBlanks.blankIndices(in: question.text, ratio: settings.practiceRatio)
        resetBlankInputs()
        verdict = nil
        if phase == .asking || phase == .listening {
            // 从下拉菜单选完强度后要把焦点还给答题框，否则用户以为卡死了
            requestInputFocus()
        }
        Diag.log("practice: ratio \(Int(settings.practiceRatio * 100))% blanks=\(blankIndices.count)/\(eligibleWordCount)")
    }

    /// 题库模式下把正在练的这句从题库删掉（本次会话里仍然保留题目）
    func removeCurrentFromBank() {
        guard let id = current?.bankID else { return }
        if bank.remove(id: id) {
            notice = "已取消收藏这句"
        } else {
            notice = bank.saveError ?? "取消收藏失败"
        }
    }

    private func finish(reason: String? = nil) {
        stopReading()
        isRetry = false
        phase = .idle
        current = nil
        revealed = nil
        verdict = nil
        coaching = nil
        playbackIssue = nil
        progress = ""
        missingSince = nil
        pausedSince = nil
        lastCommandAt = nil
        blankIndices = []
        resetBlankInputs()
        let head = reason.map { "\($0) · " } ?? "练完了 · "
        notice = head + summary
        if pausedByUs {
            watcher.send(.play)
            pausedByUs = false
        }
        Diag.log("practice: finished score=\(score) correct=\(stats.correct) wrong=\(stats.wrong) wrongLines=\(wrongQuestionIDs.count) reason=\(reason ?? "done")")
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
        source: Source? = nil,
        playbackIssue: PlaybackIssue? = nil,
        notice: String? = nil,
        stats: Stats? = nil,
        waitingForLineEnd: Bool = false
    ) {
        stopReading()
        self.phase = phase
        if let source { self.source = source }
        self.verdict = verdict
        self.current = current
        self.revealed = revealed
        self.progress = progress
        self.score = score
        self.streak = streak
        self.isRetry = retry
        self.playbackIssue = playbackIssue
        if let notice { self.notice = notice }
        if let stats { self.stats = stats }
        if let current {
            // 预览注入要和真实会话同形：会话已启用、有题目队列、光标在本题。
            // 这样 asking 快照会显示真实的「回车继续」提示，而不是因为
            // 预览缺状态而少一个提示；真实运行的守卫本身不放宽。
            self.enabled = true
            self.questions = [current]
            self.cursor = 0
            self.blankIndices = PracticeBlanks.blankIndices(
                in: current.text, ratio: settings.practiceRatio
            )
            resetBlankInputs()
            // 预览传入的是带空格的整句；逐空缓冲按旧规则从第一个空开始分配
            self.input = input.replacingOccurrences(of: " ", with: "")
            self.verdict = verdict
            // 预览「全对等句末」：必须在 input 赋值之后设置（兼容 setter 会清掉它）
            self.pendingAutoAdvance = waitingForLineEnd
        } else {
            self.blankIndices = []
            resetBlankInputs()
        }
    }

    /// 自检用：可推进时钟的主循环单步（真实 App 走 tickTask）
    func debugTick() {
        tick()
    }

    /// 自检用：模拟界面上出现的播放异常
    func debugRaise(_ issue: PlaybackIssue) {
        playbackIssue = issue
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
        requestInputFocus()
        Diag.log("practice: forced asking")
    }
}
