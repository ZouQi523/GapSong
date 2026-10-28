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

    /// 离屏渲染画不了 AppKit 控件，预览时用 Text 顶替输入框
    @Environment(\.practicePreview) private var preview

    /// 点开释义的词（预览时可由外部预置）
    @State private var selectedWord: String?
    /// 每次 +1 让隐藏输入视图重新成为第一响应者（AppKit 视图不走 @FocusState）
    @State private var focusNonce = 0

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
            let s = PracticeStyle.windowScale(width: geo.size.width, height: geo.size.height)
            // 顶部来源/进度与底部数字操作各占固定区域；只有中间题面滚动。
            // 短内容在可用区域里水平+垂直居中，内容高于可用高度时从顶部正常滚动。
            VStack(spacing: 7 * s) {
                VStack(alignment: .leading, spacing: 6 * s) {
                    header(s)
                    storageWarnings()
                    scoreBar(s)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().overlay(Color.white.opacity(0.08))

                centerStage(s)

                speechNotice(s)
                issueActions(s)
                returnHint(s)
                actions(s)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .onChange(of: engine.phase) { _, newValue in
            selectedWord = nil
            // 换阶段就停掉上一句朗读，绝不把旧句读进下一屏
            engine.stopReading()
            if newValue == .asking || newValue == .listening {
                focusNonce += 1
            }
        }
        .onChange(of: engine.focusTick) { _, _ in
            focusNonce += 1
        }
        .onChange(of: engine.current?.id) { _, _ in
            selectedWord = nil
            engine.stopReading()
        }
        .onChange(of: engine.source) { _, _ in
            engine.stopReading()
        }
        .onAppear {
            if engine.phase == .asking || engine.phase == .listening {
                focusNonce += 1
            }
        }
        .onDisappear {
            // 退出练习/回设置页时不留后台朗读
            engine.stopReading()
        }
        // Esc 仍然兼容；主提示改用 6 返回
        .onExitCommand {
            engine.exitPractice()
        }
    }

    // MARK: 固定区域与居中题面

    /// 题面所在的中间区域：内容短时垂直居中，内容高于可用高度时从顶部滚动。
    private func centerStage(_ s: CGFloat) -> some View {
        GeometryReader { area in
            ScrollView(.vertical) {
                VStack(spacing: 9 * s) {
                    stage(s)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6 * s)
                .frame(minHeight: area.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// 菜单「字号」的正文系数（默认 24 = 1）。窗口缩放 `s` 仍然负责让内容
    /// 适配窗口；这个系数只叠加在正文/填空/提示的字号上。
    private var fontFactor: CGFloat { Settings.practiceFontFactor(settings.fontSize) }

    // MARK: 顶部

    private func header(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Color.clear.frame(width: max(14, 12 * s), height: 1)   // 给左上角关闭按钮留位

            if !engine.source.badge.isEmpty {
                Text(engine.source.badge)
                    .font(.system(size: PracticeStyle.caption(s, base: 9), weight: .semibold))
                    .padding(.horizontal, 5 * s)
                    .padding(.vertical, 1.5 * s)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .foregroundStyle(PracticeStyle.Ink.secondary)
            }

            Text(engine.sourceTitle.isEmpty ? "—" : engine.sourceTitle)
                .font(.system(size: PracticeStyle.caption(s, base: 11), weight: .medium))
                .foregroundStyle(PracticeStyle.Ink.secondary)
                .lineLimit(1)
            Text("·")
                .font(.system(size: PracticeStyle.caption(s, base: 11)))
                .foregroundStyle(.white.opacity(0.25))
            Text(engine.sourceArtist)
                .font(.system(size: PracticeStyle.caption(s, base: 11)))
                .foregroundStyle(PracticeStyle.Ink.muted)
                .lineLimit(1)

            Spacer(minLength: 8)

            if !engine.progress.isEmpty {
                Text(engine.progress)
                    .font(.system(size: PracticeStyle.caption(s, base: 10)).monospacedDigit())
                    .foregroundStyle(PracticeStyle.Ink.muted)
            }
        }
    }

    /// 收藏/错题写失败要在练习界面里看得见
    @ViewBuilder
    private func storageWarnings() -> some View {
        if let warning = bank.storageWarning ?? mistakes.storageWarning {
            StorageWarningBanner(text: warning)
        }
    }

    /// 积分、连对、以及可随时调整的填空强度
    private func scoreBar(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Text("\(engine.score)")
                .font(.system(size: 26 * s, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PracticeStyle.Ink.primary)
                .contentTransition(.numericText())

            Text("分")
                .font(.system(size: PracticeStyle.caption(s, base: 11)))
                .foregroundStyle(PracticeStyle.Ink.muted)
                .padding(.top, 7 * s)

            if engine.streak >= 2 {
                Text("连对 \(engine.streak)")
                    .font(.system(size: PracticeStyle.caption(s, base: 10), weight: .medium))
                    .padding(.horizontal, 7 * s)
                    .padding(.vertical, 2.5 * s)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .foregroundStyle(PracticeStyle.Ink.secondary)
                    .padding(.top, 4 * s)
            }

            if engine.isRetry {
                Text("重试 · 不计分")
                    .font(.system(size: PracticeStyle.caption(s, base: 10), weight: .medium))
                    .padding(.horizontal, 7 * s)
                    .padding(.vertical, 2.5 * s)
                    .background(Capsule().fill(Color.orange.opacity(0.16)))
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .padding(.top, 4 * s)
            }

            if engine.source == .mistakes {
                Text("错题 ×\(engine.mistakeAttemptCount(for: engine.current))")
                    .font(.system(size: PracticeStyle.caption(s, base: 10), weight: .medium))
                    .padding(.horizontal, 7 * s)
                    .padding(.vertical, 2.5 * s)
                    .background(Capsule().fill(Color.red.opacity(0.16)))
                    .foregroundStyle(PracticeStyle.Ink.error)
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
            .help("填空强度")
        }
    }

    private func ratioLabel(_ s: CGFloat) -> some View {
        HStack(spacing: 4 * s) {
            Text("填空 \(settings.practiceRatioLabel)")
                .foregroundStyle(PracticeStyle.Ink.primary)
            if engine.eligibleWordCount > 0 {
                Text("\(engine.blankWordCount)/\(engine.eligibleWordCount) 词")
                    .foregroundStyle(PracticeStyle.Ink.tertiary)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: max(8, 7 * s), weight: .bold))
                .foregroundStyle(PracticeStyle.Ink.tertiary)
        }
        .font(.system(size: PracticeStyle.control(s, base: 10.5), weight: .medium))
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
            Text(engine.notice ?? "准备开始")
                .font(.system(size: PracticeStyle.body(s, factor: fontFactor, base: 13)))
                .foregroundStyle(PracticeStyle.Ink.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

        case .idle:
            Text(engine.notice ?? "准备开始")
                .font(.system(size: PracticeStyle.body(s, factor: fontFactor, base: 13)))
                .foregroundStyle(PracticeStyle.Ink.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

        case .listening, .asking:
            askingStage(s)

        case .revealed:
            revealedStage(s)
        }
    }

    private func askingStage(_ s: CGFloat) -> some View {
        let listening = engine.phase == .listening
        let issue = engine.playbackNotice
        let waiting = engine.isWaitingForLineEnd
        return VStack(spacing: 10 * s) {
            if let issue {
                // 播放/授权出问题时，界面必须说清原因，而不是永远停在「正在听」
                playbackIssueCard(issue, s)
            } else if waiting {
                // 已经提前填全对：明确说出「为什么还没切下一句」
                allCorrectWaitingBanner(s)
            } else if listening {
                // 听的时候横线仍然留在原位，用户已经填的内容不会消失
                HStack(spacing: 8 * s) {
                    Image(systemName: "ear")
                        .font(.system(size: max(12, 14 * s)))
                        .foregroundStyle(PracticeStyle.Ink.secondary)
                    Text("正在听这一句…")
                        .font(.system(size: PracticeStyle.body(s, factor: fontFactor, base: 16), weight: .medium))
                        .foregroundStyle(PracticeStyle.Ink.primary)
                }
                .frame(maxWidth: .infinity)
            } else if let hint = chineseHint {
                Text(hint)
                    .font(.system(size: PracticeStyle.body(s, factor: fontFactor, base: 16)))
                    .foregroundStyle(PracticeStyle.Ink.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }

            maskArea(s)

            if let coaching = engine.coaching {
                Text(coaching)
                    .font(.system(size: PracticeStyle.hint(s, factor: fontFactor, base: 10.5), weight: .medium))
                    .foregroundStyle(PracticeStyle.Ink.warn)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            } else if engine.verdict?.isCorrect == false {
                // 判错反馈必须保留，但只留一句
                Text("✗ 有几个字母听错了")
                    .font(.system(size: PracticeStyle.hint(s, factor: fontFactor, base: 10), weight: .medium))
                    .foregroundStyle(PracticeStyle.Ink.error)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if !listening {
                mistakeFootnote(s)
            }
        }
    }

    /// 句子已经全对、但音乐还没唱到句末：给出明确的等待原因和句级进度。
    /// 只有 LRC 的句首/句末两个锚点，不编造逐词时序。
    private func allCorrectWaitingBanner(_ s: CGFloat) -> some View {
        Text(PracticeEngine.allCorrectWaitingText)
            .font(.system(size: PracticeStyle.body(s, factor: fontFactor, base: 15), weight: .semibold))
            .foregroundStyle(PracticeStyle.Ink.mint)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2 * s)
    }

    /// 播放异常卡片：只提示和给动作，不自动恢复、不判失败。
    /// 缺权限时主操作是「打开系统设置」，其余异常主操作是重试/继续播放。
    private func playbackIssueCard(_ issue: PlaybackIssue, _ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            HStack(spacing: 6 * s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: max(10, 11 * s), weight: .semibold))
                    .foregroundStyle(PracticeStyle.Ink.warn)
                Text(issue.title)
                    .font(.system(size: PracticeStyle.body(s, factor: fontFactor, base: 13), weight: .semibold))
                    .foregroundStyle(PracticeStyle.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            Text(issue.detail)
                .font(.system(size: PracticeStyle.hint(s, factor: fontFactor, base: 10.5)))
                .foregroundStyle(PracticeStyle.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)

        }
        .padding(9 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private func openAutomationSettings() {
        guard !preview,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// 错题本练习时，回看上次错在哪里
    @ViewBuilder
    private func mistakeFootnote(_ s: CGFloat) -> some View {
        if engine.source == .mistakes,
                  let entry = engine.mistakeEntry(for: engine.current),
                  let last = entry.lastAttempt {
            Text("错题 ×\(entry.attemptCount) · 上次：\(last.inputSummary) · \(shortDate(last.submittedAt))")
                .font(.system(size: PracticeStyle.caption(s, base: 9.5)))
                .foregroundStyle(PracticeStyle.Ink.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
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
                        .font(.system(size: PracticeStyle.body(s, factor: fontFactor, base: 15)))
                        .foregroundStyle(PracticeStyle.Ink.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }

            if let word = selectedWord {
                wordCard(word, s: s)
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
        /// 这个空在 `blankIndices` 里的下标（非空为 nil），点击时用来选中
        var ordinal: Int?
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
            var pieceOrdinal: Int?
            if isBlank {
                typed = engine.typedChars(forBlank: ordinal)
                active = ordinal == engine.activeBlank
                pieceOrdinal = ordinal
                ordinal += 1
            }
            pieces.append(
                Piece(
                    raw: word.raw,
                    chars: word.chars,
                    isBlank: isBlank,
                    ordinal: pieceOrdinal,
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
                    .font(.system(size: PracticeStyle.body(s, factor: fontFactor, base: 14)))
                    .foregroundStyle(PracticeStyle.Ink.tertiary)
            } else {
                CenteredFlow(spacing: 11 * s, lineSpacing: 7 * s) {
                    ForEach(Array(mask.pieces.enumerated()), id: \.offset) { _, piece in
                        if piece.isBlank {
                            slotView(piece, s: s)
                        } else {
                            Text(piece.raw)
                                .font(.system(
                                    size: PracticeStyle.body(s, factor: fontFactor, base: 20),
                                    design: .rounded
                                ))
                                .foregroundStyle(PracticeStyle.Ink.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // 隐藏的 AppKit 输入视图：只负责接键盘和输入法。
            // 直接字母在 AppDelegate 的按键监听里逐字处理；这里保留输入法
            // 组字提交与粘贴的批量入口。缩成 1×1，文字全部由横线自己画。
            if !preview {
                PracticeInputSink(
                    engine: engine,
                    focusNonce: focusNonce,
                    onExit: { engine.exitPractice() }
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: max(28, 30 * s))
        .padding(.horizontal, 12 * s)
        .padding(.vertical, 4 * s)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(stroke, lineWidth: 1))
        .contentShape(shape)
        .onTapGesture { focusNonce += 1 }
    }

    /// 当前选中的空加一层浅底，空格/点击切换时一眼能看到跳到哪了
    private func slotView(_ piece: Piece, s: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
        return slotText(piece, s: s)
            .padding(.horizontal, 3 * s)
            .padding(.vertical, 1 * s)
            .background(shape.fill(Color.white.opacity(piece.active ? 0.09 : 0)))
            .contentShape(Rectangle())
            .onTapGesture {
                if let ordinal = piece.ordinal {
                    engine.selectBlank(ordinal)
                    focusNonce += 1
                }
            }
            .help(piece.active ? "当前要填的空" : "点击回到这个空（可修改前面的答案）")
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
        return output.font(.system(
            size: PracticeStyle.body(s, factor: fontFactor, base: 20),
            design: .monospaced
        ))
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
                .font(.system(
                    size: PracticeStyle.body(s, factor: fontFactor, base: 21),
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundStyle(selected ? Color.white : PracticeStyle.Ink.primary)
                .padding(.horizontal, 4 * s)
                .padding(.vertical, 1.5 * s)
                .background(
                    RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.16 : 0))
                )
        }
        .buttonStyle(.plain)
        .help("点词查看含义")
    }

    private func wordCard(_ word: String, s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3 * s) {
            Text(word)
                .font(.system(
                    size: PracticeStyle.body(s, factor: fontFactor, base: 15),
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundStyle(PracticeStyle.Ink.primary)

            if let meaning = translator.translation(for: word), !meaning.isEmpty {
                Text(meaning)
                    .font(.system(size: PracticeStyle.body(s, factor: fontFactor, base: 14)))
                    .foregroundStyle(PracticeStyle.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("查询中…")
                    .font(.system(size: PracticeStyle.hint(s, factor: fontFactor, base: 12)))
                    .foregroundStyle(PracticeStyle.Ink.tertiary)
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
            .font(.system(size: PracticeStyle.caption(s, base: 10)))
            .foregroundStyle(PracticeStyle.Ink.tertiary)
            .frame(width: 26 * s * fontFactor, alignment: .leading)
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
        return output.font(.system(
            size: PracticeStyle.body(s, factor: fontFactor, base: 13),
            design: .rounded
        ))
    }

    // MARK: 底部动作

    /// 播放异常时的恢复动作：固定在底部（数字按钮上方），不随卡片滚出屏幕。
    /// 恢复入口只出现这一处，卡片里不再重复。
    @ViewBuilder
    private func issueActions(_ s: CGFloat) -> some View {
        if let issue = engine.playbackNotice {
            WrapRowLayout(spacing: 6 * s, lineSpacing: 5 * s) {
                switch issue.primaryAction {
                case .openSettings:
                    capsule("打开系统设置", s, emphasized: true) { openAutomationSettings() }
                case .retry:
                    capsule(issue.retryActionLabel, s, emphasized: true) { engine.resumePlayback() }
                }
                if issue.offersSecondaryRetry {
                    capsule(issue.retryActionLabel, s) { engine.resumePlayback() }
                }
                if issue.suggestsStopping {
                    capsule("结束练习", s) { engine.stopSession() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
        }
    }

    /// 固定底部操作区。按钮与数字键 1…6 共用 engine 的动作判定：
    /// 主操作先换行，导航固定在右侧；内容再长也推不走它们。
    private func actions(_ s: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 8 * s) {
            WrapRowLayout(spacing: 8 * s, lineSpacing: 6 * s) {
                ForEach(PracticeCommand.primaryRow, id: \.self) { command in
                    if let title = engine.commandTitle(command) {
                        let shortcut = legacyShortcut(command)
                        capsule(
                            title,
                            s,
                            emphasized: command == .primary,
                            key: shortcut?.key,
                            modifiers: shortcut?.modifiers ?? .command
                        ) {
                            engine.perform(command)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6 * s) {
                ForEach(PracticeCommand.secondaryRow, id: \.self) { command in
                    if let title = engine.commandTitle(command) {
                        capsule(title, s) { engine.perform(command) }
                    }
                }
            }
        }
        // 右下角缩放手柄不吃按钮：给固定操作区留出尾部空间
        .padding(.trailing, 8)
    }

    /// 旧快捷键继续兼容，但界面只显示数字
    private func legacyShortcut(
        _ command: PracticeCommand
    ) -> (key: KeyEquivalent, modifiers: EventModifiers)? {
        switch command {
        case .primary:
            return (.return, [])
        case .replayOrRead:
            return engine.isSongMode ? ("r", .command) : nil
        case .revealOrRetry:
            if engine.phase == .asking { return ("e", .command) }
            if engine.phase == .revealed { return ("t", .command) }
            return nil
        case .skip:
            return (".", .command)
        case .backToSetup, .exitPractice:
            return nil
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
                .font(.system(size: PracticeStyle.control(s), weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, max(9, 12 * s))
                .padding(.vertical, max(5, 6 * s))
                .background(
                    Capsule().fill(Color.white.opacity(emphasized ? 0.20 : 0.10))
                )
                .foregroundStyle(emphasized ? PracticeStyle.Ink.primary : PracticeStyle.Ink.secondary)
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

    /// 答题阶段提交只走回车：固定区只留一句低调提示，不再放重复的提交按钮。
    /// 收听中/无题时不显示；字号沿用现有提示文字的可读标准。
    @ViewBuilder
    private func returnHint(_ s: CGFloat) -> some View {
        if engine.showsReturnHint {
            Text("回车继续")
                // 操作区是窗口 chrome：跟随窗口缩放、不随字号 72 放大，保持低调
                .font(.system(size: PracticeStyle.hint(s, base: 10)))
                .foregroundStyle(PracticeStyle.Ink.tertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 2)
        }
    }

    /// 没有英语音色时给一句短提示；下一题/重试会自动清掉
    @ViewBuilder
    private func speechNotice(_ s: CGFloat) -> some View {
        if let notice = engine.speechNotice {
            Text(notice)
                .font(.system(size: PracticeStyle.hint(s, factor: fontFactor, base: 10)))
                .foregroundStyle(PracticeStyle.Ink.warn)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .center)
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
}

/// 居中换行布局：逐词点击 / 逐空输入都需要每行各自居中
struct CenteredFlow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    /// 单个词在窄窗 + 大字号下可能比整行还宽：先按行宽重新测量，
    /// 让 Text 自己折行，而不是让整块内容横向溢出/被裁切。
    private func measured(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard maxWidth > 1, ideal.width > maxWidth else { return ideal }
        var size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        size.width = min(size.width, maxWidth)
        return size
    }

    private func lines(_ subviews: LayoutSubviews, maxWidth: CGFloat) -> [[CGSize]] {
        var result: [[CGSize]] = []
        var current: [CGSize] = []
        var width: CGFloat = 0

        for subview in subviews {
            let size = measured(subview, maxWidth: maxWidth)
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
