import Foundation
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
            await testQuestionBank()
            await testFavoritesCompatibility()
            await testRetryFlow()
            await testBlankNavigation()
            await testMistakeBook()
            await testMistakeRecording()
            await testMistakePracticeOffline()
            await testSourceSwitchCancelsAutoAdvance()
            await testSourceSwitchFromSong()
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
        check(!stillThere && bank.count == 1, "收藏再点一次移除")
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
        check(!removed && QuestionBank(url: url).count == 1, "旧收藏可正常取消")
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

    // MARK: 隔离

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
