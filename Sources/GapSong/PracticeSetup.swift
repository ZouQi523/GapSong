import SwiftUI
import AppKit

/// 练习设置：选择填空比例（30%–100%）与题目来源，预览挖空效果后开始
struct PracticeSetupView: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var settings: Settings
    @ObservedObject var engine: PracticeEngine
    @ObservedObject var bank: QuestionBank
    @ObservedObject var mistakes: MistakeBook

    /// 强度只以 settings 为准：右键菜单改过强度后，这里不会用陈旧的本地值覆盖它
    private var ratio: Double { settings.practiceRatio }

    /// 来源放在引擎里：可见按钮与数字键 3「开始」共用同一份选择
    private var source: PracticeEngine.Source { engine.setupSource }

    init(
        state: PlayerState,
        settings: Settings,
        engine: PracticeEngine,
        bank: QuestionBank,
        mistakes: MistakeBook
    ) {
        self.state = state
        self.settings = settings
        self.engine = engine
        self.bank = bank
        self.mistakes = mistakes
    }

    var body: some View {
        GeometryReader { geo in
            let s = scale(for: geo.size)
            // 只有内容滚动；「开始 / 返回」固定在底部，不会被长预览或大字号推走
            VStack(spacing: 10 * s) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 10 * s) {
                        header(s)
                        Divider().overlay(Color.white.opacity(0.08))
                        if let warning = bank.storageWarning ?? mistakes.storageWarning {
                            StorageWarningBanner(text: warning)
                        }
                        intensity(s)
                        previewBlock(s)
                        sourcePicker(s)
                        soundToggle(s)
                    }
                    .frame(minWidth: geo.size.width, alignment: .topLeading)
                    .padding(.bottom, 4 * s)
                }
                .scrollBounceBehavior(.basedOnSize)

                footer(s)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .onExitCommand {
            engine.exitPractice()
        }
    }

    private func scale(for size: CGSize) -> CGFloat {
        guard size.width > 1, size.height > 1 else { return 1 }
        let base = min(size.width / 720, size.height / 400)
        return min(max(base, 0.7), 1.45)
    }

    /// 菜单「字号」的正文系数（默认 24 = 1）：只让预览句/译文和提示文案跟着变，
    /// 比例滑杆、来源胶囊、按钮仍按窗口缩放，窄窗里不会被字号撑到横向裁切。
    private var fontFactor: CGFloat { Settings.practiceFontFactor(settings.fontSize) }

    // MARK: 顶部

    private func header(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Color.clear.frame(width: 30 * s, height: 1)   // 给左上角关闭按钮留位
            Text("开始练习")
                .font(.system(size: PracticeStyle.body(s, factor: fontFactor, base: 15), weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
            if let snap = state.snapshot {
                Text("\(snap.track.title) · \(snap.track.artist)")
                    .font(.system(size: PracticeStyle.caption(s, base: 10)))
                    .foregroundStyle(PracticeStyle.Ink.tertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: 强度

    private func intensity(_ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7 * s) {
            HStack(alignment: .firstTextBaseline, spacing: 8 * s) {
                Text("填写比例")
                    .font(.system(size: PracticeStyle.control(s, base: 12), weight: .medium))
                    .foregroundStyle(PracticeStyle.Ink.secondary)
                Text(Settings.ratioLabel(ratio))
                    .font(.system(size: 22 * s, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PracticeStyle.Ink.primary)
                    .contentTransition(.numericText())
                Text(difficultyLabel)
                    .font(.system(size: PracticeStyle.caption(s, base: 10), weight: .medium))
                    .padding(.horizontal, 7 * s)
                    .padding(.vertical, 2 * s)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .foregroundStyle(PracticeStyle.Ink.secondary)
                Spacer(minLength: 0)
                Text("\(previewBlankCount) / \(previewEligibleCount) 词")
                    .font(.system(size: PracticeStyle.caption(s, base: 10)))
                    .foregroundStyle(PracticeStyle.Ink.tertiary)
                    .monospacedDigit()
            }

            intensitySlider(s)

            HStack(spacing: 6 * s) {
                ForEach(Settings.practiceRatioChoices, id: \.self) { value in
                    Button {
                        settings.practiceRatio = value
                    } label: {
                        Text(Settings.ratioLabel(value))
                            .font(.system(size: PracticeStyle.control(s, base: 10), weight: .medium))
                            .monospacedDigit()
                            .padding(.horizontal, 8 * s)
                            .padding(.vertical, 3.5 * s)
                            .background(
                                Capsule().fill(
                                    abs(value - ratio) < 0.001
                                        ? Color.white.opacity(0.22)
                                        : Color.white.opacity(0.07)
                                )
                            )
                            .foregroundStyle(abs(value - ratio) < 0.001 ? PracticeStyle.Ink.primary : PracticeStyle.Ink.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var difficultyLabel: String {
        switch ratio {
        case ..<0.45: return "轻松"
        case ..<0.65: return "适中"
        case ..<0.9: return "偏难"
        default: return "整句"
        }
    }

    // MARK: 预览

    private func previewBlock(_ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5 * s) {
            Text(PracticeBlanks.maskedText(in: sampleText, ratio: ratio))
                .font(.system(size: PracticeStyle.body(s, factor: fontFactor, base: 17), weight: .medium, design: .rounded))
                .foregroundStyle(PracticeStyle.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let translation = sampleTranslation {
                Text(translation)
                    .font(.system(size: PracticeStyle.body(s, factor: fontFactor, base: 12)))
                    .foregroundStyle(PracticeStyle.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("预览 · \(sampleSourceLabel)")
                .font(.system(size: PracticeStyle.caption(s, base: 9)))
                .foregroundStyle(PracticeStyle.Ink.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12 * s)
        .padding(.vertical, 9 * s)
        .background(
            RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: 来源

    private func iconName(_ value: PracticeEngine.Source) -> String {
        switch value {
        case .song: return "music.note"
        case .bank: return "bookmark"
        case .mistakes: return "exclamationmark.bubble"
        }
    }

    private func emptyHelp(_ value: PracticeEngine.Source) -> String {
        switch value {
        case .song: return "这首歌没有可听写的英文句子"
        case .bank: return "收藏还是空的：全文模式点歌词右侧书签"
        case .mistakes: return "错题本还是空的"
        }
    }

    private func sourcePicker(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Text("题目来源")
                .font(.system(size: PracticeStyle.control(s, base: 12), weight: .medium))
                .foregroundStyle(PracticeStyle.Ink.secondary)

            sourceChip(.song, title: "当前歌曲", detail: "\(songCount) 句", s: s)
            sourceChip(.bank, title: "收藏歌词", detail: "\(bank.count) 句", s: s)
            sourceChip(.mistakes, title: "错题本", detail: "\(mistakes.count) 条", s: s)

            Spacer(minLength: 0)
        }
    }

    /// 自绘滑杆：系统 Slider 是 AppKit 控件，离屏预览画不出来
    private func intensitySlider(_ s: CGFloat) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = CGFloat((ratio - 0.3) / 0.7)
            let knob = 11 * s

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 4 * s)
                Capsule()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: max(4 * s, width * fraction), height: 4 * s)
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: knob, height: knob)
                    .offset(x: min(max(width * fraction - knob / 2, 0), width - knob))
            }
            .frame(height: 20 * s)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    setRatio(x: value.location.x, width: width)
                }
            )
        }
        .frame(height: 20 * s)
    }

    private func setRatio(x: CGFloat, width: CGFloat) {
        guard width > 1 else { return }
        let clampedX = min(max(x, 0), width)
        let raw = 0.3 + (clampedX / width) * 0.7
        let snapped = (raw * 20).rounded() / 20
        let value = min(max(snapped, 0.3), 1.0)
        if abs(value - settings.practiceRatio) > 0.0001 { settings.practiceRatio = value }
    }

    private func sourceChip(
        _ value: PracticeEngine.Source,
        title: String,
        detail: String,
        s: CGFloat
    ) -> some View {
        let available: Bool
        switch value {
        case .song: available = songCount > 0
        case .bank: available = bank.count > 0
        case .mistakes: available = mistakes.count > 0
        }
        let selected = source == value

        return Button {
            engine.selectSetupSource(value)
        } label: {
            HStack(spacing: 5 * s) {
                Image(systemName: iconName(value))
                    .font(.system(size: max(9, 9 * s), weight: .semibold))
                Text(title)
                    .font(.system(size: PracticeStyle.control(s, base: 11), weight: .medium))
                Text(detail)
                    .font(.system(size: PracticeStyle.caption(s, base: 9.5)).monospacedDigit())
                    .foregroundStyle(.white.opacity(selected ? 0.55 : 0.3))
            }
            .padding(.horizontal, 10 * s)
            .padding(.vertical, 5 * s)
            .background(
                RoundedRectangle(cornerRadius: 7 * s, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.18 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7 * s, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(selected ? 0.28 : 0.08),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(available ? (selected ? PracticeStyle.Ink.primary : PracticeStyle.Ink.secondary) : PracticeStyle.Ink.faint)
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .help(available ? "" : emptyHelp(value))
    }

    private func soundToggle(_ s: CGFloat) -> some View {
        Button {
            settings.typingSound.toggle()
        } label: {
            HStack(spacing: 6 * s) {
                Image(systemName: settings.typingSound ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.system(size: max(10, 10 * s), weight: .semibold))
                Text("打字机音效")
                    .font(.system(size: PracticeStyle.control(s, base: 11), weight: .medium))
                Text(settings.typingSound ? "已开" : "已关")
                    .font(.system(size: PracticeStyle.caption(s, base: 9.5), weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(settings.typingSound ? 0.8 : 0.4))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10 * s)
            .padding(.vertical, 5 * s)
            .background(
                RoundedRectangle(cornerRadius: 7 * s, style: .continuous)
                    .fill(Color.white.opacity(settings.typingSound ? 0.14 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7 * s, style: .continuous)
                    .strokeBorder(Color.white.opacity(settings.typingSound ? 0.22 : 0.07), lineWidth: 1)
            )
            .foregroundStyle(PracticeStyle.Ink.secondary)
        }
        .buttonStyle(.plain)
        .help(settings.typingSound ? "关闭打字机音效" : "打开打字机音效（本地合成，不联网）")
    }

    // MARK: 底部

    private func footer(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            // 只在空来源时留一句必要提示；其余留白，不再常驻解释
            if let hint = footerHint {
                Text(hint)
                    .font(.system(size: PracticeStyle.hint(s, factor: fontFactor, base: 9.5)))
                    .foregroundStyle(PracticeStyle.Ink.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            if let title = engine.commandTitle(.exitPractice) {
                capsule(title, s) { engine.perform(.exitPractice) }
            }
            capsule(
                engine.commandTitle(.primary) ?? "3 开始",
                s,
                emphasized: true,
                enabled: canStart
            ) {
                engine.perform(.primary)
            }
            .keyboardShortcut(.return, modifiers: [])
        }
        // 右下角缩放手柄不吃按钮：给固定操作区留出尾部空间
        .padding(.trailing, 8)
    }

    private var footerHint: String? {
        guard !canStart else { return nil }
        switch source {
        case .song: return "先播放英文歌，或收藏句子"
        case .bank: return "全文模式点歌词右侧书签"
        case .mistakes: return "答错后自动进错题本"
        }
    }

    private var canStart: Bool {
        engine.canUseSource(source)
    }

    private func capsule(
        _ title: String,
        _ s: CGFloat,
        emphasized: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: PracticeStyle.control(s), weight: .medium))
                .padding(.horizontal, 12 * s)
                .padding(.vertical, 6 * s)
                .background(
                    Capsule().fill(Color.white.opacity(emphasized ? 0.22 : 0.1))
                )
                .foregroundStyle(
                    .white.opacity(enabled ? (emphasized ? 0.95 : 0.75) : 0.25)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: 数据

    private var songCount: Int { Self.songLineCount(state: state) }

    private static func songLineCount(state: PlayerState) -> Int {
        guard let lyrics = state.lyrics, !lyrics.lines.isEmpty else { return 0 }
        return PracticeFilter.practiceableIndices(
            lines: lyrics.lines,
            trackDuration: state.snapshot?.track.duration ?? 0
        ).count
    }

    private var sampleText: String {
        if source == .mistakes, let first = mistakes.recentEntries.first {
            return first.text
        }
        if source == .bank, let first = bank.items.first {
            return first.text
        }
        if let lyrics = state.lyrics, !lyrics.lines.isEmpty {
            let indices = PracticeFilter.practiceableIndices(
                lines: lyrics.lines,
                trackDuration: state.snapshot?.track.duration ?? 0
            )
            if let first = indices.first {
                return lyrics.lines[first].text
            }
        }
        if let first = bank.items.first {
            return first.text
        }
        return DemoFixtures.firstLine
    }

    private var sampleSourceLabel: String {
        if source == .mistakes, !mistakes.entries.isEmpty { return "错题本" }
        if source == .bank, !bank.items.isEmpty { return "收藏歌词" }
        if state.lyrics != nil, songCount > 0 { return "当前歌曲" }
        if !bank.items.isEmpty { return "收藏歌词" }
        return "内置例句"
    }

    private var sampleTranslation: String? {
        if let text = state.translator.translation(for: sampleText), !text.isEmpty {
            return text
        }
        if let stored = bank.items.first(where: { $0.text == sampleText })?.translation,
           !stored.isEmpty {
            return stored
        }
        if let stored = mistakes.entries.first(where: { $0.text == sampleText })?.translation,
           !stored.isEmpty {
            return stored
        }
        if sampleText == DemoFixtures.firstLine { return DemoFixtures.firstTranslation }
        return nil
    }

    private var previewBlankCount: Int {
        PracticeBlanks.blankIndices(in: sampleText, ratio: ratio).count
    }

    private var previewEligibleCount: Int {
        PracticeBlanks.words(in: sampleText).filter(\.isEligible).count
    }
}
