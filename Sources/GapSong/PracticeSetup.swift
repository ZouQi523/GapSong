import SwiftUI
import AppKit

/// 练习设置：只保留填写比例。
///
/// 题目来源由键盘菜单的练习入口带入（`练当前歌曲 / 练收藏歌词 / 练错题本`），
/// 这个页面不再放来源、预览、滑杆和音效开关：
/// `2` 减少比例、`3` 增加比例（30%–100% 的预设档位），`4` 开始、`7` 返回、`1` 菜单。
struct PracticeSetupView: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var settings: Settings
    @ObservedObject var engine: PracticeEngine
    @ObservedObject var bank: QuestionBank
    @ObservedObject var mistakes: MistakeBook
    /// 1 菜单键：键盘和底部按钮共用同一个入口
    var onOpenMenu: () -> Void

    private var ratio: Double { settings.practiceRatio }

    /// 来源放在引擎里：菜单入口带入，`4 开始` 与界面共用同一份选择
    private var source: PracticeEngine.Source { engine.setupSource }

    private var choices: [Double] { Settings.practiceRatioChoices }

    init(
        state: PlayerState,
        settings: Settings,
        engine: PracticeEngine,
        bank: QuestionBank,
        mistakes: MistakeBook,
        onOpenMenu: @escaping () -> Void = {}
    ) {
        self.state = state
        self.settings = settings
        self.engine = engine
        self.bank = bank
        self.mistakes = mistakes
        self.onOpenMenu = onOpenMenu
    }

    var body: some View {
        GeometryReader { geo in
            let s = scale(for: geo.size)
            VStack(spacing: 0) {
                header(s)
                if let warning = bank.storageWarning ?? mistakes.storageWarning {
                    StorageWarningBanner(text: warning)
                        .padding(.top, 6 * s)
                }
                Spacer(minLength: 8 * s)
                center(s)
                Spacer(minLength: 8 * s)
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

    /// 菜单「字号」的正文系数（默认 24 = 1）：只让提示句跟着变；
    /// 比例数字和 2/3 按键保持窗口缩放，避免 72 号字把整页撑爆。
    private var fontFactor: CGFloat { Settings.practiceFontFactor(settings.fontSize) }

    // MARK: 顶部

    private func header(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Color.clear.frame(width: 30 * s, height: 1)   // 给左上角关闭按钮留位
            Text("开始练习")
                .font(.system(size: PracticeStyle.body(s, factor: fontFactor, base: 15), weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 8)
            sourceBadge(s)
        }
    }

    /// 只显示这次会练哪个来源，不在页面上做来源选择
    private func sourceBadge(_ s: CGFloat) -> some View {
        HStack(spacing: 4 * s) {
            Image(systemName: iconName(source))
                .font(.system(size: max(9, 9 * s), weight: .semibold))
            Text(sourceBadgeText)
                .font(.system(size: PracticeStyle.caption(s, base: 10), weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8 * s)
        .padding(.vertical, 3 * s)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .foregroundStyle(PracticeStyle.Ink.secondary)
    }

    private func iconName(_ value: PracticeEngine.Source) -> String {
        switch value {
        case .song: return "music.note"
        case .bank: return "bookmark"
        case .mistakes: return "exclamationmark.bubble"
        }
    }

    private var sourceBadgeText: String {
        switch source {
        case .song:
            let count = engine.songPracticeLineCount
            let title = state.snapshot?.track.title ?? ""
            return title.isEmpty ? "当前歌曲 · \(count) 句" : "\(title) · \(count) 句"
        case .bank:
            return "收藏歌词 · \(bank.count) 句"
        case .mistakes:
            return "错题本 · \(mistakes.count) 条"
        }
    }

    // MARK: 比例

    private func center(_ s: CGFloat) -> some View {
        VStack(spacing: 9 * s) {
            Text("填写比例")
                .font(.system(size: PracticeStyle.caption(s, base: 10.5), weight: .medium))
                .foregroundStyle(PracticeStyle.Ink.tertiary)

            Text(Settings.ratioLabel(ratio))
                .font(.system(size: max(34, 40 * s), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PracticeStyle.Ink.primary)
                .contentTransition(.numericText())

            // 页面唯一一句解释
            Text("填写比例越高，难度越大")
                .font(.system(size: PracticeStyle.body(s, factor: min(fontFactor, 1.5), base: 13.5)))
                .foregroundStyle(PracticeStyle.Ink.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10 * s) {
                ratioKey("2", "减少", enabled: canDecrease, s: s) {
                    engine.adjustSetupRatio(by: -1)
                }
                ratioKey("3", "增加", enabled: canIncrease, s: s) {
                    engine.adjustSetupRatio(by: 1)
                }
            }
            .padding(.top, 4 * s)

            // 空来源时才显示的必要提示；正常情况下只有上面那一句
            if !canStart, let hint = footerHint {
                Text(hint)
                    .font(.system(size: PracticeStyle.hint(s, factor: fontFactor, base: 10)))
                    .foregroundStyle(PracticeStyle.Ink.warn)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 数字键提示同时是按钮：鼠标用户也能看到并点
    private func ratioKey(
        _ key: String,
        _ title: String,
        enabled: Bool,
        s: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6 * s) {
                Text(key)
                    .font(.system(size: max(11, 12 * s), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(enabled ? Color.white.opacity(0.95) : Color.white.opacity(0.3))
                    .frame(width: 24 * s, height: 24 * s)
                    .background(Circle().fill(Color.white.opacity(enabled ? 0.14 : 0.04)))
                Text(title)
                    .font(.system(size: PracticeStyle.control(s, base: 11.5), weight: .medium))
                    .foregroundStyle(enabled ? PracticeStyle.Ink.secondary : Color.white.opacity(0.3))
            }
            .padding(.horizontal, 10 * s)
            .padding(.vertical, 5 * s)
            .background(Capsule().fill(Color.white.opacity(enabled ? 0.07 : 0.03)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var canDecrease: Bool {
        ratio > (choices.first ?? 0.3) + 0.001
    }

    private var canIncrease: Bool {
        ratio < (choices.last ?? 1.0) - 0.001
    }

    // MARK: 底部

    private func footer(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Spacer(minLength: 6)
            capsule("1 菜单", s) { onOpenMenu() }
            if let title = engine.commandTitle(.exitPractice) {
                capsule(title, s) { engine.perform(.exitPractice) }
            }
            capsule(
                engine.commandTitle(.primary) ?? "4 开始",
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
        case .bank: return "收藏还是空的：全文模式点歌词右侧书签"
        case .mistakes: return "错题本还是空的：先提交一个错误答案"
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
}
