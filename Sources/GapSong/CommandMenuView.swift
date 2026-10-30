import SwiftUI

/// 窗口内键盘菜单：数字索引、无鼠标也能走完所有操作。
///
/// 只在 `menu.isOpen` 时显示在歌词/练习窗口最上层；窗口会同时临时放大，
/// 保证 9 行都看得见（见 `OverlayController.setMenuLayout`）。
struct CommandMenuView: View {
    @ObservedObject var menu: CommandMenu

    var body: some View {
        GeometryReader { geo in
            let s = scale(geo.size)
            // 大窗口里不要把菜单拉成整屏宽：内容限宽并居中，读起来更像一个菜单
            let contentWidth = min(max(geo.size.width - 32 * s, 320), 720 * s)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    header(s)
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.vertical, 7 * s)
                    Spacer(minLength: 0)
                    rows(s)
                    Spacer(minLength: 0)
                    footer(s)
                }
                .padding(.horizontal, 16 * s)
                .padding(.top, 12 * s)
                .padding(.bottom, 10 * s)
                .frame(width: contentWidth, height: geo.size.height, alignment: .topLeading)
                Spacer(minLength: 0)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(white: 0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    /// 菜单窗口已经临时放大，这里只做轻微缩放，保证 9 行都放得下
    private func scale(_ size: CGSize) -> CGFloat {
        guard size.width > 1, size.height > 1 else { return 1 }
        return min(max(min(size.width / 620, size.height / 440), 0.85), 1.2)
    }

    // MARK: 顶部

    private func header(_ s: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8 * s) {
            Text("菜单")
                .font(.system(size: 13.5 * s, weight: .semibold))
                .foregroundStyle(PracticeStyle.Ink.primary)
            Text(menu.breadcrumb)
                .font(.system(size: max(10, 10.5 * s)))
                .foregroundStyle(PracticeStyle.Ink.muted)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("1–9 选择")
                .font(.system(size: max(9.5, 10 * s), weight: .medium))
                .foregroundStyle(PracticeStyle.Ink.tertiary)
        }
    }

    // MARK: 条目

    private func rows(_ s: CGFloat) -> some View {
        VStack(spacing: 3 * s) {
            ForEach(Array(menu.page.items.enumerated()), id: \.element.id) { index, item in
                row(index + 1, item, s)
            }
        }
    }

    private func row(_ number: Int, _ item: CommandMenuItem, _ s: CGFloat) -> some View {
        Button {
            menu.select(number)
        } label: {
            HStack(spacing: 9 * s) {
                Text("\(number)")
                    .font(.system(size: max(10.5, 11.5 * s), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        item.isEnabled ? Color.white.opacity(0.92) : Color.white.opacity(0.3)
                    )
                    .frame(width: 22 * s, height: 22 * s)
                    .background(
                        Circle().fill(Color.white.opacity(item.isEnabled ? 0.13 : 0.04))
                    )

                Text(item.title)
                    .font(.system(size: max(11.5, 13 * s), weight: item.isOn ? .semibold : .regular))
                    .foregroundStyle(
                        item.isEnabled ? PracticeStyle.Ink.primary : Color.white.opacity(0.3)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: max(9.5, 10.5 * s)))
                        .foregroundStyle(
                            item.isEnabled ? PracticeStyle.Ink.tertiary : Color.white.opacity(0.22)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                if item.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: max(9, 10 * s), weight: .bold))
                        .foregroundStyle(PracticeStyle.Ink.mint)
                        .frame(width: 12 * s)
                } else if item.isSubmenu {
                    Image(systemName: "chevron.right")
                        .font(.system(size: max(8, 9 * s), weight: .semibold))
                        .foregroundStyle(PracticeStyle.Ink.muted)
                        .frame(width: 12 * s)
                }
            }
            .padding(.horizontal, 8 * s)
            .padding(.vertical, 5 * s)
            .frame(maxWidth: .infinity, minHeight: 30 * s, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7 * s, style: .continuous)
                    .fill(Color.white.opacity(item.isEnabled ? 0.05 : 0.02))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .help(item.isEnabled ? "" : "这一项现在不可用")
    }

    // MARK: 底部

    private func footer(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Text(menu.canGoBack ? "0 / Esc 返回上一级" : "0 / Esc 关闭菜单")
                .font(.system(size: max(9.5, 10 * s), weight: .medium))
                .foregroundStyle(PracticeStyle.Ink.tertiary)
            if let notice = menu.notice {
                Text(notice)
                    .font(.system(size: max(9.5, 10 * s)))
                    .foregroundStyle(PracticeStyle.Ink.warn)
            }
            Spacer(minLength: 8)
            Text("菜单期间练习按键暂停")
                .font(.system(size: max(9, 9.5 * s)))
                .foregroundStyle(PracticeStyle.Ink.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.top, 4 * s)
    }
}
