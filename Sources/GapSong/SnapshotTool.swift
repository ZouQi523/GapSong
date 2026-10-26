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
        library: LibraryTab? = nil,
        mistakePractice: Bool = false
    ) -> Never {
        setvbuf(stdout, nil, _IONBF, 0)
        let settings = Settings()
        let state = PlayerState()
        // 快照用独立题库，别把用户真实的收藏读进来
        let bankURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gapsong-snapshot-\(UUID().uuidString).json")
        let bank = QuestionBank(url: bankURL)
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

        if let library {
            renderLibrary(bank: bank, mistakes: mistakes, tab: library,
                          path: path, width: width, height: height)
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
                           answer: answer, retry: retry)
        } else {
            renderLyrics(state: state, settings: settings, engine: engine, bank: bank,
                         mistakes: mistakes, path: path, width: width, height: height, full: full)
        }
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
        retry: Bool
    ) -> Never {
        let song = DemoFixtures.paperLanterns
        state.debugInject(
            track: song.track,
            position: 12.4,
            playing: false,
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
            phase: answer ? .revealed : .asking,
            // 答题态模拟「打到一半」：前面正确、一个字母错、后面还没打
            input: answer ? "I kept the lanterns burning law" : "I kept the lanterns buring",
            verdict: answer ? verdict : nil,
            current: question,
            revealed: answer ? question : nil,
            progress: "1 / 8",
            score: 128,
            streak: answer ? 0 : 3,
            retry: retry
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

        write(view, to: path)
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

        write(view, to: path)
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

        write(view, to: path)
    }

    // MARK: 收藏/错题管理

    @MainActor
    private static func renderLibrary(
        bank: QuestionBank,
        mistakes: MistakeBook,
        tab: LibraryTab,
        path: String,
        width: CGFloat,
        height: CGFloat
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

        let view = LibraryView(
            favorites: bank,
            mistakes: mistakes,
            model: LibraryModel(tab: tab),
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

        write(view, to: path)
    }

    // MARK: 输出

    @MainActor
    private static func write(_ view: some View, to path: String) -> Never {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard let image = renderer.nsImage,
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
}
