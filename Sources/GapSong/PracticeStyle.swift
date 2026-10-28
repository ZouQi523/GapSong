import SwiftUI

/// 练习页的排版下限、语义色与布局工具。
///
/// 480×380 最小窗下窗口系数 `s` 只有 0.67：如果按钮和提示继续等比缩小，
/// 文字会跌到 6–7pt。这里给控件/提示/脚注设可读下限；正文和填空先对
/// 「窗口基础尺寸」设下限，再乘字号系数，所以 14–72 每一档仍有可见变化。
/// 放不下时靠换行和练习页的纵向滚动兜底，不靠把字缩小，也不横向裁切。
enum PracticeStyle {
    /// 按钮、胶囊、菜单标签等可点击控件的文字下限
    static let controlFloor: CGFloat = 11.5
    /// 状态、提示、说明文字的下限（比控件略小，但仍然可读）
    static let hintFloor: CGFloat = 10.5
    /// 徽章、脚注等辅助信息的下限
    static let captionFloor: CGFloat = 9.5
    /// 正文/填空在窗口极小时只给「窗口基础尺寸」设的下限。
    ///
    /// 关键：这个下限**先乘窗口系数、再乘字号系数**，绝不能在乘完
    /// `fontFactor` 之后再 clamp。否则 480×380 下字号 14–24 会被压成同一档，
    /// 用户按 ⌘= / ⌘- 看不到变化——这正是上一轮修过的问题。
    static let bodyScaleFloor: CGFloat = 0.8
    /// 提示在窗口极小时使用的窗口系数下限（同样在乘字号系数之前）
    static let hintScaleFloor: CGFloat = 1.0

    /// 练习页的窗口系数：小窗不挤，大窗不空。
    /// 抽成静态函数，界面和自检共用同一套公式。
    static func windowScale(width: CGFloat, height: CGFloat) -> CGFloat {
        guard width > 1, height > 1 else { return 1 }
        let base = min(width / 720, height / 340)
        return min(max(base, 0.62), 1.7)
    }

    /// 控件文字：窗口再小也不低于 `controlFloor`。
    /// 控件本来就不跟字号菜单缩放，所以可以安全地设固定下限。
    static func control(_ scale: CGFloat, base: CGFloat = 11.5) -> CGFloat {
        max(controlFloor, base * scale)
    }

    /// 提示文字：先给窗口基础尺寸设下限（480 窗不再缩到 6pt），
    /// 再乘字号系数；只有低于可读下限时才停在下限。
    /// 字号 38/72 仍明显变大；14–24 在小窗里停在同一可读档是刻意的，
    /// 因为提示不属于「正文」，正文/输入字母另有单调缩放。
    static func hint(_ scale: CGFloat, factor: CGFloat = 1, base: CGFloat = 10) -> CGFloat {
        max(hintFloor, base * max(scale, hintScaleFloor) * factor)
    }

    /// 徽章/脚注等界面装饰文字：跟窗口走，不跟字号菜单缩放（与按钮同一类）。
    static func caption(_ scale: CGFloat, base: CGFloat = 9.5) -> CGFloat {
        max(captionFloor, base * scale)
    }

    /// 正文/填空横线/输入字母/译文：先给窗口基础尺寸设下限，再乘字号系数，
    /// 因此字号 14–72 每一档都有可见变化，不会被下限压平。
    static func body(_ scale: CGFloat, factor: CGFloat = 1, base: CGFloat = 16) -> CGFloat {
        base * max(scale, bodyScaleFloor) * factor
    }

    /// 练习页的语义色。避免在多处连续叠加低透明度：主文字、次文字、
    /// 弱提示各用一个固定角色，对比度至少能按角色统一检查。
    ///
    /// 透明度按真实浮窗背景留了余量：原生 480 窗里普通小字的目标约 4.5:1。
    /// 关键操作提示（空格/点击切换空、快捷键、状态说明）用 `tertiary`，
    /// 只在装饰线和可有可无的元信息上使用更弱的 `muted` / `faint`。
    enum Ink {
        /// 主文字（当前句、按钮主文字）
        static let primaryOpacity: CGFloat = 0.92
        /// 次文字（当前动作、重点说明）
        static let secondaryOpacity: CGFloat = 0.74
        /// 关键辅助文字：操作提示、快捷键、状态说明
        static let tertiaryOpacity: CGFloat = 0.62
        /// 元信息：来源、序号、脚注等（不承载操作）
        static let mutedOpacity: CGFloat = 0.46

        static let primary = Color.white.opacity(primaryOpacity)
        static let secondary = Color.white.opacity(secondaryOpacity)
        static let tertiary = Color.white.opacity(tertiaryOpacity)
        static let muted = Color.white.opacity(mutedOpacity)
        /// 装饰性分隔、未选中的横线
        static let faint = Color.white.opacity(0.3)
        /// 已全对 / 等待句末的确认色
        static let mint = Color(red: 0.45, green: 0.86, blue: 0.55)
        /// 可恢复的播放提示
        static let warn = Color(red: 1.0, green: 0.74, blue: 0.44)
        /// 判错
        static let error = Color(red: 1.0, green: 0.56, blue: 0.52)
    }
}

/// 从左到右排列、放不下就换行的行布局。
///
/// 操作区用它做兜底：窗口被压到最小时按钮先换行，而不是被横向裁切。
struct WrapRowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    private struct Row {
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 600
        let rows = rows(subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height }
            + lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = rows(subviews, maxWidth: bounds.width)
        var y = bounds.minY
        var index = 0

        for row in rows {
            var x = bounds.minX
            for size in row.sizes {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
                index += 1
            }
            y += row.height + lineSpacing
        }
    }

    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var result: [Row] = []
        var current = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.sizes.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.sizes.isEmpty {
                result.append(current)
                current = Row(sizes: [size], width: size.width, height: size.height)
            } else {
                current.sizes.append(size)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }

        if !current.sizes.isEmpty { result.append(current) }
        return result
    }
}
