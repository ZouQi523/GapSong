import SwiftUI
import AppKit

/// 听写界面：听 → 填空 → 判分 → 揭示 → 点词查义
struct PracticeView: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var settings: Settings
    @ObservedObject var engine: PracticeEngine
    @ObservedObject var translator: TranslationEngine
    @ObservedObject var bank: QuestionBank
    @ObservedObject var mistakes: MistakeBook

    @FocusState private var inputFocused: Bool
    /// 离屏渲染画不了 AppKit 控件，预览时用 Text 顶替输入框
    @Environment(\.practicePreview) private var preview

    /// 点开释义的词（预览时可由外部预置）
    @State private var selectedWord: String?

    init(
        state: PlayerState,
        settings: Settings,
        engine: PracticeEngine,
        translator: TranslationEngine,
        bank: QuestionBank,
        mistakes: MistakeBook,
        initialSelectedWord: String? = nil
    ) {
        self.state = state
        self.settings = settings
        self.engine = engine
        self.translator = translator
        self.bank = bank
        self.mistakes = mistakes
        _selectedWord = State(initialValue: initialSelectedWord)
    }

    var body: some View {
        GeometryReader { geo in
            let s = scale(for: geo.size)
            VStack(spacing: 9 * s) {
                header(s)
                Divider().overlay(Color.white.opacity(0.08))
                scoreBar(s)
                Spacer(minLength: 0)
                stage(s)
                Spacer(minLength: 0)
                actions(s)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .onChange(of: engine.phase) { _, newValue in
            selectedWord = nil
            if newValue == .asking {
                DispatchQueue.main.async { inputFocused = true }
            }
        }
        .onChange(of: engine.current?.id) { _, _ in
            selectedWord = nil
        }
        .onAppear {
            if engine.phase == .asking {
                DispatchQueue.main.async { inputFocused = true }
            }
        }
        .onChange(of: inputFocused) { _, focused in
            Diag.log("practice: input focus \(focused)")
        }
        // Esc 退出练习。走 onExitCommand 而不是 keyboardShortcut，
        // 这样输入法组字时 Esc 先给输入法用，不会误退出。
        .onExitCommand {
            settings.practiceMode = false
        }
    }

    /// 字号随窗口等比缩放：小窗不挤，大窗不空
    private func scale(for size: CGSize) -> CGFloat {
        guard size.width > 1, size.height > 1 else { return 1 }
        let base = min(size.width / 720, size.height / 300)
        return min(max(base, 0.8), 1.7)
    }

    // MARK: 顶部

    private func header(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Color.clear.frame(width: 12 * s, height: 1)   // 给左上角关闭按钮留位

            if !engine.source.badge.isEmpty {
                Text(engine.source.badge)
                    .font(.system(size: 9 * s, weight: .semibold))
                    .padding(.horizontal, 5 * s)
                    .padding(.vertical, 1.5 * s)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Text(engine.sourceTitle.isEmpty ? "—" : engine.sourceTitle)
                .font(.system(size: 11 * s, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            Text("·")
                .font(.system(size: 11 * s))
                .foregroundStyle(.white.opacity(0.25))
            Text(engine.sourceArtist)
                .font(.system(size: 11 * s))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)

            Spacer(minLength: 8)

            favoriteButton(s)

            if !engine.progress.isEmpty {
                Text(engine.progress)
                    .font(.system(size: 10 * s).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    /// 积分、连对、以及可随时调整的填空强度
    private func scoreBar(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Text("\(engine.score)")
                .font(.system(size: 26 * s, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
                .contentTransition(.numericText())

            Text("分")
                .font(.system(size: 11 * s))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 7 * s)

            if engine.streak >= 2 {
                Text("连对 \(engine.streak)")
                    .font(.system(size: 10 * s, weight: .medium))
                    .padding(.horizontal, 7 * s)
                    .padding(.vertical, 2.5 * s)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 4 * s)
            }

            if engine.isRetry {
                Text("重试 · 不计分")
                    .font(.system(size: 10 * s, weight: .medium))
                    .padding(.horizontal, 7 * s)
                    .padding(.vertical, 2.5 * s)
                    .background(Capsule().fill(Color.orange.opacity(0.16)))
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .padding(.top, 4 * s)
            }

            if engine.source == .mistakes {
                Text("错题 ×\(engine.mistakeAttemptCount(for: engine.current))")
                    .font(.system(size: 10 * s, weight: .medium))
                    .padding(.horizontal, 7 * s)
                    .padding(.vertical, 2.5 * s)
                    .background(Capsule().fill(Color.red.opacity(0.16)))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.5).opacity(0.95))
                    .padding(.top, 4 * s)
            }

            Spacer(minLength: 0)

            ratioMenu(s)
        }
    }

    @ViewBuilder
    private func ratioMenu(_ s: CGFloat) -> some View {
        // 离屏预览画不了 AppKit 的 Menu 控件（会变成黄条），预览时只画标签
        if preview {
            ratioLabel(s)
        } else {
            Menu {
                ForEach(Settings.practiceRatioChoices, id: \.self) { value in
                    Button {
                        engine.changeRatio(value)
                    } label: {
                        Text(value == settings.practiceRatio
                             ? "✓ 填空 \(Settings.ratioLabel(value))"
                             : "填空 \(Settings.ratioLabel(value))")
                    }
                }
            } label: {
                ratioLabel(s)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("调整听写强度：挖空整句里多少词")
        }
    }

    private func ratioLabel(_ s: CGFloat) -> some View {
        HStack(spacing: 4 * s) {
            Text("填空 \(settings.practiceRatioLabel)")
                .foregroundStyle(.white.opacity(0.78))
            if engine.eligibleWordCount > 0 {
                Text("\(engine.blankWordCount)/\(engine.eligibleWordCount) 词")
                    .foregroundStyle(.white.opacity(0.3))
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 7 * s, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .font(.system(size: 10.5 * s, weight: .medium))
        .padding(.horizontal, 8 * s)
        .padding(.vertical, 3.5 * s)
        .background(Capsule().fill(Color.white.opacity(0.09)))
        .contentShape(Capsule())
    }

    // MARK: 主区域

    @ViewBuilder
    private func stage(_ s: CGFloat) -> some View {
        switch engine.phase {
        case .setup:
            Text(engine.notice ?? "选择强度后开始")
                .font(.system(size: 13 * s))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)

        case .idle:
            Text(engine.notice ?? "准备开始…")
                .font(.system(size: 13 * s))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)

        case .listening, .asking:
            askingStage(s)

        case .revealed:
            revealedStage(s)
        }
    }

    private func askingStage(_ s: CGFloat) -> some View {
        let listening = engine.phase == .listening
        return VStack(spacing: 10 * s) {
            if listening {
                // 听的时候横线仍然留在原位，用户已经填的内容不会消失
                HStack(spacing: 8 * s) {
                    Image(systemName: "ear")
                        .font(.system(size: 14 * s))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("正在听这一句…")
                        .font(.system(size: 16 * s, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity)
            } else if let hint = chineseHint {
                Text(hint)
                    .font(.system(size: 16 * s))
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity)
            }

            maskArea(s)

            Text(listening ? listeningHint : hintLine)
                .font(.system(size: 10 * s))
                .foregroundStyle(
                    listening
                        ? .white.opacity(0.34)
                        : (engine.verdict != nil
                            ? Color(red: 1.0, green: 0.6, blue: 0.55).opacity(0.85)
                            : .white.opacity(0.26))
                )
                .frame(maxWidth: .infinity)

            if !listening {
                mistakeFootnote(s)
            }
        }
    }

    /// 错题本练习时，回看上次错在哪里
    @ViewBuilder
    private func mistakeFootnote(_ s: CGFloat) -> some View {
        if let warning = mistakes.storageWarning {
            Text("⚠️ \(warning)")
                .font(.system(size: 9.5 * s))
                .foregroundStyle(Color(red: 1.0, green: 0.65, blue: 0.45).opacity(0.9))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        } else if engine.source == .mistakes,
                  let entry = engine.mistakeEntry(for: engine.current),
                  let last = entry.lastAttempt {
            Text("错题 ×\(entry.attemptCount) · 上次：\(last.inputSummary) · \(shortDate(last.submittedAt))")
                .font(.system(size: 9.5 * s))
                .foregroundStyle(.white.opacity(0.3))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    private var listeningHint: String {
        "唱完会自动暂停 · 已填 \(engine.filledBlankCount)/\(engine.blankWordCount)"
    }

    private func revealedStage(_ s: CGFloat) -> some View {
        VStack(spacing: 8 * s) {
            if let line = engine.revealed {
                CenteredFlow(spacing: 6 * s, lineSpacing: 3 * s) {
                    ForEach(Array(words(of: line.text).enumerated()), id: \.offset) { _, raw in
                        wordButton(raw, s: s)
                    }
                }
                .frame(maxWidth: .infinity)

                if let translation = translationText {
                    Text(translation)
                        .font(.system(size: 15 * s))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity)
                }
            }

            if let word = selectedWord {
                wordCard(word, s: s)
            } else {
                Text("点句子里的词，可以查含义")
                    .font(.system(size: 10 * s))
                    .foregroundStyle(.white.opacity(0.22))
            }

            if let verdict = engine.verdict, !verdict.isCorrect {
                diff(verdict, s)
            }

            mistakeFootnote(s)
        }
    }

    // MARK: 横线输入（可部分挖空）

    /// 一个展示单元：要么是露出来的提示词，要么是要填的空
    private struct Piece {
        var raw: String
        var chars: [Character]
        var isBlank: Bool
        /// 这个空当前已经输入的字符
        var typed: [Character]
        /// 是否是空格选中的那个空
        var active: Bool
    }

    private struct Mask {
        var pieces: [Piece]
        var blankCount: Int
        var eligibleCount: Int
    }

    private func buildMask() -> Mask {
        let raw = engine.current?.text ?? ""
        let words = PracticeBlanks.words(in: raw)
        let blanks = Set(engine.blankIndices)

        var pieces: [Piece] = []
        var ordinal = 0
        for (i, word) in words.enumerated() {
            let isBlank = blanks.contains(i) && word.isEligible
            var typed: [Character] = []
            var active = false
            if isBlank {
                typed = engine.typedChars(forBlank: ordinal)
                active = ordinal == engine.activeBlank
                ordinal += 1
            }
            pieces.append(
                Piece(
                    raw: word.raw,
                    chars: word.chars,
                    isBlank: isBlank,
                    typed: typed,
                    active: active
                )
            )
        }

        return Mask(
            pieces: pieces,
            blankCount: pieces.filter(\.isBlank).count,
            eligibleCount: pieces.filter { !$0.chars.isEmpty }.count
        )
    }

    private func maskArea(_ s: CGFloat) -> some View {
        let mask = buildMask()
        let shape = RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
        let fill = Color.white.opacity(0.07)
        let stroke = Color.white.opacity(0.12)

        return ZStack {
            if mask.blankCount == 0 {
                Text("这句没有可输入的字母")
                    .font(.system(size: 14 * s))
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                CenteredFlow(spacing: 11 * s, lineSpacing: 7 * s) {
                    ForEach(Array(mask.pieces.enumerated()), id: \.offset) { _, piece in
                        if piece.isBlank {
                            slotView(piece, s: s)
                        } else {
                            Text(piece.raw)
                                .font(.system(size: 20 * s, design: .rounded))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // 真正的输入框：文字与光标都透明，只负责接键盘。
            // 铺满整个横线区，点任意位置都能直接开始打字。
            if !preview {
                TextField("", text: $engine.input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20 * s, design: .monospaced))
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .focused($inputFocused)
                    .onSubmit {
                        engine.submit()
                        clearFieldSelection()
                    }
                    // 输入框故意缩成 1×1：文字由上面的横线自己画，输入框只负责接键盘。
                    // 这样无论回车后系统怎么选中文字，都不会再露出白色选中条。
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 30 * s)
        .padding(.horizontal, 12 * s)
        .padding(.vertical, 4 * s)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(stroke, lineWidth: 1))
        .contentShape(shape)
        .onTapGesture { inputFocused = true }
    }

    /// 提交后输入框会被系统全选（透明输入框 => 只剩一条白条，且下次输入会覆盖原内容）。
    /// 这里把选区收回到末尾，让用户可以接着改。
    private func clearFieldSelection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
            let end = (editor.string as NSString).length
            editor.setSelectedRange(NSRange(location: end, length: 0))
        }
    }

    /// 当前选中的空加一层浅底，空格切换时一眼能看到跳到哪了
    private func slotView(_ piece: Piece, s: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
        return slotText(piece, s: s)
            .padding(.horizontal, 3 * s)
            .padding(.vertical, 1 * s)
            .background(shape.fill(Color.white.opacity(piece.active ? 0.09 : 0)))
    }

    /// 一个空：已输入的字母逐字着色，未输入的画下划线
    private func slotText(_ piece: Piece, s: CGFloat) -> Text {
        var output = Text("")
        for (i, expected) in piece.chars.enumerated() {
            let text: String
            let color: Color

            if i < piece.typed.count {
                let typed = piece.typed[i]
                text = String(typed)
                color = typed == expected
                    ? Color(red: 0.45, green: 0.86, blue: 0.55)
                    : Color(red: 1.0, green: 0.45, blue: 0.45)
            } else {
                text = "_"
                color = piece.active
                    ? Color.white.opacity(0.8)
                    : Color.white.opacity(0.22)
            }
            output = output + Text(text).foregroundColor(color)
        }
        // 多打出来的字母仍然标红，别让它们悄悄消失
        if piece.typed.count > piece.chars.count {
            output = output + Text(String(piece.typed[piece.chars.count...]))
                .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
        }
        return output.font(.system(size: 20 * s, design: .monospaced))
    }

    // MARK: 点词查义

    private func words(of text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// 去掉首尾标点并转小写后再查，避免 `world,` / `World` 查不到
    private func lookupKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet.letters.inverted).lowercased()
    }

    private func wordButton(_ raw: String, s: CGFloat) -> some View {
        let key = lookupKey(raw)
        let selected = selectedWord == key && !key.isEmpty

        return Button {
            guard !key.isEmpty else { return }
            if selected {
                selectedWord = nil
            } else {
                selectedWord = key
                translator.requestWord(key)
            }
        } label: {
            Text(raw)
                .font(.system(size: 21 * s, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.white : .white.opacity(0.9))
                .padding(.horizontal, 4 * s)
                .padding(.vertical, 1.5 * s)
                .background(
                    RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.16 : 0))
                )
        }
        .buttonStyle(.plain)
    }

    private func wordCard(_ word: String, s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3 * s) {
            Text(word)
                .font(.system(size: 15 * s, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            if let meaning = translator.translation(for: word), !meaning.isEmpty {
                Text(meaning)
                    .font(.system(size: 14 * s))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("查询中…")
                    .font(.system(size: 12 * s))
                    .foregroundStyle(.white.opacity(0.32))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11 * s)
        .padding(.vertical, 8 * s)
        .background(
            RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: 差异对照

    private func diff(_ verdict: DictationJudge.Result, _ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            HStack(alignment: .top, spacing: 8 * s) {
                label("原文", s)
                wordLine(verdict.tokens, expectedSide: true, s: s)
            }
            HStack(alignment: .top, spacing: 8 * s) {
                label("你的", s)
                wordLine(verdict.tokens, expectedSide: false, s: s)
            }
        }
        .padding(9 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func label(_ text: String, _ s: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10 * s))
            .foregroundStyle(.white.opacity(0.3))
            .frame(width: 26 * s, alignment: .leading)
            .padding(.top, 3 * s)
    }

    /// 原文里把没填出来的词画成横线（答案在上面已经露出来了），输入里把错词标红
    private func wordLine(_ tokens: [DictationJudge.Token], expectedSide: Bool, s: CGFloat) -> Text {
        var output = Text("")
        var first = true

        for token in tokens {
            let word: String?
            let color: Color
            if expectedSide {
                if token.matched {
                    word = token.expected
                    color = Color.white.opacity(0.55)
                } else if let expected = token.expected {
                    // 没填出来的位置只留一条横线，不再用绿色把答案重复一遍
                    let count = max(2, DictationJudge.comparisonChars(expected).count)
                    word = String(repeating: "_", count: count)
                    color = Color.white.opacity(0.42)
                } else {
                    word = nil
                    color = .clear
                }
            } else {
                word = token.actual
                color = token.matched
                    ? Color.white.opacity(0.55)
                    : Color(red: 1.0, green: 0.45, blue: 0.45)
            }

            guard let word else { continue }
            if !first { output = output + Text(" ") }
            output = output + Text(word).foregroundColor(color)
            first = false
        }
        return output.font(.system(size: 13 * s, design: .rounded))
    }

    // MARK: 底部动作

    @ViewBuilder
    private func actions(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            switch engine.phase {
            case .asking:
                if engine.isSongMode {
                    capsule("重听 ⌘R", s, emphasized: true, key: "r") { engine.replay() }
                }
                capsule("看答案 ⌘E", s, key: "e") { engine.giveUp() }
                capsule("跳过 ⌘.", s, key: ".") { engine.skip() }
            case .listening:
                capsule("重听 ⌘R", s, emphasized: true, key: "r") { engine.replay() }
                capsule("跳过 ⌘.", s, key: ".") { engine.skip() }
            case .revealed:
                capsule("再试试 ⌘T", s, key: "t") { engine.retryAfterReveal() }
                capsule("下一句 ⏎", s, emphasized: true, key: .return, modifiers: []) { engine.next() }
            case .idle:
                if engine.stats.correct + engine.stats.wrong > 0 {
                    capsule("再来一遍 ⏎", s, emphasized: true, key: .return, modifiers: []) {
                        engine.restartSession()
                    }
                }
                capsule("重新选择", s, emphasized: engine.stats.correct + engine.stats.wrong == 0) {
                    engine.returnToSetup()
                }
            case .setup:
                EmptyView()
            }

            Spacer(minLength: 0)

            capsule("退出 ⎋", s) { settings.practiceMode = false }
        }
    }

    private func capsule(
        _ title: String,
        _ s: CGFloat,
        emphasized: Bool = false,
        key: KeyEquivalent? = nil,
        modifiers: EventModifiers = .command,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Text(title)
                .font(.system(size: 11.5 * s, weight: .medium))
                .padding(.horizontal, 12 * s)
                .padding(.vertical, 6 * s)
                .background(
                    Capsule().fill(Color.white.opacity(emphasized ? 0.2 : 0.1))
                )
                .foregroundStyle(.white.opacity(emphasized ? 0.95 : 0.75))
        }
        .buttonStyle(.plain)

        return Group {
            if let key {
                button.keyboardShortcut(key, modifiers: modifiers)
            } else {
                button
            }
        }
    }

    // MARK: 收藏

    @ViewBuilder
    private func favoriteButton(_ s: CGFloat) -> some View {
        if let question = engine.current {
            let added = bank.contains(text: question.text, title: question.title)
            Button {
                bank.toggle(
                    text: question.text,
                    translation: engine.translation(for: question),
                    title: question.title,
                    artist: question.artist,
                    lineTime: question.lineTime ?? 0
                )
            } label: {
                Image(systemName: added ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 11 * s, weight: .semibold))
                    .foregroundStyle(added
                        ? Color(red: 0.41, green: 0.83, blue: 0.57)
                        : .white.opacity(0.45))
                    .frame(width: 21 * s, height: 21 * s)
                    .background(Circle().fill(Color.white.opacity(added ? 0.1 : 0.05)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(added ? "已收藏，点击取消" : "收藏这句歌词")
        }
    }

    // MARK: 文案

    /// 答题阶段的语义提示：让用户从中文回想英文
    private var chineseHint: String? {
        guard settings.showTranslation else { return nil }
        guard let text = engine.translation(for: engine.current), !text.isEmpty else { return nil }
        return text
    }

    private var translationText: String? {
        guard let text = engine.translation(for: engine.revealed), !text.isEmpty else { return nil }
        return text
    }

    private var hintLine: String {
        if engine.verdict?.isCorrect == false {
            return engine.isSongMode
                ? "✗ 有几个字母听错了 · 改一改，或按 ⌘R 重听"
                : "✗ 有几个字母听错了 · 改一改再提交"
        }
        if engine.input.contains(where: { !$0.isASCII && !$0.isWhitespace }) {
            return "⌘Space 切换到英文输入法"
        }
        var parts: [String] = []
        if engine.isRetry { parts.append("重试 · 不计分") }
        parts.append("空格切换横线")
        parts.append("已填 \(engine.filledBlankCount)/\(engine.blankWordCount)")
        parts.append("⏎ 提交")
        if engine.isSongMode { parts.append("⌘R 重听") }
        if !engine.isSongMode { parts.append("无音频 · 不可重听") }
        parts.append("⎋ 退出")
        return parts.joined(separator: " · ")
    }
}

/// 居中换行布局：逐词点击 / 逐空输入都需要每行各自居中
struct CenteredFlow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    private func lines(_ subviews: LayoutSubviews, maxWidth: CGFloat) -> [[CGSize]] {
        var result: [[CGSize]] = []
        var current: [CGSize] = []
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.isEmpty ? size.width : width + spacing + size.width
            if needed > maxWidth, !current.isEmpty {
                result.append(current)
                current = [size]
                width = size.width
            } else {
                current.append(size)
                width = needed
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 400
        let rows = lines(subviews, maxWidth: maxWidth)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            height += row.map(\.height).max() ?? 0
            if index > 0 { height += lineSpacing }
        }
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = lines(subviews, maxWidth: bounds.width)
        var y = bounds.minY
        var index = 0

        for row in rows {
            let rowWidth = row.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, row.count - 1))
            let rowHeight = row.map(\.height).max() ?? 0
            var x = bounds.minX + (bounds.width - rowWidth) / 2

            for size in row {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
                index += 1
            }
            y += rowHeight + lineSpacing
        }
    }
}
