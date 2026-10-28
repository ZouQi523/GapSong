import Foundation
import AppKit
import Translation

/// 命令行自检：判分、持久化、错题本、来源切换、隔离模式与网络。
/// 任何一项失败都会以非 0 退出码结束，并在输出里明确标 ✗。
enum SelfTest {
    private static var checks = 0
    private static var failures = 0

    private static func check(_ ok: Bool, _ label: String) {
        checks += 1
        if !ok { failures += 1 }
        print("\(ok ? "✓" : "✗") \(label)")
    }

    private static func info(_ text: String) {
        print("  \(text)")
    }

    static func run() -> Never {
        setvbuf(stdout, nil, _IONBF, 0)
        Task {
            print("== GapSong 自检 ==")
            print("系统版本: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            print("隔离模式: \(AppRuntime.isIsolated)  base=\(Paths.base.path)")

            check(MusicWatcher.scriptCompiles(), "AppleScript 编译")
            if let fake = SelfTest.fakeDescriptor() {
                if let snap = MusicWatcher.snapshot(from: fake) {
                    check(true, "播放状态解析: \(snap.track.title) / \(snap.track.artist) / \(snap.track.duration)s / pos=\(snap.position) / playing=\(snap.playing)")
                } else {
                    check(false, "播放状态解析")
                }
            } else {
                check(false, "构造 AppleScript 测试描述符")
            }

            testDictation()
            testPracticeFilter()
            testPracticeBlanks()
            await testSettingsModel()
            await testQuestionBank()
            await testFavoritesCompatibility()
            await testBankCorruptFileProtection()
            await testBankBackupFailureIsReadOnly()
            await testBankDirectoryPathProtection()
            await testBankSaveFailure()
            await testLegacyBankPartialFields()
            await testRetryFlow()
            await testBlankNavigation()
            await testBlankRevisitAndPaste()
            await testDigitEquivalentAutoAdvance()
            await testAutoAdvanceTiming()
            await testPracticeTypographyFloors()
            await testWaitingFeedbackAndPrimaryActions()
            await testResumeAfterIssueReArmsAuto()
            await testRetryReplaysMusic()
            await testTypingSound()
            await testNativeInputReceiver()
            await testInputSourceRouting()
            await testFontShortcuts()
            await testNumericCommandsAndKeyRouting()
            await testSpeechReaderLifecycle()
            await testWindowChromeAndDrag()
            await testEmptySubmitCoaching()
            await testStatsWording()
            await testRatioChangeKeepsInput()
            await testSmallWindowLimitsAndRestore()
            await testLibraryDeleteConfirmation()
            await testMistakeBook()
            await testMistakeHistorySurvivesReload()
            await testMistakeRecording()
            await testMistakePracticeOffline()
            await testSourceSwitchCancelsAutoAdvance()
            await testSourceSwitchFromSong()
            await testPlaybackIssueStates()
            await testPauseOwnership()
            await testMissingSampleKeepsSession()
            await testFirstCommandConfirmationTimeout()
            await testMusicProblemForwarding()
            await testCorruptMistakeFile()
            await testMistakeSaveFailure()
            await testIsolation()
            await testNetwork()

            let passed = checks - failures
            print("== 完成：\(passed)/\(checks) 通过，\(failures) 失败 ==")
            exit(failures == 0 ? 0 : 1)
        }
        RunLoop.main.run()
        exit(1)
    }

    // MARK: 替身

    /// 记录播放命令，但绝不接触真实 Music。
    private final class SpyMusicController: MusicControlling {
        private(set) var commands: [String] = []
        private(set) var seeks: [(seconds: TimeInterval, play: Bool)] = []

        var didControl: Bool { !commands.isEmpty || !seeks.isEmpty }

        func send(_ command: MusicCommand) {
            commands.append(String(describing: command))
        }

        func seek(to seconds: TimeInterval, play: Bool) {
            seeks.append((seconds, play))
        }
    }

    // MARK: 环境

    private static func tempURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gapsong-selftest-\(name)-\(UUID().uuidString).json")
    }

    private static func tempDir(_ name: String) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gapsong-selftest-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private static func makeSettings() -> (Settings, UserDefaults, String) {
        let suite = "gapsong.selftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (Settings(defaults: defaults), defaults, suite)
    }

    // MARK: 听写

    private static func testDictation() {
        let cases: [(String, String, Bool, String)] = [
            ("I kept the lanterns burning low", "i kept the lanterns burning low", true, "大小写不计"),
            ("I kept the lanterns burning low", "I kept the lanterns burning low.", true, "句末标点不计"),
            ("Don't fold the map before the ink is dry", "dont fold the map before the ink is dry", true, "漏撇号不计"),
            ("We carry quiet maps of home", "We carry quiet maps of hope", false, "换词要判错"),
            ("I kept the lanterns burning low", "I kept the lanterns burning lo", false, "少一个字母要判错"),
            ("Every window held a brighter sky", "Every window held a brighter sky", true, "完全一致"),
            ("Morning found the harbor painted gold", "morningfoundtheharborpaintedgold", true, "整句连写算对"),
            ("Morning found the harbor painted gold", "morning  found the harbor painted gold", true, "多空格算对"),
            ("Morning found the harbor painted gold", "morningfoundtheharborpaintedgld", false, "连写也不能少字母"),
            ("Morning found the harbor painted gold", "morningfoundtheharborpaintedgoldd", false, "连写多打字母要判错")
        ]
        var passed = 0
        for (expected, actual, want, note) in cases {
            let got = DictationJudge.judge(expected: expected, actual: actual).isCorrect
            if got == want {
                passed += 1
            } else {
                info("✗ 判分「\(note)」: \(expected) vs \(actual) → \(got)")
            }
        }

        var consistent = true
        for (expected, actual, _, note) in cases {
            let result = DictationJudge.judge(expected: expected, actual: actual)
            let e = DictationJudge.comparisonChars(expected)
            let a = DictationJudge.comparisonChars(actual)
            let allGreen = e.count == a.count && zip(e, a).allSatisfy { $0 == $1 }
            if allGreen, !result.isCorrect {
                consistent = false
                info("✗ 全绿却判错「\(note)」: \(expected) vs \(actual)")
            }
        }

        let aligned = DictationJudge.judge(
            expected: "I kept the lanterns burning low",
            actual: "I kept the lanterns burning law"
        )
        let wrongWords = aligned.tokens.filter { !$0.matched }.count
        check(passed == cases.count, "听写判分: \(passed)/\(cases.count) 通过，错词高亮 \(wrongWords) 处")
        check(consistent, "判分/着色口径一致")
    }

    private static func testPracticeFilter() {
        let raw = """
        [00:01.00]♪
        [00:03.00]Oh oh oh
        [00:06.00]I kept the lanterns burning low
        [00:11.00]遠い灯台がゆっくり光る
        [00:16.00]I kept the lanterns burning low
        [00:21.00]The river carried names we never said
        """
        let parsed = LRCParser.parse(raw)
        let picked = PracticeFilter.practiceableIndices(lines: parsed.lines, trackDuration: 30)
        let texts = picked.map { parsed.lines[$0].text }
        check(texts == ["I kept the lanterns burning low", "The river carried names we never said"], "听写筛句: \(texts)")

        let slow = [
            LyricLine(time: 0, text: "first"),
            LyricLine(time: 10, text: "second"),
            LyricLine(time: 14, text: "third")
        ]
        let longEnd = PracticeFilter.endTime(lines: slow, index: 0, trackDuration: 60)
        let shortEnd = PracticeFilter.endTime(lines: slow, index: 1, trackDuration: 60)
        check(abs(longEnd - 10) < 0.001 && abs(shortEnd - 14) < 0.001,
              "句末边界: 长句 end=\(longEnd)（应为 10.0），短句 end=\(shortEnd)（应为 14.0）")
    }

    private static func testPracticeBlanks() {
        let line = "I kept the lanterns burning low"
        let words = PracticeBlanks.words(in: line)
        let eligible = words.filter(\.isEligible).count

        var ok = eligible == 6
        var details: [String] = []
        for ratio in [0.3, 0.5, 0.6, 1.0] {
            let blanks = PracticeBlanks.blankIndices(in: line, ratio: ratio)
            let expected = min(eligible, max(1, Int((ratio * Double(eligible)).rounded())))
            let stable = blanks == PracticeBlanks.blankIndices(in: line, ratio: ratio)
            let valid = blanks.allSatisfy { words.indices.contains($0) && words[$0].isEligible }
            let ordered = blanks == blanks.sorted() && blanks.count == Set(blanks).count
            ok = ok && blanks.count == expected && stable && valid && ordered
            details.append("\(Int((ratio * 100).rounded()))%→\(blanks.count) 词")
        }

        let full = PracticeBlanks.blankIndices(in: line, ratio: 1.0)
        let answer = PracticeBlanks.expectedAnswer(in: line, blankIndices: full)
        check(ok, "填空比例: \(details.joined(separator: "，"))")
        check(full.count == eligible && answer == line, "填空口径: 100% 期望答案 = \"\(answer)\"")
        check(PracticeBlanks.blankIndices(in: "遠い灯台がゆっくり光る", ratio: 0.5).isEmpty,
              "非英文行不挖空")
    }

    // MARK: 引擎工具

    /// 可观测的静音音效替身：只计数，不真的播放
    @MainActor
    private final class SpyTypingSound: TypingSoundPlaying {
        private(set) var plays = 0
        private(set) var events: [Character] = []
        func playTick() { plays += 1 }
    }

    /// 朗读探针：记录每次请求和 token，可按任意顺序回调旧 token 模拟迟到取消
    @MainActor
    private final class SpySpeechSpeaker: SpeechSpeaking {
        var onFinish: ((UInt64) -> Void)?
        private(set) var isSpeaking = false
        private(set) var spoken: [(text: String, token: UInt64)] = []
        private(set) var stops = 0
        var available = true

        func speak(_ text: String, token: UInt64) -> Bool {
            guard available else { return false }
            spoken.append((text, token))
            isSpeaking = true
            return true
        }

        func stop() {
            stops += 1
            isSpeaking = false
        }

        /// 模拟「已请求但还没开口」：isSpeaking 暂时为 false
        func simulatePendingStart() { isSpeaking = false }

        func finish(token: UInt64) {
            isSpeaking = false
            onFinish?(token)
        }
    }

    @MainActor
    private static func typeCharacters(
        _ engine: PracticeEngine,
        _ text: String,
        sound: Bool = false
    ) {
        for ch in text {
            engine.typeCharacter(ch, playSound: sound)
        }
    }

    /// 按逐空接口填入某个空的期望词（不经过 input 的兼容 setter）
    @MainActor
    private static func typeExpected(_ engine: PracticeEngine, at ordinal: Int, sound: Bool = false) {
        engine.selectBlank(ordinal)
        typeCharacters(
            engine,
            String(DictationJudge.comparisonChars(engine.expectedWord(atBlank: ordinal))),
            sound: sound
        )
    }

    @MainActor
    private static func typeAllBlanks(_ engine: PracticeEngine, sound: Bool = false) {
        for ordinal in engine.blankIndices.indices {
            typeExpected(engine, at: ordinal, sound: sound)
        }
    }

    @MainActor
    private static func clearBlank(_ engine: PracticeEngine, at ordinal: Int) {
        engine.selectBlank(ordinal)
        while !engine.typedChars(forBlank: ordinal).isEmpty {
            engine.deleteBackward()
        }
    }

    /// 原生接收层测试夹具：真实 PracticeInputTextView + 独立 pasteboard。
    @MainActor
    private static func makeNativeInputHarness(
        line: String,
        settings: Settings
    ) -> (PracticeEngine, PracticeInputTextView, SpyTypingSound) {
        let bank = QuestionBank(url: tempURL("native-input-bank"))
        _ = bank.add(
            text: line, translation: nil,
            title: "Fixture", artist: "Test Only", lineTime: 1
        )
        let spy = SpyTypingSound()
        let engine = PracticeEngine(
            state: PlayerState(), watcher: SpyMusicController(), settings: settings,
            bank: bank, mistakes: MistakeBook(url: tempURL("native-input-mistakes"))
        )
        engine.typingSoundPlayer = spy
        engine.onTypingSoundEvent = { _ in }
        engine.begin(source: .bank, ratio: 1.0)
        let view = PracticeInputTextView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        view.engine = engine
        return (engine, view, spy)
    }

    @MainActor
    private static func fillAllBlanks(_ engine: PracticeEngine) {
        let count = engine.blankIndices.count
        guard count > 0 else { return }
        engine.input = (0..<count)
            .map { String(DictationJudge.comparisonChars(engine.expectedWord(atBlank: $0))) }
            .joined()
    }

    @MainActor
    private static func makeQuestion(
        _ text: String,
        title: String = "Paper Lanterns",
        artist: String = "The Quiet Harbor",
        lineTime: TimeInterval? = 12,
        translation: String? = "我让灯笼低低地燃着"
    ) -> PracticeQuestion {
        PracticeQuestion(
            text: text,
            translation: translation,
            title: title,
            artist: artist,
            start: nil,
            end: nil,
            lineTime: lineTime
        )
    }

    // MARK: 空格切换横线

    @MainActor
    private static func testBlankNavigation() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = PlayerState()
        let bankURL = tempURL("blank-bank")
        let bank = QuestionBank(url: bankURL)
        let mistakes = MistakeBook(url: tempURL("blank-mistakes"))
        bank.add(
            text: "I kept the lanterns burning low", translation: "我让灯笼低低地燃着",
            title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12
        )

        let engine = PracticeEngine(
            state: state, watcher: SpyMusicController(), settings: settings,
            bank: bank, mistakes: mistakes
        )
        state.debugInject(
            track: Track(title: "Paper Lanterns", artist: "The Quiet Harbor", album: "", duration: 242),
            position: 12, playing: false, lines: [], translations: [:]
        )
        engine.setEnabled(true)
        engine.begin(source: .bank, ratio: 1.0)

        let total = engine.blankIndices.count
        engine.input = String(DictationJudge.comparisonChars(engine.expectedWord(atBlank: 0)))
        let autoAfterFirst = engine.activeBlank == 1
        engine.input += String(DictationJudge.comparisonChars(engine.expectedWord(atBlank: 1)))

        let skippedActive = engine.activeBlank == 2
        let filled = engine.filledBlankCount
        engine.submit()

        check(autoAfterFirst, "填满当前空自动跳到下一个空")
        check(skippedActive, "填完 2 个空后停在 3/\(total)")
        check(filled == 2, "已填数量: \(filled)/\(total)")
        check(engine.verdict?.isCorrect == true, "只填部分空也判对（跳过的空不算错）")
        check(engine.stats.correct == 1 && engine.stats.wrong == 0, "部分填写计入答对、不计答错")
        check(engine.score == 4, "得分按填写比例折算: \(engine.score) 分（期望 4）")

        engine.setEnabled(false)
        try? FileManager.default.removeItem(at: bankURL)
    }

    /// 用户实际反馈的 “But I know it may hurt…”：跳过第一个空 But，填完后面，
    /// 再回到 But 补填；同时验证长词、撇号、粘贴不隔空漏空。
    @MainActor
    private static func testBlankRevisitAndPaste() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let target = "But I know it may hurt, but it won't last forever"
        let bankURL = tempURL("revisit-bank")
        let bank = QuestionBank(url: bankURL)
        let mistakes = MistakeBook(url: tempURL("revisit-mistakes"))
        guard bank.add(
            text: target, translation: "但我知道这可能会很疼，可它不会永远持续",
            title: "STORM II", artist: "Fixture", lineTime: 57.08
        ) else {
            check(false, "准备 STORM II 回归句")
            return
        }

        let spySound = SpyTypingSound()
        let engine = PracticeEngine(
            state: PlayerState(), watcher: SpyMusicController(), settings: settings,
            bank: bank, mistakes: mistakes
        )
        engine.typingSoundPlayer = spySound
        settings.typingSound = true
        engine.begin(source: .bank, ratio: 1.0)

        let total = engine.blankIndices.count
        check(total == 11, "STORM II 句 100% 挖空 11 个词（实际 \(total)）")
        check(engine.expectedWord(atBlank: 0) == "But", "第 1 空是 I know 前面的 But")

        // 跳过 But，把后面的空填完（故意把 I 填错，先不让它自动过）
        engine.selectBlank(0)
        engine.advanceBlank()
        engine.selectBlank(1)
        typeCharacters(engine, "z")
        for ordinal in 2..<total {
            typeExpected(engine, at: ordinal)
        }
        check(engine.filledBlankCount == total - 1, "只跳过首空时其余 \(total - 1) 个空已填")
        check(String(engine.typedChars(forBlank: 8)) == "wont",
              "撇号词 won't 按判分口径落为 wont")

        // 从最后一个空按空格，应该回到第一个还没填的空（But）
        engine.selectBlank(total - 1)
        engine.advanceBlank()
        check(engine.activeBlank == 0, "空格从末尾循环回第一个未填空（实际 \(engine.activeBlank)）")

        // 补入 But：不删后续任何内容
        typeCharacters(engine, "But")
        check(String(engine.typedChars(forBlank: 0)) == "but", "跳过的首空可以回头补入 But")
        check(engine.filledBlankCount == total, "补入 But 后所有空都有内容")
        check(engine.stats.correct == 0, "还有错空时不会自动通过")

        // 修正 I，全对后离线自动推进（唯一一题 → 练完）
        clearBlank(engine, at: 1)
        typeExpected(engine, at: 1)
        check(engine.stats.correct == 1, "全部填对后离线自动推进并计分")
        check(engine.phase == .idle, "单题全对自动收尾")

        // 粘贴：空格不能造成隔一个空漏一个空
        let pasteItem = bank.items.first
        guard let pasteID = pasteItem?.id else {
            check(false, "准备粘贴回归题")
            return
        }
        let pasteSound = SpyTypingSound()
        let pasteEngine = PracticeEngine(
            state: PlayerState(), watcher: SpyMusicController(), settings: settings,
            bank: bank, mistakes: mistakes
        )
        pasteEngine.typingSoundPlayer = pasteSound
        pasteEngine.begin(source: .bank, ratio: 1.0, onlyID: pasteID)
        pasteEngine.insertBulk("But I know it may hurt,")
        let firstSix = (0..<6).map { String(pasteEngine.typedChars(forBlank: $0)) }
        check(firstSix == ["but", "i", "know", "it", "may", "hurt"],
              "整句粘贴按顺序落空，不隔空: \(firstSix)")
        check(pasteEngine.typedChars(forBlank: 6).isEmpty, "粘贴 6 个词后第 7 空仍为空")
        check(pasteSound.plays == 0, "粘贴不发声")

        pasteEngine.insertBulk("but it won't last forever")
        check(pasteEngine.stats.correct == 1 && pasteEngine.phase == .idle,
              "粘贴补齐全句后整体判对并自动推进")
        check(pasteSound.plays == 0, "补齐粘贴仍然不发声")

        engine.setEnabled(false)
        pasteEngine.setEnabled(false)
        try? FileManager.default.removeItem(at: bankURL)
    }

    /// 判分器认可的等价写法（four / 4）不能被“每空字符数 >= 原文词长”挡住
    @MainActor
    private static func testDigitEquivalentAutoAdvance() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let bankURL = tempURL("digit-bank")
        let bank = QuestionBank(url: bankURL)
        _ = bank.add(
            text: "four lanterns shine", translation: "四盏灯笼亮着",
            title: "Fixture", artist: "Test Only", lineTime: 1
        )
        let engine = PracticeEngine(
            state: PlayerState(), watcher: SpyMusicController(), settings: settings,
            bank: bank, mistakes: MistakeBook(url: tempURL("digit-mistakes"))
        )
        engine.begin(source: .bank, ratio: 1.0)

        engine.selectBlank(0)
        typeCharacters(engine, "4")
        engine.advanceBlank()
        typeExpected(engine, at: 1)
        typeExpected(engine, at: 2)
        check(engine.stats.correct == 1 && engine.phase == .idle,
              "4 / four 等价答案全填后自动通过（不被词长拦住）")
        engine.setEnabled(false)
        try? FileManager.default.removeItem(at: bankURL)
    }

    /// 歌曲时序：早填全对等句末、自然边界不 pause/不倒退 seek、未填全不自动过、
    /// 播放中错后改对、句末停后改对推进、自动推进只发生一次。
    @MainActor
    private static func testAutoAdvanceTiming() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let line1 = "But I know it may hurt, but it won't last forever"
        let line2 = "The river carried names we never said"
        let parsed = LRCParser.parse("[00:10.00]\(line1)\n[00:20.00]\(line2)")
        let track = Track(title: "Timing Fixture", artist: "Test Only", album: "", duration: 30)
        let state = PlayerState()
        state.debugInject(track: track, position: 10, playing: true, lines: parsed.lines, translations: [:])
        let spy = SpyMusicController()
        let engine = PracticeEngine(
            state: state, watcher: spy, settings: settings,
            bank: QuestionBank(url: tempURL("timing-bank")),
            mistakes: MistakeBook(url: tempURL("timing-mistakes"))
        )
        var now = Date()
        engine.clock = { now }
        func tick(_ seconds: Double) {
            now = now.addingTimeInterval(seconds)
            engine.debugTick()
        }
        func sample(_ position: Double, playing: Bool = true) {
            state.debugSetPlayback(position: position, playing: playing, sampledAt: now)
        }
        func beginAndConfirm() {
            engine.begin(source: .song, ratio: 1.0)
            now = now.addingTimeInterval(0.4)
            sample(10.4)
            engine.debugTick()
        }

        // 1) 早填全对：只挂起，不暂停、不 seek、不提前计分
        beginAndConfirm()
        let seeksAfterBegin = spy.seeks.count
        let commandsAfterBegin = spy.commands.count
        typeAllBlanks(engine)
        check(engine.phase == .listening && engine.current?.text == line1,
              "早填全对仍停在当前句收听态")
        check(engine.stats.correct == 0, "早填全对在句末前不计分")
        check(spy.commands.count == commandsAfterBegin && spy.seeks.count == seeksAfterBegin,
              "早填全对不 pause、不提前 seek")
        now = now.addingTimeInterval(10.0)
        sample(20.3)
        engine.debugTick()
        check(engine.current?.text == line2 && engine.phase == .listening,
              "到达真实句末后切到下一题")
        check(engine.stats.correct == 1, "句末推进时计分一次")
        check(spy.commands.count == commandsAfterBegin, "自然句末推进不 pause")
        check(spy.seeks.count == seeksAfterBegin, "自然句末推进不倒退 seek 重唱")
        engine.debugTick()
        check(engine.stats.correct == 1 && engine.current?.text == line2,
              "自动推进只发生一次")

        // 2) 未填全：句末照旧暂停，不自动过
        beginAndConfirm()
        let total = engine.blankIndices.count
        for ordinal in 0..<(total - 1) {
            typeExpected(engine, at: ordinal)
        }
        now = now.addingTimeInterval(10.0)
        sample(20.3)
        engine.debugTick()
        check(engine.phase == .asking && engine.stats.correct == 0,
              "未填全不自动过，句末暂停进入答题")
        check(engine.typedChars(forBlank: total - 1).isEmpty,
              "未填的最后一个空保持为空")

        // 3) 句末已经停下后才填对：立即推进，并用 seek(play:) 启动下一句
        typeExpected(engine, at: total - 1)
        check(engine.stats.correct == 1 && engine.current?.text == line2,
              "句末停后改对立即推进并计分")
        check(spy.seeks.last?.seconds == 20 && spy.seeks.last?.play == true,
              "句末停后推进才 seek(play:) 启动下一句")

        // 4) 播放中错后改对：改对后等句末，不抢跑
        beginAndConfirm()
        let total2 = engine.blankIndices.count
        for ordinal in 0..<total2 where ordinal != 1 {
            typeExpected(engine, at: ordinal)
        }
        engine.selectBlank(1)
        typeCharacters(engine, "z")
        check(engine.phase == .listening && engine.stats.correct == 0,
              "播放中填满但有一空错时不自动通过")
        clearBlank(engine, at: 1)
        typeExpected(engine, at: 1)
        check(engine.phase == .listening && engine.current?.text == line1,
              "播放中改对后仍等句末，不抢跑")
        now = now.addingTimeInterval(10.0)
        sample(20.3)
        engine.debugTick()
        check(engine.stats.correct == 1 && engine.current?.text == line2,
              "播放中错后改对，在句末自动推进")

        engine.setEnabled(false)
    }

    /// U1：480×380 下控件有可读下限，同时正文/输入字母在字号 14–72 每一档
    /// 都真正变化（不能在下限处压平，否则又回到「调字号没反应」）。
    @MainActor
    private static func testPracticeTypographyFloors() {
        let small = PracticeStyle.windowScale(
            width: Settings.practiceMinSize.width,
            height: Settings.practiceMinSize.height
        )
        let normal = PracticeStyle.windowScale(width: 720, height: 400)
        check(small < 0.7 && abs(normal - 1) < 0.001,
              "窗口系数：最小窗 \(String(format: "%.3f", small)) / 正常窗 \(String(format: "%.3f", normal))")

        // 按钮：固定可读下限，最小窗和正常窗一样大，不跟字号菜单缩
        check(PracticeStyle.control(small) >= 11,
              "480×380 按钮文字 \(String(format: "%.1f", PracticeStyle.control(small)))pt ≥ 11pt")
        check(abs(PracticeStyle.control(small) - PracticeStyle.control(normal)) < 0.001,
              "最小窗与正常窗按钮字号一致")
        // 提示：默认 24 字号、最小窗不再落到 6–7pt
        check(PracticeStyle.hint(small) >= 10.5,
              "480×380 提示文字 \(String(format: "%.1f", PracticeStyle.hint(small)))pt ≥ 10.5pt")
        check(PracticeStyle.hint(small, factor: Settings.practiceFontFactor(38))
              > PracticeStyle.hint(small, factor: Settings.practiceFontFactor(24)),
              "大字号下提示仍会变大（38 > 24）")

        // 正文/输入字母：14–72 每一档都严格变高。
        // 这里量的是真实 AppKit 文本高度，不是只看公式。
        let fonts: [Double] = [14, 16, 18, 20, 22, 24, 38, 72]
        let inputSizes = fonts.map {
            PracticeStyle.body(small, factor: Settings.practiceFontFactor($0), base: 20)
        }
        let inputHeights = inputSizes.map(measuredTextHeight)
        check(zip(inputHeights, inputHeights.dropFirst()).allSatisfy { $1 > $0 },
              "最小窗输入字高 14/16/18/20/22/24/38/72 严格递增: "
              + zip(fonts, inputHeights).map { "\(Int($0))→\(String(format: "%.2f", $1))" }.joined(separator: " / "))

        // 整个 14–72 量程逐点检查：每 +1 字号都必须变高，不能有平台
        let wholeSizes = (14...72).map {
            PracticeStyle.body(small, factor: Settings.practiceFontFactor(Double($0)), base: 20)
        }
        check(zip(wholeSizes, wholeSizes.dropFirst()).allSatisfy { $1 > $0 },
              "最小窗输入字号 14…72 逐点严格递增，没有中途 clamp")
        check(inputSizes[5] >= 20 * small,
              "默认字号 24 的输入文字没有被可读下限改小: \(String(format: "%.2f", inputSizes[5]))pt")
        check(abs(inputSizes[5] - 20 * PracticeStyle.bodyScaleFloor) < 0.001,
              "默认字号 24、最小窗：输入文字 16pt（旧版 13.3pt）")

        // 关键操作提示的对比度：按 Codex 原生抽样里较亮的浮窗底色（gray 72）
        // 估算，普通小字要达到约 4.5:1。离屏快照的纯黑背景不作为依据。
        let tertiaryContrast = approximateContrast(
            alpha: PracticeStyle.Ink.tertiaryOpacity, backgroundGray: 72
        )
        check(tertiaryContrast >= 4.5,
              "操作提示在较亮浮窗底（gray 72）约 \(String(format: "%.2f", tertiaryContrast)):1 ≥ 4.5:1")
        check(PracticeStyle.Ink.tertiaryOpacity > PracticeStyle.Ink.mutedOpacity,
              "操作提示比来源/序号等元信息更亮（0.62 > 0.46）")

        // 正常窗保持原排版：默认字号下输入/正文与旧版一致
        check(abs(PracticeStyle.body(normal, factor: 1, base: 20) - 20) < 0.001,
              "正常窗默认字号正文仍为 20pt")
        check(abs(PracticeStyle.body(normal, factor: Settings.practiceFontFactor(72), base: 20) - 60) < 0.001,
              "正常窗 72 字号正文 60pt（14–72 线性可用）")
    }

    /// 真实文本高度（AppKit 字体度量，快照之外的第二重验证）
    private static func measuredTextHeight(_ size: CGFloat) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return ("lanterns" as NSString).size(withAttributes: [.font: font]).height
    }

    /// 近似 WCAG 对比度：白色以 alpha 叠加在指定灰度的背景上。
    /// 只用于确认语义色在较亮原生浮窗背景上的余量，不替代完整可访问性结论。
    private static func approximateContrast(alpha: CGFloat, backgroundGray: Double) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let bg = backgroundGray / 255
        let fg = Double(alpha) + (1 - Double(alpha)) * bg
        let lighter = max(linear(fg), linear(bg))
        let darker = min(linear(fg), linear(bg))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// U2/U3：全对等待反馈、改错清除、异常不误报、回车提示与重试入口去重。
    /// 不改既有推进时序：只在真实句末推进，且只计分一次。
    @MainActor
    private static func testWaitingFeedbackAndPrimaryActions() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let line1 = "But I know it may hurt, but it won't last forever"
        let line2 = "The river carried names we never said"
        let parsed = LRCParser.parse("[00:10.00]\(line1)\n[00:20.00]\(line2)")
        let track = Track(title: "Waiting Fixture", artist: "Test Only", album: "", duration: 40)
        let state = PlayerState()
        state.debugInject(track: track, position: 10, playing: true, lines: parsed.lines, translations: [:])
        let spy = SpyMusicController()
        let bankURL = tempURL("waiting-bank")
        let mistakeURL = tempURL("waiting-mistakes")
        let bank = QuestionBank(url: bankURL)
        _ = bank.add(
            text: "I kept the lanterns burning low", translation: nil,
            title: "Fixture", artist: "Test Only", lineTime: 1
        )
        let engine = PracticeEngine(
            state: state, watcher: spy, settings: settings,
            bank: bank, mistakes: MistakeBook(url: mistakeURL)
        )
        var now = Date()
        engine.clock = { now }
        func tick(_ seconds: Double) {
            now = now.addingTimeInterval(seconds)
            engine.debugTick()
        }
        func sample(_ position: Double, playing: Bool = true) {
            state.debugSetPlayback(position: position, playing: playing, sampledAt: now)
        }

        engine.begin(source: .song, ratio: 1.0)
        now = now.addingTimeInterval(0.4)
        sample(10.4)
        tick(0.01)
        check(!engine.showsReturnHint, "收听中不显示回车提示（时序仍由句末边界决定）")
        check(!engine.isWaitingForLineEnd && engine.currentLineProgress(at: now) != nil,
              "未全对时没有等待确认，但句级进度可用")
        let seeksBefore = spy.seeks.count
        let commandsBefore = spy.commands.count

        typeAllBlanks(engine)
        check(engine.isWaitingForLineEnd, "提前填全对后进入「全部正确、等句末」状态")
        check(PracticeEngine.allCorrectWaitingText.contains("全部正确")
              && PracticeEngine.allCorrectWaitingText.contains("唱完这句后继续"),
              "等待文案明确: \(PracticeEngine.allCorrectWaitingText)")
        check(engine.phase == .listening && engine.stats.correct == 0,
              "等待句末不提前切题、不提前计分")
        if let progress = engine.currentLineProgress(at: now) {
            check(progress > 0 && progress < 1,
                  "句级进度在句内: \(String(format: "%.2f", progress))")
        } else {
            check(false, "等句末时句级进度可用")
        }
        check(spy.seeks.count == seeksBefore && spy.commands.count == commandsBefore,
              "等句末不 pause、不提前 seek")

        // 改错立刻清掉确认；改回再重新挂起
        engine.selectBlank(0)
        typeCharacters(engine, "z")
        check(!engine.isWaitingForLineEnd, "改错后清掉全对等待反馈")
        engine.selectBlank(0)
        engine.deleteBackward()
        check(engine.isWaitingForLineEnd, "删掉多余字母、仍然全对时重新等待句末")
        engine.selectBlank(0)
        engine.deleteBackward()
        check(!engine.isWaitingForLineEnd, "删掉正确字母后未填全，不再显示全对等待")
        clearBlank(engine, at: 0)
        typeExpected(engine, at: 0)
        check(engine.isWaitingForLineEnd, "补回正确答案后重新进入等待")

        // 手动暂停：不能误显示「等句末」，重试入口只留在状态卡片
        sample(11.0, playing: false)
        tick(0.4)
        tick(2.0)
        tick(2.0)
        check(engine.playbackIssue == .paused, "手动暂停被识别")
        check(!engine.isWaitingForLineEnd, "手动暂停时不显示「全部正确、等句末」")
        check(engine.playbackIssuePrimaryAction == .retry
              && engine.playbackNotice?.retryActionLabel == "继续播放",
              "暂停时主操作是「继续播放」")
        check(!engine.showsRetryInActionBar, "异常时底部不再重复重试入口")

        // 缺权限：优先打开系统设置，重试降为次要但仍可达
        engine.reportMusicProblem(.unauthorized)
        check(engine.playbackIssuePrimaryAction == .openSettings,
              "缺权限时主操作是「打开系统设置」")
        check(engine.playbackNotice?.offersSecondaryRetry == true,
              "授权后仍保留一个次要重试入口")
        check(!engine.isWaitingForLineEnd, "授权异常时不误显示等句末")

        // 用户显式恢复：重新挂起，仍然只等真实句末
        engine.resumePlayback()
        check(engine.playbackIssue == nil && engine.isWaitingForLineEnd,
              "显式恢复后重新确认等待句末")
        let seeksAfterResume = spy.seeks.count
        now = now.addingTimeInterval(0.5)
        sample(11.0)
        tick(0.01)
        check(engine.isWaitingForLineEnd && engine.stats.correct == 0,
              "恢复后的第一条采样只确认命令，不抢跑")
        now = now.addingTimeInterval(9.0)
        sample(20.3)
        tick(0.01)
        check(engine.current?.text == line2 && engine.phase == .listening,
              "真实句末才切到下一句")
        check(engine.stats.correct == 1 && !engine.isWaitingForLineEnd,
              "句末推进只计分一次，等待确认随之消失")
        check(spy.seeks.count == seeksAfterResume, "自然句末推进不额外 seek")

        // 句末暂停（asking）：显示回车提示；空提交只提示不计错
        check(!engine.showsReturnHint, "收听下一句时仍不显示回车提示")
        now = now.addingTimeInterval(10.0)
        sample(30.3)
        tick(0.01)
        check(engine.phase == .asking && engine.showsReturnHint,
              "句末暂停后显示「回车继续」提示")
        check(!engine.isWaitingForLineEnd && engine.currentLineProgress(at: now) == nil,
              "回答时不显示等句末/句级进度")
        engine.submit()
        check(engine.coaching != nil && engine.stats.wrong == 0 && engine.phase == .asking,
              "空提交只提示、不计错、不离开答题")

        // 离线来源：同样显示回车提示，但没有播放/等待状态
        engine.begin(source: .bank, ratio: 1.0)
        check(engine.phase == .asking && engine.showsReturnHint,
              "离线答题也显示「回车继续」提示")
        check(!engine.isWaitingForLineEnd && engine.playbackNotice == nil,
              "离线来源不出现等句末/播放异常")
        check(engine.currentLineProgress(at: now) == nil, "离线来源没有句级播放进度")
        check(engine.showsRetryInActionBar, "无异常时底部不出现重试入口")

        engine.setEnabled(false)
        try? FileManager.default.removeItem(at: bankURL)
        try? FileManager.default.removeItem(at: mistakeURL)
    }

    /// 异常提示期间已经填全对：显式恢复播放后重新建立“等句末推进”，
    /// 恢复瞬间不抢跑，也不额外播放。
    @MainActor
    private static func testResumeAfterIssueReArmsAuto() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let line1 = "But I know it may hurt, but it won't last forever"
        let line2 = "The river carried names we never said"
        let parsed = LRCParser.parse("[00:10.00]\(line1)\n[00:20.00]\(line2)")
        let track = Track(title: "Issue Fixture", artist: "Test Only", album: "", duration: 30)
        let state = PlayerState()
        state.debugInject(track: track, position: 10, playing: true, lines: parsed.lines, translations: [:])
        let spy = SpyMusicController()
        let engine = PracticeEngine(
            state: state, watcher: spy, settings: settings,
            bank: QuestionBank(url: tempURL("issue-bank")),
            mistakes: MistakeBook(url: tempURL("issue-mistakes"))
        )
        var now = Date()
        engine.clock = { now }
        func tick(_ seconds: Double) {
            now = now.addingTimeInterval(seconds)
            engine.debugTick()
        }
        func sample(_ position: Double, playing: Bool = true) {
            state.debugSetPlayback(position: position, playing: playing, sampledAt: now)
        }

        engine.begin(source: .song, ratio: 1.0)
        now = now.addingTimeInterval(0.4)
        sample(10.4)
        engine.debugTick()

        // 异常期间填全对：不推进、不播放
        engine.debugRaise(.paused)
        typeAllBlanks(engine)
        let pausesBefore = spy.commands.filter { $0 == "pause" }.count
        check(engine.phase == .listening && engine.current?.text == line1,
              "异常提示期间填全对不推进")
        check(engine.stats.correct == 0, "异常期间不计分")
        check(spy.commands.filter { $0 == "pause" }.count == pausesBefore,
              "异常期间不额外 pause")

        // 用户显式恢复：只发一次 seek(play:)，重新挂起等待句末
        engine.resumePlayback()
        check(engine.playbackIssue == nil && engine.phase == .listening,
              "显式恢复清掉异常并回到收听")
        check(spy.seeks.last?.play == true, "恢复只发 seek(play:)")
        check(engine.stats.correct == 0 && engine.current?.text == line1,
              "恢复瞬间不抢跑、不计分")

        now = now.addingTimeInterval(0.5)
        sample(10.5)
        engine.debugTick()
        now = now.addingTimeInterval(10.0)
        sample(20.3)
        engine.debugTick()
        check(engine.stats.correct == 1 && engine.current?.text == line2,
              "恢复后重新唱到句末才自动下一题")
        check(spy.commands.filter { $0 == "pause" }.count == pausesBefore,
              "恢复后的自动推进不 pause")

        // 采样消失同样不抢播；恢复后重新挂起
        engine.setEnabled(true)
        now = now.addingTimeInterval(0.4)
        state.debugInject(track: track, position: 10, playing: true, lines: parsed.lines, translations: [:])
        engine.begin(source: .song, ratio: 1.0)
        now = now.addingTimeInterval(0.4)
        sample(10.4)
        engine.debugTick()
        typeAllBlanks(engine)
        state.debugClearSnapshot()
        tick(0.5)
        tick(3.0)
        check(engine.playbackIssue == .musicStopped && engine.stats.correct == 0,
              "采样消失时已挂起的自动推进不抢播")
        engine.resumePlayback()
        check(engine.playbackIssue == nil && engine.phase == .listening,
              "采样恢复后显式重试回到收听")
        now = now.addingTimeInterval(0.5)
        state.debugInject(track: track, position: 10.5, playing: true, lines: parsed.lines, translations: [:])
        sample(10.5)
        engine.debugTick()
        now = now.addingTimeInterval(10.0)
        sample(20.3)
        engine.debugTick()
        check(engine.stats.correct == 1 && engine.current?.text == line2,
              "采样恢复后仍只在可信句末推进")

        engine.setEnabled(false)
    }

    /// “再试试”：歌曲来源从当前句句首重播；不额外 pause、不重复计分
    @MainActor
    private static func testRetryReplaysMusic() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let line1 = "But I know it may hurt, but it won't last forever"
        let line2 = "The river carried names we never said"
        let parsed = LRCParser.parse("[00:10.00]\(line1)\n[00:20.00]\(line2)")
        let track = Track(title: "Retry Fixture", artist: "Test Only", album: "", duration: 30)
        let state = PlayerState()
        state.debugInject(track: track, position: 10, playing: true, lines: parsed.lines, translations: [:])
        let spy = SpyMusicController()
        let engine = PracticeEngine(
            state: state, watcher: spy, settings: settings,
            bank: QuestionBank(url: tempURL("retry-song-bank")),
            mistakes: MistakeBook(url: tempURL("retry-song-mistakes"))
        )
        var now = Date()
        engine.clock = { now }
        func sample(_ position: Double, playing: Bool = true) {
            state.debugSetPlayback(position: position, playing: playing, sampledAt: now)
        }

        engine.begin(source: .song, ratio: 1.0)
        now = now.addingTimeInterval(0.4)
        sample(10.4)
        engine.debugTick()
        // 让第一句自然唱完并暂停
        now = now.addingTimeInterval(10.0)
        sample(20.3)
        engine.debugTick()
        check(engine.phase == .asking, "句末暂停后进入答题")
        let pausesAfterBoundary = spy.commands.filter { $0 == "pause" }.count
        let seeksAfterBoundary = spy.seeks.count

        engine.giveUp()
        check(engine.phase == .revealed, "看答案进入揭示态")
        engine.retryAfterReveal()
        check(engine.phase == .listening && engine.isRetry, "再试试回到收听态并标记重试")
        check(engine.input.isEmpty && engine.filledBlankCount == 0, "再试试清空本次输入")
        check(spy.seeks.count == seeksAfterBoundary + 1
              && spy.seeks.last?.seconds == 10 && spy.seeks.last?.play == true,
              "再试试从当前句句首 seek(play:) 重播")
        check(spy.commands.filter { $0 == "pause" }.count == pausesAfterBoundary,
              "再试试不额外 pause")

        // 重播过程中可以继续填写；全对等句末，不计分
        typeAllBlanks(engine)
        check(engine.phase == .listening && engine.stats.correct == 0,
              "重播中填写不抢跑")
        now = now.addingTimeInterval(0.5)
        sample(10.5)
        engine.debugTick()
        now = now.addingTimeInterval(10.0)
        sample(20.3)
        engine.debugTick()
        check(engine.current?.text == line2, "重试句在句末自动进入下一题")
        check(engine.stats.correct == 0, "看答案后的重试答对不重复计分")

        engine.setEnabled(false)
    }

    /// 音效开关 / 字母过滤 / 程序同步不触发 / 本地 WAV 短促可解码
    @MainActor
    private static func testTypingSound() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let bankURL = tempURL("sound-bank")
        let bank = QuestionBank(url: bankURL)
        _ = bank.add(
            text: "I kept the lanterns burning low", translation: nil,
            title: "Fixture", artist: "Test Only", lineTime: 1
        )
        let spy = SpyTypingSound()
        let engine = PracticeEngine(
            state: PlayerState(), watcher: SpyMusicController(), settings: settings,
            bank: bank, mistakes: MistakeBook(url: tempURL("sound-mistakes"))
        )
        engine.typingSoundPlayer = spy
        var events = 0
        engine.onTypingSoundEvent = { _ in events += 1 }
        engine.begin(source: .bank, ratio: 1.0)
        settings.typingSound = false

        engine.selectBlank(0)
        engine.typeCharacter("i")
        check(spy.plays == 0, "默认关闭时不发声")

        settings.typingSound = true
        check(defaults.bool(forKey: "typingSound"), "音效开关写入持久化偏好")
        engine.typeCharacter("k")
        check(spy.plays == 1 && events == 1, "打开后每个新字母触发一次")

        engine.typeCharacter("'")
        engine.advanceBlank()
        check(spy.plays == 1, "撇号与空格不触发音效")

        engine.input = "keep"
        check(spy.plays == 1, "程序性赋值不触发音效")
        engine.insertBulk("abc")
        check(spy.plays == 1, "粘贴/批量输入不触发音效")

        engine.selectBlank(0)
        typeCharacters(engine, "abc", sound: true)
        check(spy.plays == 4, "连续字母逐次触发（\(spy.plays)）")

        let wav = TypewriterSoundPlayer.makeClickWAV()
        let header = String(data: wav.prefix(4), encoding: .ascii) ?? ""
        let wave = String(data: wav.dropFirst(8).prefix(4), encoding: .ascii) ?? ""
        let pcmBytes = max(0, wav.count - 44)
        let duration = Double(pcmBytes) / (44_100.0 * 2.0)
        check(header == "RIFF" && wave == "WAVE", "本地合成 WAV 头正确")
        check(duration > 0.01 && duration < 0.05,
              "本地键击音短促（\(String(format: "%.3f", duration))s）")
        check(wav.count > 44, "本地键击音含 PCM 数据")

        engine.setEnabled(false)
        try? FileManager.default.removeItem(at: bankURL)
    }

    /// 原生接收层：真实 PracticeInputTextView 的 insertText / paste / 输入法提交，
    /// 不依赖 AppDelegate 的输入源前缀，也不碰用户真实剪贴板。
    @MainActor
    private static func testNativeInputReceiver() async {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.typingSound = true
        let line = "But I know it may hurt, but it won't last forever"

        // 1) 真实单字母：一次落空 + 一次音效，不写入文本视图
        let (singleEngine, singleView, singleSpy) = makeNativeInputHarness(line: line, settings: settings)
        singleView.insertText("b", replacementRange: NSRange(location: 0, length: 0))
        check(singleSpy.plays == 1,
              "原生 insertText 单字母触发一次音效（不按输入源前缀分流）")
        check(String(singleEngine.typedChars(forBlank: 0)) == "b"
              && singleView.string.isEmpty,
              "原生单字母落空且不写入隐藏文本视图")

        // 2) 多字符提交（粘贴/输入法提交的形态）：逐空批量，不发声
        let (bulkEngine, bulkView, bulkSpy) = makeNativeInputHarness(line: line, settings: settings)
        bulkView.insertText("But I know it may hurt,", replacementRange: NSRange(location: 0, length: 0))
        let bulkFirstSix = (0..<6).map { String(bulkEngine.typedChars(forBlank: $0)) }
        check(bulkSpy.plays == 0, "原生多字符 insertText 不发声")
        check(bulkFirstSix == ["but", "i", "know", "it", "may", "hurt"],
              "原生多字符按顺序落空，不隔空: \(bulkFirstSix)")
        check(bulkView.string.isEmpty, "原生批量不写入隐藏文本视图")

        // 3) 原生 paste：读独立 pasteboard，不发声，保留剪贴板原文
        let (pasteEngine, pasteView, pasteSpy) = makeNativeInputHarness(line: line, settings: settings)
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("gapsong-selftest-paste-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        _ = pasteboard.setString("But I know it may hurt,", forType: .string)
        pasteView.pasteboard = pasteboard
        pasteView.paste(nil)
        let pasteFirstSix = (0..<6).map { String(pasteEngine.typedChars(forBlank: $0)) }
        check(pasteSpy.plays == 0, "原生 paste 不发声")
        check(pasteFirstSix == ["but", "i", "know", "it", "may", "hurt"],
              "原生 paste 直接进入逐空入口: \(pasteFirstSix)")
        check(pasteboard.string(forType: .string) == "But I know it may hurt,",
              "原生 paste 只读剪贴板，原文保留")

        // 4) 输入法组字提交：不发声、不污染逐空内容
        let (imeEngine, imeView, imeSpy) = makeNativeInputHarness(line: line, settings: settings)
        imeView.setMarkedText(
            "ni", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: 0, length: 0)
        )
        imeView.insertText("你", replacementRange: NSRange(location: 0, length: 0))
        check(imeSpy.plays == 0, "输入法组字/提交不发声")
        check(imeEngine.filledBlankCount == 0, "输入法非 ASCII 提交不污染逐空内容")
        imeView.engine = nil

        // 5) 中文组字取消后切回 ABC：残留标记/字符串被清掉，后续真实单字母仍发声
        let (staleEngine, staleView, staleSpy) = makeNativeInputHarness(line: line, settings: settings)
        staleView.setMarkedText(
            "b", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 0, length: 0)
        )
        check(staleView.hasMarkedText(), "残留组字测试已进入标记态")
        staleView.discardPendingComposition()
        check(!staleView.hasMarkedText() && staleView.string.isEmpty,
              "切回普通键盘后残留组字被清空")
        // 让 discard 触发的输入法回调跑完，再模拟下一次真实按键
        try? await Task.sleep(nanoseconds: 30_000_000)
        staleView.insertText("u", replacementRange: NSRange(location: 0, length: 0))
        let staleText = String(staleEngine.typedChars(forBlank: 0))
        check(staleSpy.plays == 1 && staleText == "u",
              "清理残留后真实单字母仍然落空并触发音效: plays=\(staleSpy.plays) blank0=\(staleText) marked=\(staleView.hasMarkedText()) phase=\(staleEngine.phase)")
        staleView.engine = nil

        singleEngine.setEnabled(false)
        bulkEngine.setEnabled(false)
        pasteEngine.setEnabled(false)
        imeEngine.setEnabled(false)
        staleEngine.setEnabled(false)
    }

    /// 输入源分类：ABC/第三方键盘布局走直接字母，输入法关键词走 IME，
    /// 未知来源在未组字时按普通键盘、正在组字时让给输入法。
    @MainActor
    private static func testInputSourceRouting() {
        check(PracticeInputRouting.isPlainKeyboardLayout(
            source: "com.apple.keylayout.ABC", hasMarkedText: true
        ), "ABC 键盘布局（即使有残留标记）按普通键盘处理")
        check(!PracticeInputRouting.isPlainKeyboardLayout(
            source: "com.apple.inputmethod.SCIM.ITABC", hasMarkedText: false
        ), "中文输入法按 IME 处理")
        check(!PracticeInputRouting.isPlainKeyboardLayout(
            source: "com.apple.inputmethod.SCIM.ITABC", hasMarkedText: true
        ), "组字中的中文输入法不被抢键")
        check(PracticeInputRouting.isPlainKeyboardLayout(
            source: nil, hasMarkedText: false
        ), "未知/无输入上下文且未组字时按普通键盘兜底")
        check(!PracticeInputRouting.isPlainKeyboardLayout(
            source: nil, hasMarkedText: true
        ), "未知上下文正在组字时不抢首键")
        check(PracticeInputRouting.isPlainKeyboardLayout(
            source: "com.example.keylayout.Custom", hasMarkedText: false
        ), "第三方键盘布局按普通键盘处理")
    }

    @MainActor
    private static func testRetryFlow() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = PlayerState()
        let bankURL = tempURL("retry-bank")
        let bank = QuestionBank(url: bankURL)
        let mistakes = MistakeBook(url: tempURL("retry-mistakes"))
        bank.add(
            text: "I kept the lanterns burning low", translation: "我让灯笼低低地燃着",
            title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12
        )
        bank.add(
            text: "The river carried names we never said", translation: "河水带走了我们从未说出口的名字",
            title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 17.2
        )

        let engine = PracticeEngine(
            state: state, watcher: SpyMusicController(), settings: settings,
            bank: bank, mistakes: mistakes
        )
        state.debugInject(
            track: Track(title: "Paper Lanterns", artist: "The Quiet Harbor", album: "", duration: 242),
            position: 12, playing: false, lines: [], translations: [:]
        )
        engine.setEnabled(true)
        engine.begin(source: .bank, ratio: 1.0)

        let first = engine.current?.text ?? ""
        fillAllBlanks(engine)
        engine.submit()
        let scored = engine.score
        let correctCount = engine.stats.correct
        check(!first.isEmpty && scored > 0 && correctCount == 1, "正常答对计分: \(scored) 分（期望 > 0）")

        engine.next()
        engine.input = "totallywrong"
        engine.submit()
        engine.giveUp()
        check(engine.phase == .revealed, "看答案后停在揭示态")

        engine.retryAfterReveal()
        check(engine.phase == .asking && engine.isRetry, "「再试试」回到答题态并标记重试")
        fillAllBlanks(engine)
        engine.submit()
        check(engine.score == scored && engine.stats.correct == correctCount,
              "重试答对不重复计分（仍是 \(engine.score) 分）")
        check(engine.phase == .revealed, "重试答对后再次揭示")

        engine.setEnabled(false)
        try? FileManager.default.removeItem(at: bankURL)
    }

    // MARK: 收藏歌词

    @MainActor
    private static func testQuestionBank() {
        let url = tempURL("bank")
        let bank = QuestionBank(url: url)

        let first = bank.add(
            text: "I kept the lanterns burning low", translation: "我让灯笼低低地燃着",
            title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12
        )
        let duplicate = bank.add(
            text: "i  kept the lanterns burning low", translation: nil,
            title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12
        )
        let otherSong = bank.add(
            text: "I kept the lanterns burning low", translation: nil,
            title: "Cover", artist: "Someone", lineTime: 1
        )

        check(first && !duplicate && otherSong && bank.count == 2,
              "收藏去重: 两次同句 + 一首翻唱 → \(bank.count) 条（期望 2）")
        check(QuestionBank(url: url).count == 2, "收藏落盘: 重新加载 \(QuestionBank(url: url).count) 条")

        let stillThere = bank.toggle(
            text: "I kept the lanterns burning low", translation: nil,
            title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12
        )
        check(stillThere == .removed && bank.count == 1, "收藏再点一次移除")
        check(QuestionBank(url: url).count == 1, "移除也落盘")

        bank.clear()
        check(bank.isEmpty && QuestionBank(url: url).isEmpty, "清空收藏")
        try? FileManager.default.removeItem(at: url)
    }

    /// 旧版 questions.json 没有新字段也要能读，ID/原文保持不变
    @MainActor
    private static func testFavoritesCompatibility() {
        let url = tempURL("legacy-bank")
        let id = UUID()
        let legacy: [[String: Any]] = [[
            "id": id.uuidString,
            "text": "I kept the lanterns burning low",
            "translation": "我让灯笼低低地燃着",
            "title": "Paper Lanterns",
            "artist": "The Quiet Harbor",
            "lineTime": 12.0,
            "addedAt": "2026-10-26T00:00:00Z"
        ]]
        do {
            let data = try JSONSerialization.data(withJSONObject: legacy)
            try data.write(to: url)
        } catch {
            check(false, "写入旧版收藏 JSON: \(error)")
            return
        }

        let bank = QuestionBank(url: url)
        let item = bank.items.first
        check(bank.count == 1, "旧收藏可加载: \(bank.count) 条")
        check(item?.id == id && item?.text == "I kept the lanterns burning low" && item?.translation == "我让灯笼低低地燃着",
              "旧收藏 ID/原文/译文保留")
        check(item?.title == "Paper Lanterns" && item?.artist == "The Quiet Harbor" && item?.lineTime == 12,
              "旧收藏 歌名/歌手/时间 保留")

        _ = bank.add(
            text: "The river carried names we never said", translation: nil,
            title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 17.2
        )
        check(QuestionBank(url: url).count == 2, "旧文件追加新收藏后仍可读")

        let removed = bank.toggle(
            text: "I kept the lanterns burning low", translation: nil,
            title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12
        )
        check(removed == .removed && QuestionBank(url: url).count == 1, "旧收藏可正常取消")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: 错题本

    @MainActor
    private static func testMistakeBook() {
        let url = tempURL("mistakes")
        let book = MistakeBook(url: url)
        let q1 = makeQuestion("I kept the lanterns burning low")
        let q2 = makeQuestion("I kept the lanterns burning low", artist: "Cover")
        let a1 = MistakeAttempt(
            source: "bank", ratio: 1, rawInput: "zz", translation: "我让灯笼低低地燃着",
            wasRetry: false,
            blanks: [
                MistakeBlank(ordinal: 0, wordIndex: 0, expected: "I", actual: "z", skipped: false),
                MistakeBlank(ordinal: 1, wordIndex: 1, expected: "kept", actual: "z", skipped: false)
            ]
        )
        let a2 = MistakeAttempt(
            source: "mistakes", ratio: 0.6, rawInput: "qq", translation: "我让灯笼低低地燃着",
            wasRetry: true,
            blanks: [MistakeBlank(ordinal: 0, wordIndex: 0, expected: "I", actual: "q", skipped: false)]
        )
        let a3 = MistakeAttempt(
            source: "bank", ratio: 1, rawInput: "x", translation: nil,
            wasRetry: false,
            blanks: [MistakeBlank(ordinal: 0, wordIndex: 0, expected: "I", actual: "x", skipped: false)]
        )

        check(book.record(question: q1, translation: "我让灯笼低低地燃着", attempt: a1), "错题首次落盘")
        check(book.record(question: q1, translation: "我让灯笼低低地燃着", attempt: a2), "同句第二次错误追加历史")
        check(book.record(question: q2, translation: nil, attempt: a3), "同句不同歌手独立成条")

        check(book.count == 2, "错题条目数: \(book.count)（同句合并、不同歌手分开）")
        check(book.entry(for: q1)?.attempts.count == 2, "同句保留 2 次历史")
        check(book.entry(for: q2)?.attempts.count == 1, "翻唱独立 1 次历史")
        check(book.entry(for: q1)?.attempts.first?.rawInput == "zz"
              && book.entry(for: q1)?.attempts.last?.rawInput == "qq", "历史按提交顺序保留原始输入")
        check(book.entry(for: q1)?.attempts.last?.wasRetry == true, "看答案后的重试错误也保留标记")
        check(book.entry(for: q1)?.attempts.last?.ratio == 0.6, "每次错误保留各自挖空比例")

        let four = MistakeBlank(ordinal: 0, wordIndex: 0, expected: "4", actual: "four", skipped: false)
        let typo = MistakeBlank(ordinal: 0, wordIndex: 0, expected: "low", actual: "law", skipped: false)
        check(!four.isWrong, "4 / four 与整体判分同口径，不算错")
        check(typo.isWrong && book.entry(for: q1)?.attempts.first?.wrongBlankCount == 2,
              "逐空错位统计正确")

        let reloaded = MistakeBook(url: url)
        check(reloaded.count == 2 && reloaded.entry(for: q1)?.attempts.count == 2,
              "错题落盘: 重新加载 \(reloaded.count) 条 / \(reloaded.totalAttempts) 次")

        if let id = book.entry(for: q2)?.id {
            check(book.remove(id: id), "删除单条错题落盘")
        } else {
            check(false, "找到待删除的错题")
        }
        check(MistakeBook(url: url).count == 1, "单条删除后重新加载")

        check(book.clear(), "清空错题本（临时文件）")
        check(MistakeBook(url: url).isEmpty, "清空后重新加载为空")
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    private static func testMistakeRecording() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = PlayerState()
        let bankURL = tempURL("record-bank")
        let bookURL = tempURL("record-mistakes")
        let bank = QuestionBank(url: bankURL)
        let book = MistakeBook(url: bookURL)
        let spy = SpyMusicController()
        bank.add(
            text: "I kept the lanterns burning low", translation: "我让灯笼低低地燃着",
            title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12
        )

        let engine = PracticeEngine(
            state: state, watcher: spy, settings: settings, bank: bank, mistakes: book
        )
        engine.begin(source: .bank, ratio: 1.0)

        // 空提交不记
        engine.input = ""
        engine.submit()
        check(book.isEmpty, "空提交不记错题")

        // 只看答案不记
        engine.giveUp()
        check(book.isEmpty, "只看答案不记错题")

        // 只跳过、不提交不记；skip 会进入下一题/结束
        engine.begin(source: .bank, ratio: 1.0)
        engine.skip()
        check(book.isEmpty, "跳过不记错题")

        // 只输入、不提交（逐字红色提示）不记
        engine.begin(source: .bank, ratio: 1.0)
        engine.input = "zz"
        check(book.isEmpty, "只输入未提交不记错题")
        engine.submit()
        let entry = book.entry(for: engine.current)
        let attempt = entry?.attempts.last
        check(book.count == 1 && entry?.attempts.count == 1, "提交判错后记录 1 条 / 1 次")
        check(attempt?.source == "bank" && attempt?.ratio == 1.0,
              "记录题目来源与挖空比例")
        check(attempt?.translation == "我让灯笼低低地燃着", "记录当时译文")
        check(attempt?.blanks.count == 6, "逐空快照覆盖全部 6 个空")
        check(attempt?.blanks[0].expected == "I" && attempt?.blanks[0].actual == "z"
              && attempt?.blanks[0].wordIndex == 0 && attempt?.blanks[0].ordinal == 0,
              "第 1 空: 期望 I / 实际 z / 原句词下标 0")
        check(attempt?.blanks[1].expected == "kept" && attempt?.blanks[1].actual == "z"
              && attempt?.blanks[1].wordIndex == 1,
              "第 2 空: 期望 kept / 实际 z / 原句词下标 1")
        check(attempt?.blanks[2].skipped == true && attempt?.blanks[2].actual == "",
              "跳过的空保留位置并标记 skipped")
        check(attempt?.wrongBlankCount == 2 && attempt?.skippedBlankCount == 4,
              "错空 2 / 跳过 4，部分跳空仍能对齐")
        check(attempt?.rawInput == "zz" && attempt?.wasRetry == false, "保留原始输入与重试标记")

        // 再次提交另一个错误 → 同句追加
        engine.input = "qq"
        engine.submit()
        check(book.entry(for: engine.current)?.attempts.count == 2, "再次答错追加第 2 次历史")

        // 正确答案不记错
        fillAllBlanks(engine)
        engine.submit()
        check(book.entry(for: engine.current)?.attempts.count == 2, "最终答对不追加错题历史")
        check(engine.verdict?.isCorrect == true, "正确答案判对")

        // 看答案后再试，真正判错仍然记录（但整体不计分）
        engine.retryAfterReveal()
        engine.input = "ww"
        engine.submit()
        check(book.entry(for: engine.current)?.attempts.count == 3, "看答案后重试答错仍记录")
        check(book.entry(for: engine.current)?.attempts.last?.wasRetry == true, "该次历史标记为重试")
        check(!spy.didControl, "收藏练习不下发任何真实播放命令")

        engine.setEnabled(false)
        try? FileManager.default.removeItem(at: bankURL)
        try? FileManager.default.removeItem(at: bookURL)
    }

    @MainActor
    private static func testMistakePracticeOffline() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = PlayerState()
        let bookURL = tempURL("practice-mistakes")
        let book = MistakeBook(url: bookURL)
        let q1 = makeQuestion("I kept the lanterns burning low")
        let q2 = makeQuestion("The river carried names we never said", lineTime: 17.2)
        let attempt = MistakeAttempt(
            source: "bank", ratio: 0.6, rawInput: "zz", translation: "我让灯笼低低地燃着",
            wasRetry: false,
            blanks: [MistakeBlank(ordinal: 0, wordIndex: 0, expected: "I", actual: "z", skipped: false)]
        )
        _ = book.record(question: q1, translation: "我让灯笼低低地燃着", attempt: attempt)
        _ = book.record(question: q2, translation: "河水带走了我们从未说出口的名字", attempt: attempt)

        let spy = SpyMusicController()
        let bank = QuestionBank(url: tempURL("practice-empty-bank"))
        let engine = PracticeEngine(
            state: state, watcher: spy, settings: settings, bank: bank, mistakes: book
        )

        engine.begin(source: .mistakes, ratio: 0.6)
        check(engine.source == .mistakes, "错题本来源生效")
        check(engine.phase == .asking, "错题本离线直接进入答题")
        check(engine.current != nil && engine.mistakeAttemptCount(for: engine.current) >= 1,
              "错题练习显示该句错误次数")
        check(!engine.blankIndices.isEmpty, "错题练习按强度挖空")
        check(engine.isSongMode == false, "错题练习不是歌曲模式（无音频）")
        check(!spy.didControl, "错题练习不下发任何真实播放命令")

        let single = book.recentEntries[0]
        engine.begin(source: .mistakes, ratio: 1.0, onlyID: single.id)
        check(engine.current?.text == single.text, "从错题列表单独练某一句")
        let beforeRestart = engine.current?.text
        engine.restartSession()
        check(engine.current?.text == beforeRestart, "单句错题「再来一遍」仍是同一句")

        let emptyBook = MistakeBook(url: tempURL("practice-empty-book"))
        let emptyBank = QuestionBank(url: tempURL("practice-empty-bank-2"))
        let emptySpy = SpyMusicController()
        let emptyEngine = PracticeEngine(
            state: PlayerState(), watcher: emptySpy, settings: settings,
            bank: emptyBank, mistakes: emptyBook
        )
        emptyEngine.begin(source: .mistakes, ratio: 1.0)
        check(emptyEngine.phase == .idle, "空错题本进入空闲态")
        check(emptyEngine.notice?.contains("错题本") == true, "空错题本给出解释")
        check(!emptySpy.didControl, "空错题本不下发播放命令")

        engine.setEnabled(false)
        try? FileManager.default.removeItem(at: bookURL)
    }

    /// 切换来源必须取消旧会话的自动下一题，不能让旧任务改掉新题
    @MainActor
    private static func testSourceSwitchCancelsAutoAdvance() async {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = PlayerState()
        let bankURL = tempURL("switch-bank")
        let bookURL = tempURL("switch-mistakes")
        let bank = QuestionBank(url: bankURL)
        let book = MistakeBook(url: bookURL)
        bank.add(text: "I kept the lanterns burning low", translation: "我让灯笼低低地燃着",
                 title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12)
        bank.add(text: "The river carried names we never said", translation: "河水带走了我们从未说出口的名字",
                 title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 17.2)
        let attempt = MistakeAttempt(
            source: "bank", ratio: 0.6, rawInput: "zz", translation: "我让灯笼低低地燃着",
            wasRetry: false,
            blanks: [MistakeBlank(ordinal: 0, wordIndex: 0, expected: "I", actual: "z", skipped: false)]
        )
        _ = book.record(question: makeQuestion("I kept the lanterns burning low"),
                        translation: "我让灯笼低低地燃着", attempt: attempt)
        _ = book.record(question: makeQuestion("The river carried names we never said"),
                        translation: "河水带走了我们从未说出口的名字", attempt: attempt)

        let spy = SpyMusicController()
        let engine = PracticeEngine(
            state: state, watcher: spy, settings: settings, bank: bank, mistakes: book
        )
        engine.begin(source: .bank, ratio: 1.0)
        fillAllBlanks(engine)
        engine.submit()
        check(engine.phase == .revealed, "收藏答对后进入揭示态并排队自动下一题")

        engine.begin(source: .mistakes, ratio: 1.0)
        let switchedText = engine.current?.text
        try? await Task.sleep(nanoseconds: 2_300_000_000)

        check(engine.source == .mistakes && engine.phase == .asking, "切换到错题本后仍在答题")
        check(engine.current?.text == switchedText, "旧会话的自动下一题被取消，新题未被推进")
        check(!spy.didControl, "收藏/错题切换全程不下发真实播放命令")

        engine.setEnabled(false)
        try? FileManager.default.removeItem(at: bankURL)
        try? FileManager.default.removeItem(at: bookURL)
    }

    /// 关键：.song 来源切换通过替身验证，绝不碰真实 Music
    @MainActor
    private static func testSourceSwitchFromSong() async {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = PlayerState()
        let raw = """
        [00:10.00]I kept the lanterns burning low
        [00:15.00]The river carried names we never said
        """
        let parsed = LRCParser.parse(raw)
        state.debugInject(
            track: Track(title: "Paper Lanterns", artist: "The Quiet Harbor", album: "", duration: 30),
            position: 12,
            playing: false,
            lines: parsed.lines,
            translations: [:]
        )

        let bankURL = tempURL("song-switch-bank")
        let bank = QuestionBank(url: bankURL)
        bank.add(text: "I kept the lanterns burning low", translation: "我让灯笼低低地燃着",
                 title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 10)
        let spy = SpyMusicController()
        let book = MistakeBook(url: tempURL("song-switch-mistakes"))
        let engine = PracticeEngine(
            state: state, watcher: spy, settings: settings, bank: bank, mistakes: book
        )

        engine.begin(source: .song, ratio: 1.0)
        check(engine.source == .song, "歌曲来源启动")
        check(spy.didControl, "歌曲模式通过替身发送播放命令（真实 Music 未被触碰）")

        engine.begin(source: .bank, ratio: 1.0)
        let after = engine.current?.text
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        check(engine.source == .bank && engine.phase == .asking, "歌曲 → 收藏切换后停在收藏答题")
        check(engine.current?.text == after, "歌曲计时/自动任务未干扰新来源")

        engine.setEnabled(false)
        try? FileManager.default.removeItem(at: bankURL)
    }

    // MARK: 坏文件保护

    @MainActor
    private static func testCorruptMistakeFile() {
        let url = tempURL("corrupt-mistakes")
        let bad = "not json"
        do {
            try Data(bad.utf8).write(to: url)
        } catch {
            check(false, "写入损坏错题文件: \(error)")
            return
        }

        let book = MistakeBook(url: url)
        check(book.loadError != nil, "损坏错题本读取失败对用户可见")
        guard let backup = book.backupURL else {
            check(false, "损坏文件已备份")
            return
        }
        check(FileManager.default.fileExists(atPath: backup.path), "损坏文件备份存在")
        check((try? String(contentsOf: backup, encoding: .utf8)) == bad, "备份保留原始内容")

        let q = makeQuestion("I kept the lanterns burning low")
        let attempt = MistakeAttempt(
            source: "bank", ratio: 1, rawInput: "zz", translation: "我让灯笼低低地燃着",
            wasRetry: false,
            blanks: [MistakeBlank(ordinal: 0, wordIndex: 0, expected: "I", actual: "z", skipped: false)]
        )
        check(book.record(question: q, translation: "我让灯笼低低地燃着", attempt: attempt),
              "备份后新错误可以写入新文件")
        check(FileManager.default.fileExists(atPath: backup.path), "写入新文件后备份仍在")
        check((try? String(contentsOf: backup, encoding: .utf8)) == bad, "备份内容未被覆盖")
        let reloaded = MistakeBook(url: url)
        check(reloaded.count == 1 && reloaded.loadError == nil, "新错题文件可正常重新加载")

        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: backup)
    }

    /// 写入失败不能静默：record 返回 false，saveError 可见，内存里仍有本次记录但不假装落盘
    @MainActor
    private static func testMistakeSaveFailure() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gapsong-selftest-readonly-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        } catch {
            check(false, "准备只读目录: \(error)")
            return
        }
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }

        let book = MistakeBook(url: dir.appendingPathComponent("mistakes.json"))
        let q = makeQuestion("I kept the lanterns burning low")
        let attempt = MistakeAttempt(
            source: "bank", ratio: 1, rawInput: "z", translation: "我让灯笼低低地燃着",
            wasRetry: false,
            blanks: [MistakeBlank(ordinal: 0, wordIndex: 0, expected: "I", actual: "z", skipped: false)]
        )
        let saved = book.record(question: q, translation: "我让灯笼低低地燃着", attempt: attempt)
        check(!saved, "写入失败时 record 返回 false（不假装成功）")
        check(book.saveError != nil, "写入失败对用户可见: \(book.saveError ?? "nil")")
        check(book.entries.count == 1, "写入失败时内存中仍保留本次记录供 UI 提示")
    }

    // MARK: 设置模型（F6 / F7 / 窗口下限）

    @MainActor
    private static func testSettingsModel() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        check(abs(settings.practiceTail - 0.2) < 0.001, "句末停顿默认 +0.2s（当前 \(settings.practiceTailLabel)）")
        check(Settings.practiceTailChoices.contains(0.2) && Settings.practiceTailChoices.contains(-0.1),
              "句末停菜单沿用同一组选项 \(Settings.practiceTailChoices)")
        check(Settings.practiceTailLabel(0.2) == "延后 0.2s"
              && Settings.practiceTailLabel(-0.1) == "提前 0.1s"
              && Settings.practiceTailLabel(0) == "准时停",
              "句末停文案可读: \(Settings.practiceTailLabel(0.2)) / \(Settings.practiceTailLabel(-0.1)) / \(Settings.practiceTailLabel(0))")

        settings.practiceTail = 0.5
        check(abs(settings.practiceTail - 0.5) < 0.001, "菜单选句末停后写入偏好")
        settings.practiceTail = 9
        check(abs(settings.practiceTail - 1.5) < 0.001, "句末停越界被钳到 1.5s")

        check(OverlayController.minSize(practice: false).height == 110, "歌词态最小高度仍是 110")
        let practiceMin = OverlayController.minSize(practice: true)
        check(practiceMin.width >= 480 && practiceMin.height >= 380,
              "练习态最小尺寸 \(Int(practiceMin.width))×\(Int(practiceMin.height))，足够放下设置/答题/揭示/结束")

        // 菜单字号要真的进练习版式：14…72 全区间单调，不在中间提前 clamp；
        // 默认 24 的系数必须是 1，保证现有排版不变。真实字形变化由快照渲染量高验证。
        let fontSizes: [Double] = [14, 24, 38, 72]
        let factors = fontSizes.map { Settings.practiceFontFactor($0) }
        check(zip(factors, factors.dropFirst()).allSatisfy { $1 > $0 },
              "练习字号系数随 14/24/38/72 递增: \(factors.map { String(format: "%.2f", $0) }.joined(separator: " / "))")
        check(abs(Settings.practiceFontFactor(24) - 1) < 0.0001,
              "默认字号 24 的练习排版系数为 1（现有排版不变）")
        let wholeRange = (14...72).map { Settings.practiceFontFactor(Double($0)) }
        check(zip(wholeRange, wholeRange.dropFirst()).allSatisfy { $1 > $0 },
              "练习字号 14…72 全程可调，没有中途 clamp")
        check(abs(Settings.practiceFontFactor(14) - 14.0 / 24) < 0.0001
              && abs(Settings.practiceFontFactor(72) - 3) < 0.0001,
              "练习字号沿用菜单的 14–72 量程: \(String(format: "%.2f", Settings.practiceFontFactor(14)))…\(String(format: "%.2f", Settings.practiceFontFactor(72)))")
    }

    // MARK: 小窗口限制与退出恢复（F4）

    @MainActor
    private static func testSmallWindowLimitsAndRestore() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.practiceMode = false
        settings.setSize(width: 900, height: 320)
        let lyric = settings.rememberedLyricSize
        check(abs(lyric.width - 900) < 0.5 && abs(lyric.height - 320) < 0.5,
              "歌词态尺寸被记住: \(Int(lyric.width))×\(Int(lyric.height))")

        settings.practiceMode = true
        let practiceMin = OverlayController.minSize(practice: true)
        settings.setSize(width: max(practiceMin.width, 720), height: max(practiceMin.height, 400))
        check(settings.panelHeight >= practiceMin.height, "进入练习后窗口高度不低于 \(Int(practiceMin.height))")

        settings.practiceMode = false
        let restored = settings.rememberedLyricSize
        settings.setSize(width: restored.width, height: restored.height)
        check(abs(settings.panelWidth - 900) < 0.5 && abs(settings.panelHeight - 320) < 0.5,
              "退出练习恢复原尺寸 \(Int(settings.panelWidth))×\(Int(settings.panelHeight))")
        check(OverlayController.minSize(practice: false).height == 110, "退出练习后限制回到歌词态 110")

        // 启动时 practiceMode 已经是 true：进入练习前先快照，退出仍回默认紧凑尺寸
        let (boot, bootDefaults, bootSuite) = makeSettings()
        defer { bootDefaults.removePersistentDomain(forName: bootSuite) }
        boot.practiceMode = true
        boot.captureLyricSizeIfNeeded()          // AppDelegate 进入练习时会做的事
        boot.setSize(width: 720, height: 400)    // 练习放大窗口
        let bootRestored = boot.rememberedLyricSize
        check(abs(bootRestored.width - 836) < 0.5 && abs(bootRestored.height - 155) < 0.5,
              "启动即练习时，退出练习仍回到默认紧凑尺寸 \(Int(bootRestored.width))×\(Int(bootRestored.height))")

        // 老版本用户只有 panelWidth/panelHeight：升级后不能被新默认值顶掉
        let legacySuite = "gapsong-selftest-legacy-size-\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuite)!
        defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }
        legacyDefaults.set(967.0, forKey: "panelWidth")
        legacyDefaults.set(217.0, forKey: "panelHeight")
        legacyDefaults.set(false, forKey: "practiceMode")
        let upgraded = Settings(defaults: legacyDefaults)
        let upgradedSize = upgraded.rememberedLyricSize
        check(abs(upgradedSize.width - 967) < 0.5 && abs(upgradedSize.height - 217) < 0.5,
              "升级时已有自定义歌词窗尺寸不会被新默认值替换: \(Int(upgradedSize.width))×\(Int(upgradedSize.height))")
    }

    // MARK: 收藏持久化保护（F3）

    @MainActor
    private static func testBankCorruptFileProtection() {
        let fm = FileManager.default
        let dir = tempDir("bank-corrupt")
        let url = dir.appendingPathComponent("questions.json")
        let original = Data([0xFF, 0x00, 0x7B, 0x62, 0x61, 0x64, 0x7D])
        do {
            try original.write(to: url)
        } catch {
            check(false, "写入损坏收藏: \(error)")
            return
        }

        let bank = QuestionBank(url: url)
        check(bank.loadError != nil, "损坏收藏读取失败对用户可见")
        check(bank.count == 0, "损坏文件不会被当成空收藏后直接覆盖")
        guard let backup = bank.backupURL else {
            check(false, "损坏收藏已备份")
            return
        }
        let backedUp = (try? Data(contentsOf: backup)) == original
        check(backedUp, "坏文件在重建前已逐字节备份")

        let added = bank.add(
            text: "I kept the lanterns burning low", translation: "我让灯笼低低地燃着",
            title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12
        )
        check(added && bank.count == 1, "备份成功后可以重建新收藏文件")
        check((try? Data(contentsOf: backup)) == original, "重建新文件后备份未被覆盖")
        let reloaded = QuestionBank(url: url)
        check(reloaded.count == 1 && reloaded.loadError == nil, "新收藏文件仍是可加载的裸数组")

        // 合法 JSON 但缺少核心字段：不能伪造随机 ID / 空白原文
        let schemaDir = tempDir("bank-schema")
        let schemaURL = schemaDir.appendingPathComponent("questions.json")
        let schemaBytes = Data(#"[{"unexpected_payload":"ORIGINAL MUST REMAIN RECOVERABLE"}]"#.utf8)
        try? schemaBytes.write(to: schemaURL)
        let schemaBank = QuestionBank(url: schemaURL)
        check(schemaBank.isEmpty, "缺少 id/text 的记录不会被当成有效收藏")
        check(schemaBank.loadError != nil, "缺少核心字段按损坏文件处理")
        _ = schemaBank.add(
            text: "Do not invent identities", translation: nil,
            title: "Fixture", artist: "Test Only", lineTime: 1
        )
        let schemaFiles = (try? fm.contentsOfDirectory(at: schemaDir, includingPropertiesForKeys: nil)) ?? []
        let schemaPreserved = schemaFiles.contains {
            $0.lastPathComponent.hasPrefix("questions.corrupt-")
                && (try? Data(contentsOf: $0)) == schemaBytes
        } || (try? Data(contentsOf: schemaURL)) == schemaBytes
        check(schemaPreserved, "合法 JSON 但缺核心字段时原始字节仍可恢复")
        check(schemaBank.items.allSatisfy { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.id != UUID() },
              "损坏记录不会被伪造成空白原文 + 随机身份")

        try? fm.removeItem(at: dir)
        try? fm.removeItem(at: schemaDir)
    }

    @MainActor
    private static func testBankBackupFailureIsReadOnly() {
        let fm = FileManager.default
        let dir = tempDir("bank-blocked")
        let url = dir.appendingPathComponent("questions.json")
        let original = Data([0xFF, 0x00, 0x7B, 0x62, 0x61, 0x64, 0x7D])
        do {
            try original.write(to: url)
            try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        } catch {
            check(false, "准备只读目录: \(error)")
            return
        }
        defer {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try? fm.removeItem(at: dir)
        }

        let bank = QuestionBank(url: url)
        check(bank.loadError != nil, "无法备份时读取失败对用户可见")
        check(bank.backupURL == nil, "无法备份时不谎称已备份")
        let added = bank.add(
            text: "Leave the original bytes alone", translation: nil,
            title: "Fixture", artist: "Test Only", lineTime: 1
        )
        check(!added && bank.isEmpty, "无法备份时拒绝重建并返回失败")
        check(bank.saveError != nil || bank.loadError != nil, "只读保护提示可见")
        check((try? Data(contentsOf: url)) == original, "原始坏文件字节未被改写")
    }

    @MainActor
    private static func testBankDirectoryPathProtection() {
        let fm = FileManager.default
        let dir = tempDir("bank-directory")
        let url = dir.appendingPathComponent("questions.json", isDirectory: true)
        let sentinel = url.appendingPathComponent("preserve.bin")
        let original = Data([0x70, 0x72, 0x65, 0x73, 0x65, 0x72, 0x76, 0x65])
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try original.write(to: sentinel)
        } catch {
            check(false, "准备目录占位: \(error)")
            return
        }
        defer { try? fm.removeItem(at: dir) }

        let bank = QuestionBank(url: url)
        check(bank.loadError != nil, "收藏路径是目录时不假装是空库")
        let added = bank.add(
            text: "A directory is not an empty library", translation: nil,
            title: "Fixture", artist: "Test Only", lineTime: 1
        )
        check(!added, "目录路径写不进去时报失败")
        check((try? Data(contentsOf: sentinel)) == original, "目录里的内容未被破坏")
    }

    @MainActor
    private static func testBankSaveFailure() {
        let fm = FileManager.default
        let dir = tempDir("bank-readonly")
        do {
            try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        } catch {
            check(false, "准备只读目录: \(error)")
            return
        }
        defer {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try? fm.removeItem(at: dir)
        }

        let bank = QuestionBank(url: dir.appendingPathComponent("questions.json"))
        check(bank.loadError == nil, "文件不存在不算读取失败")
        let added = bank.add(
            text: "Writing must really reach the disk", translation: nil,
            title: "Fixture", artist: "Test Only", lineTime: 1
        )
        check(!added && bank.count == 0, "写失败时返回 false 并回滚，不显示成已收藏")
        check(bank.saveError != nil, "写失败提示可见: \(bank.saveError ?? "nil")")
        check(bank.storageWarning != nil, "管理/歌词/练习界面拿到统一的 storageWarning")
    }

    @MainActor
    private static func testLegacyBankPartialFields() {
        let fm = FileManager.default
        let dir = tempDir("bank-legacy")

        // 缺 artist/lineTime/addedAt：安全兼容，ID/原文保留
        let id = UUID()
        let partialURL = dir.appendingPathComponent("partial.json")
        let partial: [[String: Any]] = [[
            "id": id.uuidString,
            "text": "I kept the lanterns burning low",
            "title": "Paper Lanterns"
        ]]
        do {
            try JSONSerialization.data(withJSONObject: partial).write(to: partialURL)
        } catch {
            check(false, "写入缺字段旧收藏: \(error)")
            return
        }
        let bank = QuestionBank(url: partialURL)
        check(bank.count == 1 && bank.items.first?.id == id
              && bank.items.first?.text == "I kept the lanterns burning low",
              "缺展示字段的旧收藏仍可加载，ID/原文不变")
        check(bank.items.first?.artist == "" && bank.items.first?.lineTime == 0,
              "缺失字段用安全默认值补齐")

        // 缺 id：整份按损坏文件保护，不生成随机身份
        let noID = dir.appendingPathComponent("no-id.json")
        let noIDBytes = Data(#"[{"text":"I kept the lanterns burning low"}]"#.utf8)
        try? noIDBytes.write(to: noID)
        let noIDBank = QuestionBank(url: noID)
        check(noIDBank.isEmpty && noIDBank.loadError != nil, "缺少 id 的记录不会被伪造身份")
        check(noIDBank.backupURL.flatMap { try? Data(contentsOf: $0) } == noIDBytes,
              "缺少 id 时原始字节已备份")

        // 空白原文：同样按损坏文件保护
        let blank = dir.appendingPathComponent("blank-text.json")
        let blankBytes = Data(#"[{"id":"\#(UUID().uuidString)","text":"   "}]"#.utf8)
        try? blankBytes.write(to: blank)
        let blankBank = QuestionBank(url: blank)
        check(blankBank.isEmpty && blankBank.loadError != nil, "空白原文不会被当成有效收藏")

        try? fm.removeItem(at: dir)
    }

    // MARK: 删除确认（F9）

    @MainActor
    private static func testLibraryDeleteConfirmation() {
        let fm = FileManager.default
        let bankURL = tempURL("delete-bank")
        let bookURL = tempURL("delete-mistakes")
        let bank = QuestionBank(url: bankURL)
        bank.add(text: "I kept the lanterns burning low", translation: nil,
                 title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12)
        bank.add(text: "The river carried names we never said", translation: nil,
                 title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 17.2)
        guard let target = bank.items.last?.id else {
            check(false, "准备待删除收藏")
            return
        }
        let bankBytes = try? Data(contentsOf: bankURL)

        let book = MistakeBook(url: bookURL)
        let q = makeQuestion("I kept the lanterns burning low")
        for suffix in ["zz", "qq"] {
            let attempt = MistakeAttempt(
                source: "bank", ratio: 1, rawInput: suffix, translation: nil,
                wasRetry: false,
                blanks: [MistakeBlank(ordinal: 0, wordIndex: 0, expected: "I", actual: suffix, skipped: false)]
            )
            _ = book.record(question: q, translation: nil, attempt: attempt)
        }
        guard let mistakeID = book.entries.first?.id else {
            check(false, "准备待删除错题")
            return
        }
        let bookBytes = try? Data(contentsOf: bookURL)

        let model = LibraryModel(tab: .favorites)
        model.confirmDelete = { _, _ in false }
        model.askDelete(.favorite(target))
        let cancelled = model.confirmPendingDelete(favorites: bank, mistakes: book)
        check(!cancelled && bank.count == 2 && (try? Data(contentsOf: bankURL)) == bankBytes,
              "取消删除收藏不落盘")

        model.askDelete(.favorite(target))
        model.cancelDelete()
        check(model.pendingDelete == nil && bank.count == 2
              && (try? Data(contentsOf: bankURL)) == bankBytes,
              "关闭确认框不落盘")

        model.askDelete(.mistake(mistakeID))
        _ = model.confirmPendingDelete(favorites: bank, mistakes: book)
        check(book.count == 1 && book.totalAttempts == 2
              && (try? Data(contentsOf: bookURL)) == bookBytes,
              "取消删除错题时历史完整保留")

        model.confirmDelete = { _, _ in true }
        model.askDelete(.favorite(target))
        let confirmed = model.confirmPendingDelete(favorites: bank, mistakes: book)
        check(confirmed && bank.count == 1 && QuestionBank(url: bankURL).count == 1,
              "确认后才真正删除并落盘")

        model.askDelete(.mistake(mistakeID))
        check(model.confirmPendingDelete(favorites: bank, mistakes: book) && book.isEmpty,
              "确认后删除单条错题（含历史）")

        try? fm.removeItem(at: bankURL)
        try? fm.removeItem(at: bookURL)
    }

    // MARK: 字号快捷键（⌘= / ⌘+ / ⌘-）

    /// 用真实 `NSEvent` + 真实窗口接收层验证键位匹配、修饰键放行、每次 2pt 与 14…72 边界。
    /// 原生菜单/窗口的完整按键分发由独立 GUI 验收，这里不启动 AppDelegate、不装全局监听。
    @MainActor
    private static func testFontShortcuts() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let other = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        other.isReleasedWhenClosed = false

        let monitor = FontShortcutMonitor(settings: settings) { $0 === window }
        var stamp: TimeInterval = 0
        func event(
            _ keyCode: UInt16,
            characters: String,
            ignoring: String,
            flags: NSEvent.ModifierFlags,
            window: NSWindow
        ) -> NSEvent {
            stamp += 1
            return NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: stamp, windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: ignoring,
                isARepeat: false, keyCode: keyCode
            )!
        }

        settings.fontSize = 24
        check(monitor.handle(event(24, characters: "=", ignoring: "=", flags: [.command], window: window))
              && settings.fontSize == 26,
              "⌘= 放大 2pt: \(Int(settings.fontSize))")
        check(monitor.handle(event(24, characters: "+", ignoring: "=", flags: [.command, .shift], window: window))
              && settings.fontSize == 28,
              "⌘⇧=（主键盘 ⌘+）放大 2pt: \(Int(settings.fontSize))")
        check(monitor.handle(event(69, characters: "+", ignoring: "+", flags: [.command, .numericPad], window: window))
              && settings.fontSize == 30,
              "数字区 ⌘+ 放大 2pt: \(Int(settings.fontSize))")
        check(monitor.handle(event(27, characters: "-", ignoring: "-", flags: [.command], window: window))
              && settings.fontSize == 28,
              "⌘- 缩小 2pt: \(Int(settings.fontSize))")
        check(monitor.handle(event(78, characters: "-", ignoring: "-", flags: [.command, .numericPad], window: window))
              && settings.fontSize == 26,
              "数字区 ⌘- 缩小 2pt: \(Int(settings.fontSize))")

        let text = settings.fontSize
        check(!monitor.handle(event(24, characters: "=", ignoring: "=", flags: [.control], window: window)),
              "⌃= 不抢")
        check(!monitor.handle(event(24, characters: "=", ignoring: "=", flags: [.option], window: window)),
              "⌥= 不抢")
        check(!monitor.handle(event(24, characters: "=", ignoring: "=", flags: [], window: window))
              && !monitor.handle(event(27, characters: "-", ignoring: "-", flags: [], window: window))
              && !monitor.handle(event(24, characters: "+", ignoring: "=", flags: [.shift], window: window)),
              "普通字符 = / - / + 不触发字号")
        check(!monitor.handle(event(24, characters: "=", ignoring: "=", flags: [.command], window: other)),
              "别的窗口（非 GapSong 目标窗）不触发")
        check(settings.fontSize == text, "被放行的按键不改字号: \(Int(settings.fontSize))")

        // 同一物理事件被菜单与监视器都收到时只生效一次
        let once = event(24, characters: "=", ignoring: "=", flags: [.command], window: window)
        let before = settings.fontSize
        _ = monitor.handle(once)
        _ = monitor.handle(once)
        check(settings.fontSize == before + 2, "同一按键事件不重复执行: \(Int(settings.fontSize))")

        settings.fontSize = 71
        _ = monitor.handle(event(24, characters: "=", ignoring: "=", flags: [.command], window: window))
        _ = monitor.handle(event(24, characters: "=", ignoring: "=", flags: [.command], window: window))
        check(settings.fontSize == 72, "放大到 72 封顶: \(Int(settings.fontSize))")
        settings.fontSize = 15
        _ = monitor.handle(event(27, characters: "-", ignoring: "-", flags: [.command], window: window))
        _ = monitor.handle(event(27, characters: "-", ignoring: "-", flags: [.command], window: window))
        check(settings.fontSize == 14, "缩小到 14 封底: \(Int(settings.fontSize))")

        monitor.uninstall()
    }

    // MARK: 空提交与统计口径（F8）

    @MainActor
    private static func testEmptySubmitCoaching() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let bankURL = tempURL("empty-submit-bank")
        let bookURL = tempURL("empty-submit-mistakes")
        let bank = QuestionBank(url: bankURL)
        let book = MistakeBook(url: bookURL)
        bank.add(text: "I kept the lanterns burning low", translation: nil,
                 title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12)
        let engine = PracticeEngine(
            state: PlayerState(), watcher: SpyMusicController(),
            settings: settings, bank: bank, mistakes: book
        )
        engine.begin(source: .bank, ratio: 1.0)
        engine.input = ""
        engine.submit()
        check(engine.coaching != nil, "空提交给轻提示: \(engine.coaching ?? "nil")")
        check(engine.stats.wrong == 0 && book.isEmpty, "空提交不判错、不记错题")
        check(engine.phase == .asking, "空提交停在答题态")
        engine.input = "a"
        check(engine.coaching == nil, "一开始输入就收掉轻提示")
        engine.setEnabled(false)
        try? FileManager.default.removeItem(at: bankURL)
        try? FileManager.default.removeItem(at: bookURL)
    }

    @MainActor
    private static func testStatsWording() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let bankURL = tempURL("stats-bank")
        let bank = QuestionBank(url: bankURL)
        bank.add(text: "I kept the lanterns burning low", translation: nil,
                 title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12)
        let engine = PracticeEngine(
            state: PlayerState(), watcher: SpyMusicController(),
            settings: settings, bank: bank, mistakes: MistakeBook(url: tempURL("stats-mistakes"))
        )
        engine.begin(source: .bank, ratio: 1.0)
        engine.input = "zz"
        engine.submit()
        engine.input = "qq"
        engine.submit()
        check(engine.stats.wrong == 2 && engine.wrongQuestionCount == 1,
              "同一句错两次：次数 2 / 句数 1")

        fillAllBlanks(engine)
        engine.submit()
        check(engine.stats.correct == 1 && engine.stats.wrong == 2, "答对不改变已发生的错误次数")

        engine.next()
        let notice = engine.notice ?? ""
        check(engine.phase == .idle, "练完回到空闲态")
        check(notice.contains("答错 2 次") && notice.contains("1 句") && notice.contains("答对 1 句"),
              "汇总文案区分「次」与「句」: \(notice)")
        engine.setEnabled(false)
        try? FileManager.default.removeItem(at: bankURL)
    }

    @MainActor
    private static func testRatioChangeKeepsInput() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let bankURL = tempURL("ratio-bank")
        let bank = QuestionBank(url: bankURL)
        bank.add(text: "I kept the lanterns burning low", translation: nil,
                 title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12)
        let engine = PracticeEngine(
            state: PlayerState(), watcher: SpyMusicController(),
            settings: settings, bank: bank, mistakes: MistakeBook(url: tempURL("ratio-mistakes"))
        )
        engine.begin(source: .bank, ratio: 0.5)
        let before = engine.blankIndices.count
        var focusRequests = 0
        engine.onRequestFocus = { focusRequests += 1 }
        engine.changeRatio(0.9)
        check(abs(settings.practiceRatio - 0.9) < 0.001, "改强度写回 settings（设置页不再用陈旧值覆盖）")
        check(engine.ratio == settings.practiceRatio, "引擎与设置页读同一份强度")
        check(engine.blankIndices.count >= before, "当前句按新强度重挖（\(before) → \(engine.blankIndices.count)）")
        check(focusRequests > 0, "切强度后重新请求输入焦点")
        engine.input = "keep"
        check(engine.input == "keep" && engine.phase == .asking, "切强度后可以继续输入")
        engine.setEnabled(false)
        try? FileManager.default.removeItem(at: bankURL)
    }

    /// 暂停归属：只有「确由我们按下、且暂停仍然成立」才允许在退出时恢复播放
    @MainActor
    private static func testPauseOwnership() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = PlayerState()
        let parsed = LRCParser.parse("[00:10.00]I kept the lanterns burning low\n[00:40.00]The river carried names we never said")
        let track = Track(title: "Paper Lanterns", artist: "The Quiet Harbor", album: "", duration: 120)
        state.debugInject(track: track, position: 10, playing: true, lines: parsed.lines, translations: [:])

        let spy = SpyMusicController()
        let bank = QuestionBank(url: tempURL("pause-own-bank"))
        bank.add(text: "I kept the lanterns burning low", translation: nil,
                 title: "Paper Lanterns", artist: "The Quiet Harbor", lineTime: 12)
        let engine = PracticeEngine(
            state: state, watcher: spy, settings: settings, bank: bank,
            mistakes: MistakeBook(url: tempURL("pause-own-mistakes"))
        )
        var now = Date()
        engine.clock = { now }
        func tick(_ seconds: Double) {
            now = now.addingTimeInterval(seconds)
            engine.debugTick()
        }

        engine.begin(source: .song, ratio: 1.0)
        engine.input = "kee"
        check(spy.seeks.count == 1 && spy.seeks[0].play && !spy.commands.contains("play"),
              "开始练习只 seek(play:)，不会额外冒充用户播放")

        // 用户自己在「音乐」里暂停
        state.debugSetPlayback(position: 12, playing: false, sampledAt: now)
        tick(0.5)
        tick(2.0)
        tick(2.0)
        check(engine.playbackIssue == .paused && engine.input == "kee",
              "用户手动暂停被识别且不丢输入")

        let sends = spy.commands.count
        engine.begin(source: .bank, ratio: 1.0)
        check(spy.commands.count == sends,
              "切到收藏练习时不会替用户把暂停中的音乐按播放")
        engine.returnToSetup()
        check(spy.commands.count == sends, "回设置页同样不会擅自恢复播放")
        engine.setEnabled(false)
        check(spy.commands.count == sends, "退出练习同样不会擅自恢复播放")
        check(engine.playbackIssue == nil, "离开后不残留异常提示")

        // 正常语义保留：句末由我们暂停 → 退出时恢复播放
        engine.setEnabled(true)
        now = Date()
        state.debugInject(track: track, position: 10, playing: true, lines: parsed.lines, translations: [:])
        engine.begin(source: .song, ratio: 1.0)
        state.debugSetPlayback(position: 40, playing: true, sampledAt: now.addingTimeInterval(1))
        now = now.addingTimeInterval(1.5)
        engine.debugTick()
        check(engine.phase == .asking && spy.commands.contains("pause"),
              "句末由我们暂停并进入答题（暂停归属在我们手上）")
        let beforeExit = spy.commands.count
        engine.setEnabled(false)
        check(spy.commands.count == beforeExit + 1 && spy.commands.last == "play",
              "句末暂停的正常退出语义保留：把播放还给用户")
    }

    /// 暂时没有采样 ≠ 换歌：不清题、不清输入、不重建「无歌名」新题
    @MainActor
    private static func testMissingSampleKeepsSession() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = PlayerState()
        let parsed = LRCParser.parse("[00:10.00]I kept the lanterns burning low\n[00:40.00]The river carried names we never said")
        let track = Track(title: "Paper Lanterns", artist: "The Quiet Harbor", album: "", duration: 120)
        state.debugInject(track: track, position: 10, playing: true, lines: parsed.lines, translations: [:])

        let spy = SpyMusicController()
        let bank = QuestionBank(url: tempURL("missing-bank"))
        let engine = PracticeEngine(
            state: state, watcher: spy, settings: settings, bank: bank,
            mistakes: MistakeBook(url: tempURL("missing-mistakes"))
        )
        var now = Date()
        engine.clock = { now }
        func tick(_ seconds: Double) {
            now = now.addingTimeInterval(seconds)
            engine.debugTick()
        }

        engine.begin(source: .song, ratio: 1.0)
        engine.input = "kee"
        let title = engine.current?.title ?? ""
        let count = engine.questionCount
        check(title == "Paper Lanterns" && count > 0, "歌曲练习从真实歌名出题")

        // 真实 MusicWatcher deliver(nil) → PlayerState.ingest(nil) 会清 lyrics/generation
        state.ingest(nil)
        tick(0.2)
        check(engine.current?.title == title, "采样消失时不重建成无歌名新题")
        check(engine.questionCount == count, "采样消失时题目数量不变")
        check(engine.input == "kee", "采样消失时保留已输入内容")
        tick(3.0)
        check(engine.playbackIssue == .musicStopped, "采样消失给出可解释状态")
        check(engine.current?.title == title && engine.input == "kee",
              "给出状态提示后原题与输入仍然保留")

        // 同一首歌的采样回来了：答案和题目都还在
        now = Date()
        state.debugInject(track: track, position: 12, playing: true, lines: parsed.lines, translations: [:])
        tick(0.2)
        check(engine.current?.title == title, "同一首歌采样恢复后仍是同一题")
        check(engine.input == "kee", "同一首歌采样恢复后已输入内容还在")

        // 明确换成另一首歌：按来源切换规则重建（清输入）
        let other = Track(title: "Low Tide Letters", artist: "The Quiet Harbor", album: "", duration: 200)
        let otherLines = LRCParser.parse("[00:05.00]Morning found the harbor painted gold")
        now = Date()
        state.debugInject(track: other, position: 5, playing: true, lines: otherLines.lines, translations: [:])
        tick(0.2)
        check(engine.current?.title == "Low Tide Letters", "明确换歌后按新歌重建题库")
        check(engine.input.isEmpty, "换歌按来源切换规则清空输入")
        engine.setEnabled(false)
    }

    /// 首个播放命令一直没被新采样确认：给可恢复超时，不永久停在「正在听」
    @MainActor
    private static func testFirstCommandConfirmationTimeout() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = PlayerState()
        let parsed = LRCParser.parse("[00:10.00]I kept the lanterns burning low\n[00:40.00]The river carried names we never said")
        state.debugInject(
            track: Track(title: "Paper Lanterns", artist: "The Quiet Harbor", album: "", duration: 120),
            position: 10, playing: true, lines: parsed.lines, translations: [:]
        )
        let spy = SpyMusicController()
        let engine = PracticeEngine(
            state: state, watcher: spy, settings: settings,
            bank: QuestionBank(url: tempURL("confirm-bank")),
            mistakes: MistakeBook(url: tempURL("confirm-mistakes"))
        )
        var now = Date()
        engine.clock = { now }

        engine.begin(source: .song, ratio: 1.0)
        engine.input = "kee"
        let sendsBefore = spy.commands.count + spy.seeks.count
        // 旧的播放中采样一直不更新（没有命令后的新采样）
        now = now.addingTimeInterval(7)
        engine.debugTick()
        check(engine.playbackIssue == .stalled,
              "命令长时间没被新采样确认时给出可恢复提示: \(engine.playbackIssue.map(String.init(describing:)) ?? "nil")")
        check(engine.playbackIssue?.suggestsStopping == false, "卡住时仍可显式重试（不自动恢复）")
        check(engine.phase == .listening && engine.input == "kee", "提示期间不结束练习、不清输入")
        check(spy.commands.count + spy.seeks.count == sendsBefore, "给出提示本身不下发任何播放命令")

        // 用户显式重试后仍然只等新采样，不会自动循环
        engine.resumePlayback()
        check(engine.playbackIssue == nil && engine.input == "kee", "显式重试清掉提示并保留输入")
        engine.setEnabled(false)
    }

    /// MusicWatcher 的 typed 问题确实经同一路径转发到练习引擎，恢复后可清除、可再次上报
    @MainActor
    private static func testMusicProblemForwarding() async {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = PlayerState()
        let parsed = LRCParser.parse("[00:10.00]I kept the lanterns burning low")
        state.debugInject(
            track: Track(title: "Paper Lanterns", artist: "The Quiet Harbor", album: "", duration: 120),
            position: 10, playing: true, lines: parsed.lines, translations: [:]
        )

        let watcher = MusicWatcher()
        var hints: [String] = []
        var kinds: [MusicProblem] = []
        var recovered = 0
        watcher.onProblem = { hints.append($0) }
        watcher.onRecovered = { recovered += 1 }

        let bank = QuestionBank(url: tempURL("forward-bank"))
        let engine = PracticeEngine(
            state: state, watcher: watcher, settings: settings, bank: bank,
            mistakes: MistakeBook(url: tempURL("forward-mistakes"))
        )
        // 与 AppDelegate 一致的桥接
        watcher.onProblemKind = { [weak engine] problem in
            kinds.append(problem)
            engine?.reportMusicProblem(problem)
        }
        engine.clock = { Date() }
        engine.begin(source: .song, ratio: 1.0)

        watcher.debugReport(.unauthorized)
        try? await Task.sleep(nanoseconds: 200_000_000)
        check(kinds.count == 1 && kinds.first == .unauthorized,
              "MusicProblem 从 watcher 以 typed 形式上报")
        check(hints.first?.contains("授权") == true, "旧字符串提示仍然给出")
        check(engine.playbackNotice == .unauthorized, "typed 问题确实进了练习界面")

        watcher.debugReportRecovered()
        try? await Task.sleep(nanoseconds: 200_000_000)
        check(recovered == 1, "采样恢复后通知界面清除旧提示")

        watcher.debugReport(.readFailed(-1))
        try? await Task.sleep(nanoseconds: 200_000_000)
        check(kinds.count == 2 && kinds.last == .readFailed(-1),
              "恢复之后再次失败仍会重新上报（不会永久哑掉）")
        check(engine.playbackNotice == .readFailed(-1), "新问题替换旧提示")
        engine.setEnabled(false)
    }

    // MARK: 错题多次历史

    @MainActor
    private static func testMistakeHistorySurvivesReload() {
        let bookURL = tempURL("history-mistakes")
        let book = MistakeBook(url: bookURL)
        let q = makeQuestion("I kept the lanterns burning low")
        for (index, wrong) in ["a", "b", "c"].enumerated() {
            let attempt = MistakeAttempt(
                submittedAt: Date().addingTimeInterval(Double(index)),
                source: "song", ratio: 0.6, rawInput: wrong, translation: nil,
                wasRetry: false,
                blanks: [MistakeBlank(ordinal: 0, wordIndex: 0, expected: "I", actual: wrong, skipped: false)]
            )
            _ = book.record(question: q, translation: nil, attempt: attempt)
        }
        check(book.totalAttempts == 3, "同句累计 3 次错误历史")

        let reloaded = MistakeBook(url: bookURL)
        check(reloaded.count == 1 && reloaded.totalAttempts == 3,
              "重启后 3 次历史完整保留")
        check(reloaded.entries.first?.attempts.map(\.rawInput) == ["a", "b", "c"],
              "历史顺序与原始输入未丢")

        // 裸数组旧格式也要能读
        let bareURL = tempURL("history-bare")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let payload = try? encoder.encode(reloaded.entries) {
            try? payload.write(to: bareURL)
        }
        let bare = MistakeBook(url: bareURL)
        check(bare.count == 1 && bare.totalAttempts == 3, "裸数组旧格式错题本仍可加载")

        try? FileManager.default.removeItem(at: bookURL)
        try? FileManager.default.removeItem(at: bareURL)
    }

    // MARK: 播放异常状态机（F2）

    @MainActor
    private static func testPlaybackIssueStates() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = PlayerState()
        let raw = """
        [00:10.00]I kept the lanterns burning low
        [00:40.00]The river carried names we never said
        """
        let parsed = LRCParser.parse(raw)
        state.debugInject(
            track: Track(title: "Paper Lanterns", artist: "The Quiet Harbor", album: "", duration: 120),
            position: 10, playing: true, lines: parsed.lines, translations: [:]
        )

        let spy = SpyMusicController()
        let bank = QuestionBank(url: tempURL("playback-bank"))
        let book = MistakeBook(url: tempURL("playback-mistakes"))
        let engine = PracticeEngine(
            state: state, watcher: spy, settings: settings, bank: bank, mistakes: book
        )
        // 可注入时钟：不依赖真实等待
        var now = Date()
        engine.clock = { now }
        func tick(_ seconds: Double) {
            now = now.addingTimeInterval(seconds)
            engine.debugTick()
        }

        engine.begin(source: .song, ratio: 1.0)
        check(engine.phase == .listening, "歌曲练习进入收听态")
        check(spy.seeks.count == 1 && spy.seeks[0].play, "开始练习通过替身 seek+play（真实 Music 未触碰）")
        let seeksAfterStart = spy.seeks.count
        let commandsAfterStart = spy.commands.count
        engine.input = "keep"

        // 用户手动暂停：给出原因，不结束、不清输入、不自动恢复
        state.debugSetPlayback(position: 12, playing: false, sampledAt: now)
        tick(0.5)
        tick(2.0)
        tick(2.0)
        check(engine.playbackIssue == .paused, "手动暂停被识别（不再永久「正在听这一句」）")
        check(engine.phase == .listening, "暂停不结束练习")
        check(engine.input == "keep", "暂停保留已输入内容")
        check(spy.seeks.count == seeksAfterStart && spy.commands.count == commandsAfterStart,
              "显示提示时不自动恢复播放（不强行 play）")
        check(engine.playbackNotice?.detail.contains("继续播放") == true, "提示里给出明确的继续动作")

        engine.resumePlayback()
        check(engine.playbackIssue == nil && engine.phase == .listening, "「继续播放」清掉提示并回到收听")
        check(spy.seeks.count == seeksAfterStart + 1 && spy.seeks.last?.play == true,
              "只有用户点按后才下发继续播放命令")
        check(engine.input == "keep", "继续播放后输入仍在")

        // 授权失败：如实说权限问题，不冒充「播放已结束」
        engine.reportMusicProblem(.unauthorized)
        check(engine.playbackIssue == .unauthorized, "授权失败带进练习界面")
        check(engine.playbackIssue?.title.contains("权限") == true
              && engine.playbackIssue?.offersSettings == true,
              "授权失败文案与「打开系统设置」动作正确")
        check(engine.phase == .listening && engine.input == "keep", "授权失败不清输入、不结束")
        engine.resumePlayback()
        check(engine.playbackIssue == nil, "重试清掉授权提示")

        // 采样消失且没到曲尾：可解释、可重试，不判失败
        state.debugClearSnapshot()
        tick(0.5)
        tick(3.0)
        check(engine.playbackIssue == .musicStopped, "采样消失给出可解释原因")
        check(engine.phase == .listening && engine.input == "keep", "采样消失不结束练习、保留输入")

        // 采样长时间不更新（Music 卡住）
        engine.resumePlayback()
        state.debugSetPlayback(position: 12, playing: true, sampledAt: now.addingTimeInterval(1))
        tick(1.5)
        state.debugSetPlayback(position: 12.2, playing: true, sampledAt: now)
        tick(5.0)
        check(engine.playbackIssue == .stalled, "采样停止更新 → 「播放状态停止更新」而不是判错")
        check(engine.phase == .listening, "卡住时仍保留答题现场")

        // 歌播完 / 被切走 / Music 退出在采样层无法区分：绝不冒充「练完了」
        engine.resumePlayback()
        state.debugClearSnapshot()
        tick(0.3)
        tick(3.0)
        check(engine.playbackIssue == .musicStopped, "没有采样时只说「没有在播放」，不冒充正常练完")
        check(engine.playbackIssue?.suggestsStopping == true,
              "给用户「结束练习」的选择，而不是自己判定成绩")
        engine.stopSession()
        check(engine.phase == .idle
              && engine.notice?.contains("提前结束") == true
              && engine.notice?.contains("练完了") != true,
              "提前结束如实汇总，不冒充练完: \(engine.notice ?? "nil")")

        // 普通长句/间奏：位置持续前进，不误判
        state.debugInject(
            track: Track(title: "Paper Lanterns", artist: "The Quiet Harbor", album: "", duration: 120),
            position: 10, playing: true, lines: parsed.lines, translations: [:]
        )
        now = Date()
        engine.begin(source: .song, ratio: 1.0)
        var falseAlarm = false
        for index in 0..<25 {
            state.debugSetPlayback(
                position: 12 + Double(index) * 0.8, playing: true, sampledAt: now.addingTimeInterval(1)
            )
            tick(0.4)
            if engine.playbackIssue != nil {
                falseAlarm = true
                break
            }
        }
        check(!falseAlarm && engine.phase == .listening,
              "普通长句/间奏（位置持续推进）不误判为失败")

        // 切到收藏来源后不残留播放任务或提示
        engine.begin(source: .bank, ratio: 1.0)
        check(engine.playbackIssue == nil && engine.playbackNotice == nil,
              "来源切换后不残留播放异常提示")
        check(engine.phase == .idle, "空收藏给出空闲提示而不是继续收听")
        engine.setEnabled(false)
    }

    // MARK: 隔离

    // MARK: 数字命令与按键路由

    @MainActor
    private static func testNumericCommandsAndKeyRouting() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        // 主键盘 / 小键盘：1…0 全部按物理键码认识，1…6 才有命令
        let mainRow: [(UInt16, Int)] = [
            (18, 1), (19, 2), (20, 3), (21, 4), (23, 5), (22, 6),
            (26, 7), (28, 8), (25, 9), (29, 0)
        ]
        let keypad: [(UInt16, Int)] = [
            (83, 1), (84, 2), (85, 3), (86, 4), (87, 5), (88, 6),
            (89, 7), (91, 8), (92, 9), (82, 0)
        ]
        check(mainRow.allSatisfy { PracticeNumericKeys.digit(forKeyCode: $0.0) == $0.1 },
              "主键盘 1…0 的物理键码映射")
        check(keypad.allSatisfy { PracticeNumericKeys.digit(forKeyCode: $0.0) == $0.1 },
              "小键盘 1…0 的物理键码映射")
        check((1...6).allSatisfy { PracticeCommand(rawValue: $0) != nil },
              "1…6 各自对应一个动作")
        check([26, 28, 25, 29, 89, 91, 92, 82].allSatisfy {
            PracticeNumericKeys.command(forKeyCode: UInt16($0)) == nil
        }, "7…0 没有功能（仍会被消费）")

        // 真实 NSEvent 走同一条纯路由
        func keyEvent(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent? {
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: chars,
                charactersIgnoringModifiers: chars,
                isARepeat: false,
                keyCode: code
            )
        }
        func intent(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) -> PracticeKeyIntent? {
            guard let event = keyEvent(code, chars, flags) else { return nil }
            return PracticeKeyRouting.intent(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                characters: event.charactersIgnoringModifiers
            )
        }

        check(intent(18, "1") == .command(.replayOrRead), "主键盘 1 → 重听/朗读")
        check(intent(83, "1") == .command(.replayOrRead), "小键盘 1 → 重听/朗读")
        check(intent(22, "6") == .command(.exitPractice), "6 → 返回歌词")
        check(intent(26, "7") == .consumedDigit, "7 无动作但消费，不落字")
        check(intent(29, "0") == .consumedDigit, "0 无动作但消费，不落字")
        check(intent(82, "0") == .consumedDigit, "小键盘 0 同样消费")
        check(intent(0, "a") == .letter("a"), "普通字母仍直接输入")
        check(intent(0, "A", .shift) == .letter("A"), "Shift+字母仍按字母输入")
        check(intent(18, "1", .command) == .passThrough, "⌘1 不触发功能")
        check(intent(18, "1", .option) == .passThrough, "⌥1 不触发功能")
        check(intent(18, "1", .control) == .passThrough, "⌃1 不触发功能")
        check(intent(18, "!", .shift) == .passThrough, "Shift+1 不触发功能")
        check(intent(18, "1", .numericPad) == .command(.replayOrRead),
              "小键盘数字即使带 numericPad 也正常触发")

        let allDigitCodes: [UInt16] = [
            18, 19, 20, 21, 23, 22, 26, 28, 25, 29,
            83, 84, 85, 86, 87, 88, 89, 91, 92, 82
        ]
        check(allDigitCodes.allSatisfy {
            guard let value = intent($0, "\(PracticeNumericKeys.digit(forKeyCode: $0) ?? 0)") else {
                return false
            }
            if case .letter = value { return false }
            return true
        }, "任何数字键都不会被当成字母落进答案")

        // 数字命令不写答案、不响打字音效
        let bank = QuestionBank(url: tempURL("numeric-bank"))
        bank.add(text: "I kept the lanterns burning low", translation: nil,
                 title: "Fixture", artist: "Test", lineTime: 1)
        bank.add(text: "The river carried names we never said", translation: nil,
                 title: "Fixture", artist: "Test", lineTime: 2)
        let sound = SpyTypingSound()
        let engine = PracticeEngine(
            state: PlayerState(), watcher: SpyMusicController(), settings: settings,
            bank: bank, mistakes: MistakeBook(url: tempURL("numeric-mistakes"))
        )
        engine.typingSoundPlayer = sound
        engine.begin(source: .bank, ratio: 1.0)
        check(engine.phase == .asking, "数字命令测试从答题态开始")
        let inputBefore = engine.input
        for command in PracticeCommand.allCases {
            engine.perform(command)
        }
        check(engine.input == inputBefore,
              "1…6 不把数字写进答案")
        check(sound.plays == 0, "1…6 不响打字机音效")
        engine.setEnabled(false)

        // 阶段映射：可见按钮标题 = 按键动作，且收听中不抢提交
        let q = PracticeQuestion(
            text: "I kept the lanterns burning low", translation: nil,
            title: "Paper Lanterns", artist: "The Quiet Harbor",
            start: 12, end: 17.2, lineTime: 12
        )
        let phaseBank = QuestionBank(url: tempURL("numeric-phase-bank"))
        phaseBank.add(text: "I kept the lanterns burning low", translation: nil,
                      title: "Fixture", artist: "Test", lineTime: 1)
        let phaseEngine = PracticeEngine(
            state: PlayerState(), watcher: SpyMusicController(), settings: settings,
            bank: phaseBank,
            mistakes: MistakeBook(url: tempURL("numeric-phase-mistakes"))
        )

        phaseEngine.debugShow(
            phase: .asking, input: "I kept", verdict: nil, current: q,
            revealed: nil, progress: "1 / 2", score: 0, streak: 0, source: .song
        )
        check(phaseEngine.commandTitle(.replayOrRead) == "1 重听"
              && phaseEngine.commandTitle(.revealOrRetry) == "2 看答案"
              && phaseEngine.commandTitle(.primary) == nil
              && phaseEngine.commandTitle(.skip) == "4 跳过"
              && phaseEngine.commandTitle(.backToSetup) == "5 设置"
              && phaseEngine.commandTitle(.exitPractice) == "6 返回",
              "答题阶段不再有 3 提交，1/2/4/5/6 标签保持")
        check(phaseEngine.showsReturnHint, "答题阶段显示「回车继续」提示条件")
        let askingScore = phaseEngine.score
        phaseEngine.perform(.primary)
        check(phaseEngine.phase == .asking && phaseEngine.score == askingScore,
              "答题阶段按 3 不提交、不跳题")

        // 回车仍走原有提交逻辑：空提交只提示，不计错、不离开答题
        phaseEngine.input = ""
        phaseEngine.primaryAction()
        check(phaseEngine.coaching == "先填几个词"
              && phaseEngine.phase == .asking
              && phaseEngine.stats.wrong == 0,
              "答题阶段回车仍按原逻辑提交（空提交只提示）")

        phaseEngine.debugShow(
            phase: .listening, input: "I kept", verdict: nil, current: q,
            revealed: nil, progress: "1 / 2", score: 0, streak: 0, source: .song
        )
        let listeningProgress = phaseEngine.progress
        let listeningInput = phaseEngine.input
        check(phaseEngine.commandTitle(.primary) == nil, "收听中没有提交/下一句主操作")
        check(phaseEngine.commandTitle(.revealOrRetry) == nil, "收听中不显示看答案")
        phaseEngine.perform(.primary)
        check(phaseEngine.phase == .listening
              && phaseEngine.progress == listeningProgress
              && phaseEngine.input == listeningInput,
              "收听中按 3 不抢音乐时序、不改题面")

        phaseEngine.debugShow(
            phase: .revealed, input: "I kept", verdict: nil, current: q,
            revealed: q, progress: "1 / 2", score: 0, streak: 0, source: .song
        )
        check(phaseEngine.commandTitle(.revealOrRetry) == "2 再试"
              && phaseEngine.commandTitle(.primary) == "3 下一句"
              && phaseEngine.commandTitle(.skip) == nil,
              "揭示阶段 2/3 映射")

        phaseEngine.debugShow(
            phase: .idle, input: "", verdict: nil, current: nil,
            revealed: nil, progress: "", score: 5, streak: 0, source: .bank,
            stats: PracticeEngine.Stats(correct: 1, wrong: 0)
        )
        check(phaseEngine.commandTitle(.primary) == "3 再来一遍"
              && phaseEngine.commandTitle(.backToSetup) == "5 设置"
              && phaseEngine.commandTitle(.exitPractice) == "6 返回",
              "结束阶段 3/5/6 映射")

        // 设置阶段：3 开始使用引擎里的来源（数字键与按钮一致）
        phaseEngine.setEnabled(true)
        phaseEngine.selectSetupSource(.bank)
        check(phaseEngine.commandTitle(.primary) == "3 开始",
              "设置阶段 3 是开始")
        check(phaseEngine.commandTitle(.backToSetup) == nil,
              "已经在设置页时不再显示 5")
        phaseEngine.perform(.primary)
        check(phaseEngine.phase == .asking && phaseEngine.current != nil,
              "数字 3 在设置页真的开始练习")
        phaseEngine.setEnabled(false)
    }

    // MARK: 本地朗读生命周期

    @MainActor
    private static func testSpeechReaderLifecycle() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let bank = QuestionBank(url: tempURL("speech-bank"))
        bank.add(text: "I kept the lanterns burning low", translation: nil,
                 title: "Fixture", artist: "Test", lineTime: 1)
        bank.add(text: "The river carried names we never said", translation: nil,
                 title: "Fixture", artist: "Test", lineTime: 2)
        let book = MistakeBook(url: tempURL("speech-book"))
        let engine = PracticeEngine(
            state: PlayerState(), watcher: SpyMusicController(),
            settings: settings, bank: bank, mistakes: book
        )
        let spy = SpySpeechSpeaker()
        engine.installSpeechSpeaker(spy)

        engine.begin(source: .bank, ratio: 1.0)
        check(!engine.isSpeaking, "进入练习不自动朗读")
        check(spy.spoken.isEmpty, "没有用户操作就不会发朗读请求")
        check(engine.commandTitle(.replayOrRead) == "1 朗读", "收藏练习有 1 朗读")

        let first = engine.current?.text
        engine.perform(.replayOrRead)
        check(spy.spoken.count == 1 && spy.spoken.first?.text == first,
              "1 朗读当前英文原句")
        check(engine.isSpeaking, "朗读中状态可见")
        check(engine.score == 0 && engine.stats.correct == 0 && engine.stats.wrong == 0,
              "朗读不影响分数/统计")

        engine.perform(.replayOrRead)
        check(!engine.isSpeaking && spy.spoken.count == 1,
              "朗读中再按 1 是停止，不重复叠音")

        engine.perform(.replayOrRead)
        let oldToken = spy.spoken.last!.token
        engine.next()
        check(!engine.isSpeaking, "换题取消旧朗读")
        check(spy.stops > 0, "换题前确实向朗读器发了停止")

        let newText = engine.current?.text
        engine.perform(.replayOrRead)
        check(spy.spoken.last?.text == newText && newText != first, "新题读新句，不读上一题")
        let newToken = spy.spoken.last!.token

        // 新请求已排队但还没开口：isSpeaking 暂时 false，旧回调也不能清新句
        spy.simulatePendingStart()
        spy.finish(token: oldToken)
        check(engine.isSpeaking, "新句待启动时，迟到旧回调不清新句归属")
        spy.finish(token: newToken)
        check(!engine.isSpeaking, "当前句读完自然清状态")

        // 无英语音色：明确提示，不静默改用中文
        spy.available = false
        engine.perform(.replayOrRead)
        check(!engine.isSpeaking && engine.speechNotice == "没有可用的英语语音",
              "无英语音色给一句可恢复提示")
        engine.restartSession()
        check(engine.speechNotice == nil, "换题/重来清掉朗读提示")
        spy.available = true

        // 看答案 / 再试 / 改强度 / 重来 / 切来源 / 结束 / 退出都取消
        engine.perform(.replayOrRead)
        engine.perform(.revealOrRetry)
        check(engine.phase == .revealed && !engine.isSpeaking, "看答案取消朗读")
        engine.perform(.replayOrRead)
        check(spy.spoken.last?.text == engine.revealed?.text, "揭示页读的是当前英文原句")
        engine.perform(.revealOrRetry)
        check(engine.phase == .asking && !engine.isSpeaking, "再试取消朗读")
        engine.perform(.replayOrRead)
        engine.changeRatio(0.6)
        check(!engine.isSpeaking, "改填空强度取消朗读")
        engine.perform(.replayOrRead)
        engine.restartSession()
        check(!engine.isSpeaking, "再来一遍取消朗读")

        engine.perform(.replayOrRead)
        engine.begin(source: .mistakes, ratio: 1.0)
        check(!engine.isSpeaking, "切来源取消朗读")

        // 空错题本进入空闲；不会因此朗读任何旧句
        check(spy.spoken.count > 0, "朗读探针确实记录过请求")
        engine.setEnabled(true)
        engine.selectSetupSource(.bank)
        engine.perform(.primary)
        check(engine.phase == .asking, "重新开始收藏练习")
        engine.perform(.replayOrRead)
        engine.stopSession()
        check(!engine.isSpeaking && engine.phase == .idle, "结束练习取消朗读")

        settings.practiceMode = true
        engine.begin(source: .bank, ratio: 1.0)
        engine.perform(.replayOrRead)
        engine.perform(.exitPractice)
        check(settings.practiceMode == false && !engine.isSpeaking,
              "6 退出练习回歌词并取消朗读")

        // 默认引擎静默：自检/快照不构造 AVSpeechSynthesizer
        let silentEngine = PracticeEngine(
            state: PlayerState(), watcher: SpyMusicController(), settings: settings,
            bank: QuestionBank(url: tempURL("speech-silent-bank")),
            mistakes: MistakeBook(url: tempURL("speech-silent-mistakes"))
        )
        check(!silentEngine.isSpeaking, "默认朗读器静默（隔离运行不发真实语音）")
    }

    // MARK: 窗口拖拽与背景透明度

    @MainActor
    private static func testWindowChromeAndDrag() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        // 背景透明度：默认保持原有视觉，真实改变底色 alpha，并在透明时加材质
        check(abs(settings.backgroundTransparency) < 0.0001,
              "背景透明度默认 0（保留现有视觉）")
        check(abs(WindowChrome.backgroundFillAlpha(transparency: 0)
                  - WindowChrome.baseBackgroundAlpha) < 0.0001,
              "透明度 0 时背景仍是 0.82")
        check(WindowChrome.backgroundBlurAlpha(transparency: 0) == 0,
              "透明度 0 时不加材质层")
        let fill15 = WindowChrome.backgroundFillAlpha(transparency: 0.15)
        let fill45 = WindowChrome.backgroundFillAlpha(transparency: 0.45)
        check(fill45 < fill15 && fill15 < WindowChrome.baseBackgroundAlpha,
              "透明度越高，真实桌面透出越多: \(fill15) → \(fill45)")
        check(WindowChrome.backgroundBlurAlpha(transparency: 0.45) > 0,
              "透明时用系统材质保住文字可读性")

        settings.backgroundTransparency = 0.3
        check(abs(settings.backgroundTransparency - 0.3) < 0.0001,
              "背景透明度写入注入偏好")
        check(abs((defaults.object(forKey: "backgroundTransparency") as? Double ?? -1) - 0.3) < 0.0001,
              "背景透明度持久化到独立 defaults")
        let reloaded = Settings(defaults: defaults)
        check(abs(reloaded.backgroundTransparency - 0.3) < 0.0001, "重启后恢复背景透明度")
        settings.backgroundTransparency = 0.9
        check(abs(settings.backgroundTransparency - WindowChrome.maxTransparency) < 0.0001,
              "背景透明度上限被钳到 45%")
        settings.backgroundTransparency = -1
        check(settings.backgroundTransparency == 0, "背景透明度下限被钳到 0")
        check(Settings.backgroundTransparencyLabel(0) == "不透明"
              && Settings.backgroundTransparencyLabel(0.3) == "30%",
              "透明度菜单文案简洁")

        check(WindowChrome.dragStripHeight >= 10 && WindowChrome.dragStripHeight <= 14,
              "顶部拖拽条保持窄条，不占内容")
        check(WindowChrome.dragStripEnabled(locked: false)
              && !WindowChrome.dragStripEnabled(locked: true),
              "锁定位置时拖拽条不响应")

        // 原生 hitTest：拖拽条在真实布局偏移下仍必须命中（点属于 superview 坐标）
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 1502, y: 134, width: 820, height: 440),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 440))
        window.contentView = root
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 440))
        root.addSubview(container)
        let bar = WindowDragBar.DragBarView(
            frame: NSRect(x: 36, y: 420, width: 748, height: WindowChrome.dragStripHeight)
        )
        container.addSubview(bar)
        container.layoutSubtreeIfNeeded()

        let hit = container.hitTest(NSPoint(x: 300, y: 426))
        check(hit === bar, "顶部拖拽条在真实偏移布局里能被命中（superview 坐标）")
        let below = container.hitTest(NSPoint(x: 300, y: 200))
        check(below !== bar, "拖拽条只覆盖顶部窄带，不吃下方内容点击")

        // 真实 mouseDown/Dragged：位移完全来自事件自己的 locationInWindow，
        // 不读全局 NSEvent.mouseLocation（可访问性/合成事件也能拖）。
        let downWindowPoint = NSPoint(x: 410, y: 434)
        let dragWindowPoint = NSPoint(x: 470, y: 454)
        guard let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: window.convertPoint(toScreen: downWindowPoint),
            modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ), let dragged = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: window.convertPoint(toScreen: dragWindowPoint),
            modifierFlags: [], timestamp: 0.1,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1
        ) else {
            check(false, "构造原生拖拽事件")
            return
        }
        let before = window.frame.origin
        bar.mouseDown(with: down)
        bar.mouseDragged(with: dragged)
        bar.mouseUp(with: dragged)
        let after = window.frame.origin
        check(abs((after.x - before.x) - 60) < 0.5 && abs((after.y - before.y) - 20) < 0.5,
              "拖拽条按事件 locationInWindow 移动窗口: \(before) → \(after)")
    }

    @MainActor
    private static func testIsolation() {
        check(AppRuntime.isIsolated, "自检运行在隔离模式")

        let key = "fontSize"
        let before = UserDefaults.standard.double(forKey: key)
        let probe = before == 13.75 ? 13.5 : 13.75
        let settings = Settings()
        settings.fontSize = probe
        let after = UserDefaults.standard.double(forKey: key)
        check(settings.fontSize == probe, "隔离 Settings 可正常读写")
        check(before == after, "隔离 Settings 不写真实偏好")

        if ProcessInfo.processInfo.environment["GAPSONG_HOME"] == nil {
            check(Paths.base.path.contains("gapsong-isolated"), "自检缓存/日志目录走隔离目录")
        }
    }

    // MARK: 网络

    private static func testNetwork() async {
        // 网络自检只验证「能抓取并解析」；这里使用公有领域的赞美诗，不内置任何商业歌词。
        let track = Track(
            title: "Amazing Grace",
            artist: "Saint Michael's Singers",
            album: "The Hymn Makers - John Newton & William Cowper",
            duration: 213
        )
        let t0 = Date()
        var songSample: String?
        if let r = await LyricsService.fetch(track: track) {
            let parsed = LRCParser.parse(r.raw)
            let dt = String(format: "%.2fs", Date().timeIntervalSince(t0))
            check(parsed.lines.count > 0, "歌词: \(r.source) 时间轴=\(parsed.synced) 行数=\(parsed.lines.count) 用时=\(dt)")
            songSample = parsed.lines.map(\.text).joined(separator: " ")
            if let sample = songSample {
                check(TranslationEngine.detectLanguage(in: sample) != nil, "歌词语言识别")
            }
        } else {
            check(false, "歌词抓取（检查网络）")
        }

        let sample = "Morning found the harbor painted gold"
        if let lang = TranslationEngine.detectLanguage(in: songSample ?? sample) {
            check(true, "语言识别: \(lang.minimalIdentifier)")
            let avail = LanguageAvailability()
            let to = Locale.Language(identifier: "zh-Hans")
            let st = await avail.status(from: lang, to: to)
            info("翻译可用性 \(lang.minimalIdentifier)→zh-Hans: \(st)")
        } else {
            check(false, "语言识别")
        }
    }

    // MARK: 测试描述符

    static func fakeDescriptor() -> NSAppleEventDescriptor? {
        let list = NSAppleEventDescriptor.list()
        let values: [Any] = ["Paper Lanterns", "The Quiet Harbor", "Low Tide Letters", 242.0, 33.5, "playing"]
        for v in values {
            let d: NSAppleEventDescriptor?
            if let dbl = v as? Double {
                d = NSAppleEventDescriptor(double: dbl)
            } else {
                d = NSAppleEventDescriptor(string: v as? String ?? "")
            }
            guard let d else { return nil }
            list.insert(d, at: list.numberOfItems + 1)
        }
        return list
    }
}
