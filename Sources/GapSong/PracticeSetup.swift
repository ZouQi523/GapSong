import SwiftUI
import AppKit

/// 练习设置：选择填空比例（30%–100%）与题目来源，预览挖空效果后开始
struct PracticeSetupView: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var settings: Settings
    @ObservedObject var engine: PracticeEngine
    @ObservedObject var bank: QuestionBank
    @ObservedObject var mistakes: MistakeBook

    @State private var ratio: Double
    @State private var source: PracticeEngine.Source

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

        let songCount = Self.songLineCount(state: state)
        _ratio = State(initialValue: settings.practiceRatio)
        if songCount > 0 {
            _source = State(initialValue: .song)
        } else if bank.count > 0 {
            _source = State(initialValue: .bank)
        } else {
            _source = State(initialValue: mistakes.count > 0 ? .mistakes : .song)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let s = scale(for: geo.size)
            VStack(alignment: .leading, spacing: 10 * s) {
                header(s)
                Divider().overlay(Color.white.opacity(0.08))
                intensity(s)
                previewBlock(s)
                sourcePicker(s)
                collectHint(s)
                Spacer(minLength: 0)
                footer(s)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .onChange(of: ratio) { _, newValue in
            settings.practiceRatio = newValue
        }
        .onExitCommand {
            settings.practiceMode = false
        }
    }

    private func scale(for size: CGSize) -> CGFloat {
        guard size.width > 1, size.height > 1 else { return 1 }
        let base = min(size.width / 720, size.height / 380)
        return min(max(base, 0.85), 1.45)
    }

    // MARK: 顶部

    private func header(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Color.clear.frame(width: 30 * s, height: 1)   // 给左上角关闭按钮留位
            VStack(alignment: .leading, spacing: 2 * s) {
                Text("开始练习")
                    .font(.system(size: 15 * s, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("先选听写强度：挖空的词越多越难")
                    .font(.system(size: 10.5 * s))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 0)
            if let snap = state.snapshot {
                Text("\(snap.track.title) · \(snap.track.artist)")
                    .font(.system(size: 10 * s))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
            }
        }
    }

    // MARK: 强度

    private func intensity(_ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7 * s) {
            HStack(alignment: .firstTextBaseline, spacing: 8 * s) {
                Text("填写比例")
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(Settings.ratioLabel(ratio))
                    .font(.system(size: 22 * s, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.95))
                    .contentTransition(.numericText())
                Text(difficultyLabel)
                    .font(.system(size: 10 * s, weight: .medium))
                    .padding(.horizontal, 7 * s)
                    .padding(.vertical, 2 * s)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
                Text("这句要填 \(previewBlankCount) / \(previewEligibleCount) 个词")
                    .font(.system(size: 10 * s))
                    .foregroundStyle(.white.opacity(0.3))
                    .monospacedDigit()
            }

            intensitySlider(s)

            HStack(spacing: 6 * s) {
                ForEach(Settings.practiceRatioChoices, id: \.self) { value in
                    Button {
                        ratio = value
                    } label: {
                        Text(Settings.ratioLabel(value))
                            .font(.system(size: 10 * s, weight: .medium))
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
                            .foregroundStyle(.white.opacity(abs(value - ratio) < 0.001 ? 0.95 : 0.55))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Text("30% 轻松 · 100% 整句听写")
                    .font(.system(size: 9.5 * s))
                    .foregroundStyle(.white.opacity(0.25))
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
                .font(.system(size: 17 * s, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            if let translation = sampleTranslation {
                Text(translation)
                    .font(.system(size: 12 * s))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("预览 · \(sampleSourceLabel)")
                .font(.system(size: 9 * s))
                .foregroundStyle(.white.opacity(0.22))
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
        case .bank: return "收藏歌词还是空的：播放时点歌词右侧的书签收藏"
        case .mistakes: return "错题本还是空的：提交错误答案后会自动记录"
        }
    }

    private func sourcePicker(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Text("题目来源")
                .font(.system(size: 12 * s, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

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
        if abs(value - ratio) > 0.0001 { ratio = value }
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
            guard available else { return }
            source = value
        } label: {
            HStack(spacing: 5 * s) {
                Image(systemName: iconName(value))
                    .font(.system(size: 9 * s, weight: .semibold))
                Text(title)
                    .font(.system(size: 11 * s, weight: .medium))
                Text(detail)
                    .font(.system(size: 9.5 * s).monospacedDigit())
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
            .foregroundStyle(.white.opacity(available ? (selected ? 0.95 : 0.6) : 0.25))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .help(available ? "" : emptyHelp(value))
    }

    private func collectHint(_ s: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 6 * s) {
            Image(systemName: "bookmark")
                .font(.system(size: 10 * s, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 1 * s)
            Text("正常播放时，把鼠标移到任意一句歌词右侧的书签上就能收藏；收藏的句子会出现在「收藏歌词」里，不播音乐也能反复练。")
                .font(.system(size: 9.5 * s))
                .foregroundStyle(.white.opacity(0.32))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 底部

    private func footer(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Text(footerHint)
                .font(.system(size: 9.5 * s))
                .foregroundStyle(.white.opacity(0.3))
                .lineLimit(2)
            Spacer(minLength: 0)
            capsule("退出 ⎋", s) { settings.practiceMode = false }
            capsule("开始练习 ⏎", s, emphasized: true, enabled: canStart) {
                engine.begin(source: source, ratio: ratio)
            }
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private var footerHint: String {
        switch source {
        case .bank:
            return "收藏歌词不依赖音乐：随时都能练，题目会打乱顺序"
        case .mistakes:
            return "错题本是离线文本练习：不播放、不控制音乐，也没有重听"
        case .song:
            if songCount > 0 {
                return "练习会控制「音乐」：唱到句末自动暂停，回到句首再听一遍"
            }
            return "播放一首英文歌，或先把喜欢的句子加进收藏"
        }
    }

    private var canStart: Bool {
        switch source {
        case .song: return songCount > 0
        case .bank: return bank.count > 0
        case .mistakes: return mistakes.count > 0
        }
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
                .font(.system(size: 11.5 * s, weight: .medium))
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
