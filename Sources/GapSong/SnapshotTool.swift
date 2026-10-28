import SwiftUI
import AppKit

enum SnapshotTool {
    @MainActor
    static func render(
        to path: String,
        width: CGFloat = 836,
        height: CGFloat = 155,
        full: Bool = false,
        practice: Bool = false,
        answer: Bool = false,
        setup: Bool = false,
        bankPractice: Bool = false,
        retry: Bool = false,
        waiting: Bool = false,
        library: LibraryTab? = nil,
        mistakePractice: Bool = false,
        issue: PlaybackIssue? = nil,
        storageWarning: Bool = false,
        libraryConfirmDelete: Bool = false
    ) -> Never {
        setvbuf(stdout, nil, _IONBF, 0)
        let settings = Settings()
        // 可选 --snapshot-font 72：同一套快照覆盖 14–72 的字号排版
        if let raw = SnapshotTool.argumentValue("--snapshot-font"),
           let fontSize = Double(raw) {
            settings.fontSize = min(max(fontSize, 14), 72)
        }
        let state = PlayerState()
        // 快照用独立题库，别把用户真实的收藏读进来。
        // storageWarning 变体故意指向一个只读目录，让写入真的失败（不伪造提示文案）。
        let bankURL: URL
        if storageWarning {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("gapsong-snapshot-readonly-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
            bankURL = dir.appendingPathComponent("questions.json")
        } else {
            bankURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("gapsong-snapshot-\(UUID().uuidString).json")
        }
        let bank = QuestionBank(url: bankURL)
        if storageWarning {
            // 真正触发一次写失败，界面上的警示必须来自真实错误
            _ = bank.add(
                text: DemoFixtures.firstLine, translation: DemoFixtures.firstTranslation,
                title: DemoFixtures.paperLanterns.track.title,
                artist: DemoFixtures.paperLanterns.track.artist, lineTime: 12
            )
        }
        let mistakeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gapsong-snapshot-mistakes-\(UUID().uuidString).json")
        let mistakes = MistakeBook(url: mistakeURL)
        let engine = PracticeEngine(
            state: state,
            watcher: NoopMusicController(),
            settings: settings,
            bank: bank,
            mistakes: mistakes
        )
        // 快照绝不发真实语音：显式保持静默朗读器（数字 1 的标签仍可核对）
        engine.installSpeechSpeaker(SilentSpeechSpeaker())

        if let library {
            renderLibrary(bank: bank, mistakes: mistakes, tab: library,
                          path: path, width: width, height: height,
                          confirmDelete: libraryConfirmDelete)
        } else if mistakePractice {
            renderMistakePractice(state: state, settings: settings, engine: engine,
                                  bank: bank, mistakes: mistakes,
                                  path: path, width: width, height: height)
        } else if setup {
            renderPracticeSetup(state: state, settings: settings, engine: engine, bank: bank,
                                mistakes: mistakes, path: path, width: width, height: height)
        } else if bankPractice {
            renderBankPractice(state: state, settings: settings, engine: engine, bank: bank,
                               mistakes: mistakes, path: path, width: width, height: height)
        } else if practice {
            renderPractice(state: state, engine: engine, settings: settings, bank: bank,
                           mistakes: mistakes, path: path, width: width, height: height,
                           answer: answer, retry: retry, waiting: waiting, issue: issue)
        } else {
            renderLyrics(state: state, settings: settings, engine: engine, bank: bank,
                         mistakes: mistakes, path: path, width: width, height: height, full: full)
        }
    }

    /// 读取 `--flag value` 形式的参数（仅快照进程使用）
    private static func argumentValue(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag), args.count > index + 1 else { return nil }
        return args[index + 1]
    }

    // MARK: 歌词窗

    @MainActor
    private static func renderLyrics(
        state: PlayerState,
        settings: Settings,
        engine: PracticeEngine,
        bank: QuestionBank,
        mistakes: MistakeBook,
        path: String,
        width: CGFloat,
        height: CGFloat,
        full: Bool
    ) -> Never {
        let song = DemoFixtures.paperLanterns
        state.debugInject(
            track: song.track,
            position: 33.5,
            playing: true,
            lines: song.lines,
            translations: song.translations
        )
        settings.showTranslation = true
        // 快照进程会写 UserDefaults，别把练习模式也顺手打开
        settings.practiceMode = false
        settings.forceFull = full

        let view = OverlayView(
            state: state,
            settings: settings,
            translator: state.translator,
            practice: engine,
            bank: bank,
            mistakes: mistakes
        )
        .environment(\.lyricPreview, true)
        .frame(width: width, height: height)

        write(view, to: path)
    }

    // MARK: 听写窗

    @MainActor
    private static func renderPractice(
        state: PlayerState,
        engine: PracticeEngine,
        settings: Settings,
        bank: QuestionBank,
        mistakes: MistakeBook,
        path: String,
        width: CGFloat,
        height: CGFloat,
        answer: Bool,
        retry: Bool,
        waiting: Bool,
        issue: PlaybackIssue?
    ) -> Never {
        let song = DemoFixtures.paperLanterns
        state.debugInject(
            track: song.track,
            // 等句末的预览要让「本句进度」有真实的中间位置；普通答题仍是暂停态
            position: waiting ? 15.4 : 12.4,
            playing: waiting,
            lines: song.lines,
            translations: song.translations
        )
        settings.showTranslation = true
        settings.practiceRatio = 1.0

        let question = PracticeQuestion(
            text: DemoFixtures.firstLine,
            translation: DemoFixtures.firstTranslation,
            title: song.track.title,
            artist: song.track.artist,
            start: 12,
            end: 17.2,
            lineTime: 12
        )
        let verdict = DictationJudge.judge(
            expected: question.text,
            actual: "I kept the lanterns burning law"
        )
        engine.debugShow(
            // 播放异常时停在收听态：输入已保留，等用户选择重试/结束/跳过
            phase: waiting ? .listening : (issue == nil ? (answer ? .revealed : .asking) : .listening),
            // 答题态模拟「打到一半」：前面正确、一个字母错、后面还没打
            input: waiting
                ? DemoFixtures.firstLine
                : (answer ? "I kept the lanterns burning law" : "I kept the lanterns buring"),
            verdict: answer ? verdict : nil,
            current: question,
            revealed: answer ? question : nil,
            progress: "1 / 8",
            score: 128,
            streak: answer ? 0 : 3,
            retry: retry,
            playbackIssue: issue,
            waitingForLineEnd: waiting
        )

        let view = OverlayView(
            state: state,
            settings: settings,
            translator: state.translator,
            practice: engine,
            bank: bank,
            mistakes: mistakes,
            previewSelectedWord: answer ? "lanterns" : nil
        )
        .environment(\.lyricPreview, true)
        .environment(\.practicePreview, true)
        .frame(width: width, height: height)

        writeHosted(view, width: width, height: height, to: path)
    }

    // MARK: 题库练习

    @MainActor
    private static func renderBankPractice(
        state: PlayerState,
        settings: Settings,
        engine: PracticeEngine,
        bank: QuestionBank,
        mistakes: MistakeBook,
        path: String,
        width: CGFloat,
        height: CGFloat
    ) -> Never {
        let song = DemoFixtures.paperLanterns
        state.debugInject(
            track: song.track,
            position: 12.4,
            playing: false,
            lines: song.lines,
            translations: song.translations
        )

        bank.add(
            text: DemoFixtures.firstLine,
            translation: DemoFixtures.firstTranslation,
            title: song.track.title,
            artist: song.track.artist,
            lineTime: 12
        )
        bank.add(
            text: DemoFixtures.secondLine,
            translation: DemoFixtures.secondTranslation,
            title: song.track.title,
            artist: song.track.artist,
            lineTime: 17.2
        )
        bank.add(
            text: DemoFixtures.thirdLine,
            translation: DemoFixtures.thirdTranslation,
            title: song.track.title,
            artist: song.track.artist,
            lineTime: 22.4
        )

        settings.showTranslation = true
        settings.practiceRatio = 0.6
        engine.begin(source: .bank, ratio: 0.6)

        let view = OverlayView(
            state: state,
            settings: settings,
            translator: state.translator,
            practice: engine,
            bank: bank,
            mistakes: mistakes
        )
        .environment(\.lyricPreview, true)
        .environment(\.practicePreview, true)
        .frame(width: width, height: height)

        writeHosted(view, width: width, height: height, to: path)
    }

    // MARK: 练习设置

    @MainActor
    private static func renderPracticeSetup(
        state: PlayerState,
        settings: Settings,
        engine: PracticeEngine,
        bank: QuestionBank,
        mistakes: MistakeBook,
        path: String,
        width: CGFloat,
        height: CGFloat
    ) -> Never {
        let song = DemoFixtures.paperLanterns
        state.debugInject(
            track: song.track,
            position: 12.4,
            playing: false,
            lines: song.lines,
            translations: song.translations
        )
        bank.add(
            text: DemoFixtures.thirdLine,
            translation: DemoFixtures.thirdTranslation,
            title: song.track.title,
            artist: song.track.artist,
            lineTime: 22.4
        )
        let mistakeQuestion = PracticeQuestion(
            text: DemoFixtures.thirdLine,
            translation: DemoFixtures.thirdTranslation,
            title: song.track.title,
            artist: song.track.artist,
            start: nil,
            end: nil,
            lineTime: 22.4
        )
        let mistakeAttempt = MistakeAttempt(
            source: "bank", ratio: 0.6, rawInput: "The riber carried",
            translation: DemoFixtures.thirdTranslation, wasRetry: false,
            blanks: [
                MistakeBlank(ordinal: 0, wordIndex: 0, expected: "The", actual: "The", skipped: false),
                MistakeBlank(ordinal: 1, wordIndex: 1, expected: "river", actual: "riber", skipped: false),
                MistakeBlank(ordinal: 2, wordIndex: 2, expected: "carried", actual: "carried", skipped: false),
                MistakeBlank(ordinal: 3, wordIndex: 3, expected: "names", actual: "", skipped: true)
            ]
        )
        _ = mistakes.record(
            question: mistakeQuestion,
            translation: DemoFixtures.thirdTranslation,
            attempt: mistakeAttempt
        )

        settings.showTranslation = true
        settings.practiceRatio = 0.6

        let view = OverlayView(
            state: state,
            settings: settings,
            translator: state.translator,
            practice: engine,
            bank: bank,
            mistakes: mistakes
        )
        .environment(\.lyricPreview, true)
        .environment(\.practicePreview, true)
        .frame(width: width, height: height)

        writeHosted(view, width: width, height: height, to: path)
    }

    // MARK: 收藏/错题管理

    @MainActor
    private static func renderLibrary(
        bank: QuestionBank,
        mistakes: MistakeBook,
        tab: LibraryTab,
        path: String,
        width: CGFloat,
        height: CGFloat,
        confirmDelete: Bool = false
    ) -> Never {
        let song = DemoFixtures.paperLanterns
        bank.add(text: DemoFixtures.firstLine, translation: DemoFixtures.firstTranslation,
                 title: song.track.title, artist: song.track.artist, lineTime: 12)
        bank.add(text: DemoFixtures.secondLine, translation: DemoFixtures.secondTranslation,
                 title: song.track.title, artist: song.track.artist, lineTime: 17.2)
        bank.add(text: DemoFixtures.thirdLine, translation: DemoFixtures.thirdTranslation,
                 title: song.track.title, artist: song.track.artist, lineTime: 22.4)

        let q1 = PracticeQuestion(
            text: DemoFixtures.firstLine, translation: DemoFixtures.firstTranslation,
            title: song.track.title, artist: song.track.artist,
            start: nil, end: nil, lineTime: 12
        )
        let q2 = PracticeQuestion(
            text: DemoFixtures.thirdLine, translation: DemoFixtures.thirdTranslation,
            title: song.track.title, artist: song.track.artist,
            start: nil, end: nil, lineTime: 22.4
        )
        _ = mistakes.record(question: q1, translation: DemoFixtures.firstTranslation, attempt: sampleAttempt(
            q1, actual: ["I", "kept", "the", "lanterns", "burning", "law"],
            raw: "I kept the lanterns burning law"
        ))
        _ = mistakes.record(question: q1, translation: DemoFixtures.firstTranslation, attempt: sampleAttempt(
            q1, actual: ["I", "kept", "the", "lanterns", "burnig", ""],
            raw: "I kept the lanterns burnig",
            retry: true
        ))
        _ = mistakes.record(question: q2, translation: DemoFixtures.thirdTranslation, attempt: sampleAttempt(
            q2,
            actual: ["The", "river", "carried", "names", "we", "never", "sayed"],
            raw: "The river carried names we never sayed"
        ))

        let model = LibraryModel(tab: tab)
        if confirmDelete {
            // 只在快照里把某一行的删除确认框展开，不写任何文件
            switch tab {
            case .favorites:
                if let id = bank.items.first?.id { model.pendingDelete = .favorite(id) }
            case .mistakes:
                if let id = mistakes.entries.first?.id { model.pendingDelete = .mistake(id) }
            }
        }

        let view = LibraryView(
            favorites: bank,
            mistakes: mistakes,
            model: model,
            preview: true,
            onPracticeFavorite: { _ in },
            onPracticeAllFavorites: {},
            onPracticeMistake: { _ in },
            onPracticeAllMistakes: {},
            onClearFavorites: {},
            onClearMistakes: {},
            onClose: {}
        )
        .frame(width: width, height: height)

        write(view, to: path)
    }

    private static func sampleAttempt(
        _ question: PracticeQuestion,
        actual: [String],
        raw: String,
        retry: Bool = false
    ) -> MistakeAttempt {
        let words = PracticeBlanks.words(in: question.text)
        let blanks = words.indices.map { index in
            let value = index < actual.count ? actual[index] : ""
            return MistakeBlank(
                ordinal: index,
                wordIndex: index,
                expected: words[index].raw,
                actual: value,
                skipped: value.isEmpty
            )
        }
        return MistakeAttempt(
            source: "bank",
            ratio: 1,
            rawInput: raw,
            translation: question.translation,
            wasRetry: retry,
            blanks: blanks
        )
    }

    // MARK: 错题练习

    @MainActor
    private static func renderMistakePractice(
        state: PlayerState,
        settings: Settings,
        engine: PracticeEngine,
        bank: QuestionBank,
        mistakes: MistakeBook,
        path: String,
        width: CGFloat,
        height: CGFloat
    ) -> Never {
        let song = DemoFixtures.paperLanterns
        let question = PracticeQuestion(
            text: DemoFixtures.firstLine, translation: DemoFixtures.firstTranslation,
            title: song.track.title, artist: song.track.artist,
            start: nil, end: nil, lineTime: 12
        )
        _ = mistakes.record(question: question, translation: DemoFixtures.firstTranslation, attempt: sampleAttempt(
            question, actual: ["I", "kept", "the", "lanterns", "burning", "law"],
            raw: "I kept the lanterns burning law"
        ))
        _ = mistakes.record(question: question, translation: DemoFixtures.firstTranslation, attempt: sampleAttempt(
            question, actual: ["I", "kept", "the", "lanterns", "burnig", ""],
            raw: "I kept the lanterns burnig", retry: true
        ))

        settings.showTranslation = true
        settings.practiceRatio = 1.0
        engine.debugShow(
            phase: .asking,
            input: "I kept the lanterns buring",
            verdict: nil,
            current: question,
            revealed: nil,
            progress: "1 / 2",
            score: 0,
            streak: 0,
            source: .mistakes
        )

        let view = OverlayView(
            state: state,
            settings: settings,
            translator: state.translator,
            practice: engine,
            bank: bank,
            mistakes: mistakes
        )
        .environment(\.lyricPreview, true)
        .environment(\.practicePreview, true)
        .frame(width: width, height: height)

        writeHosted(view, width: width, height: height, to: path)
    }

    // MARK: 输出

    /// 普通快照：ImageRenderer 足够，且能正确画纯 SwiftUI 内容。
    @MainActor
    private static func write(_ view: some View, to path: String) -> Never {
        finish(renderWithImageRenderer(view), path: path)
    }

    /// 听写/设置这类界面内部有 ScrollView。当前的 SwiftUI `ImageRenderer`
    /// 不会给 ScrollView 做栅格化（输出整片纯背景），所以这里改用
    /// NSHostingView + cacheDisplay 走 AppKit 的原生位图缓存：
    /// 同一个 SwiftUI 视图、同一套布局，只是换了光栅化路径，生产 UI 不受影响。
    @MainActor
    private static func writeHosted(
        _ view: some View,
        width: CGFloat,
        height: CGFloat,
        to path: String
    ) -> Never {
        finish(renderWithHostingView(view, width: width, height: height), path: path)
    }

    @MainActor
    private static func finish(_ image: NSImage?, path: String) -> Never {
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("render failed")
            exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("saved \(path) size=\(image.size)")
        exit(0)
    }

    @MainActor
    private static func renderWithImageRenderer(_ view: some View) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage
    }

    @MainActor
    private static func renderWithHostingView(
        _ view: some View,
        width: CGFloat,
        height: CGFloat
    ) -> NSImage? {
        let scale: CGFloat = 2
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        let host = NSHostingView(rootView: view.frame(width: width, height: height))
        host.frame = frame

        // 放进一个不显示的 borderless 窗口：有真实窗口层级才能拿到正确的
        // 原生位图缓存（ScrollView 也才会真正排版并绘制内容）。
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setIsVisible(false)
        host.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * scale),
            pixelsHigh: Int(height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: width, height: height)

        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        _ = window
        return image
    }
}
