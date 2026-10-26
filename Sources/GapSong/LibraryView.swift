import SwiftUI
import AppKit

enum LibraryTab: String, CaseIterable, Identifiable {
    case favorites
    case mistakes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: return "收藏歌词"
        case .mistakes: return "错题本"
        }
    }
}

@MainActor
final class LibraryModel: ObservableObject {
    @Published var tab: LibraryTab

    init(tab: LibraryTab = .favorites) {
        self.tab = tab
    }
}

/// 收藏歌词 / 错题本的轻量管理窗口内容
struct LibraryView: View {
    @ObservedObject var favorites: QuestionBank
    @ObservedObject var mistakes: MistakeBook
    @ObservedObject var model: LibraryModel

    /// 离屏渲染时不用 ScrollView（ImageRenderer 画不出滚动内容），只展示前几行
    var preview: Bool = false

    var onPracticeFavorite: (UUID) -> Void
    var onPracticeAllFavorites: () -> Void
    var onPracticeMistake: (UUID) -> Void
    var onPracticeAllMistakes: () -> Void
    var onClearFavorites: () -> Void
    var onClearMistakes: () -> Void
    var onClose: () -> Void

    private let mint = Color(red: 0.41, green: 0.83, blue: 0.57)
    private let red = Color(red: 1.0, green: 0.5, blue: 0.45)
    private let ink = Color(white: 0.075)
    private let card = Color.white.opacity(0.055)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let warning = mistakes.storageWarning {
                Text("⚠️ \(warning)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 1.0, green: 0.65, blue: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    )
            }
            tabs
            Divider().overlay(Color.white.opacity(0.08))
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ink)
        .preferredColorScheme(.dark)
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bookmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(mint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.06)))

            VStack(alignment: .leading, spacing: 2) {
                Text("收藏与错题")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text("收藏 \(favorites.count) 句 · 错题 \(mistakes.count) 条（\(mistakes.totalAttempts) 次错误提交）")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.38))
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            tabButton(.favorites, count: favorites.count)
            tabButton(.mistakes, count: mistakes.count)
            Spacer(minLength: 0)
        }
    }

    private func tabButton(_ tab: LibraryTab, count: Int) -> some View {
        let selected = model.tab == tab
        return Button {
            model.tab = tab
        } label: {
            HStack(spacing: 5) {
                Text(tab.title)
                    .font(.system(size: 11.5, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(.white.opacity(selected ? 0.55 : 0.3))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.14 : 0.05))
            )
            .foregroundStyle(.white.opacity(selected ? 0.92 : 0.55))
        }
        .buttonStyle(.plain)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        switch model.tab {
        case .favorites:
            favoritesSection
        case .mistakes:
            mistakesSection
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: "收藏歌词",
                detail: "\(favorites.count) 句",
                practiceTitle: "练全部收藏",
                practiceEnabled: !favorites.isEmpty,
                clearTitle: "清空收藏",
                clearEnabled: !favorites.isEmpty,
                onPracticeAll: onPracticeAllFavorites,
                onClear: onClearFavorites
            )

            if favorites.isEmpty {
                emptyState(
                    icon: "bookmark",
                    text: "还没有收藏。播放时点歌词右侧的书签，或在练习中点右上角的书签。"
                )
            } else {
                rows {
                    ForEach(preview ? Array(favorites.items.prefix(3)) : favorites.items) { item in
                        favoriteRow(item)
                    }
                }
            }
        }
    }

    private var mistakesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: "错题本",
                detail: "\(mistakes.count) 条 · \(mistakes.totalAttempts) 次错误提交",
                practiceTitle: "练全部错题",
                practiceEnabled: !mistakes.isEmpty,
                clearTitle: "清空错题本",
                clearEnabled: !mistakes.isEmpty,
                onPracticeAll: onPracticeAllMistakes,
                onClear: onClearMistakes
            )

            if mistakes.isEmpty {
                emptyState(
                    icon: "exclamationmark.bubble",
                    text: "还没有错题。只有真正提交且判错才会记录；跳过、空提交、看答案都不会记。"
                )
            } else {
                rows {
                    ForEach(preview ? Array(mistakes.recentEntries.prefix(2)) : mistakes.recentEntries) { entry in
                        MistakeRow(
                            entry: entry,
                            preview: preview,
                            mint: mint,
                            red: red,
                            onPractice: { onPracticeMistake(entry.id) },
                            onDelete: { mistakes.remove(id: entry.id) }
                        )
                    }
                }
            }
        }
    }

    private func sectionHeader(
        title: String,
        detail: String,
        practiceTitle: String,
        practiceEnabled: Bool,
        clearTitle: String,
        clearEnabled: Bool,
        onPracticeAll: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text(detail)
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(.white.opacity(0.3))
            Spacer(minLength: 0)
            smallButton(practiceTitle, enabled: practiceEnabled, action: onPracticeAll)
            smallButton(clearTitle, enabled: clearEnabled, destructive: true, action: onClear)
        }
    }

    private func smallButton(
        _ title: String,
        enabled: Bool,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.white.opacity(enabled ? 0.09 : 0.03))
                )
                .foregroundStyle(
                    destructive
                        ? red.opacity(enabled ? 0.85 : 0.25)
                        : .white.opacity(enabled ? 0.75 : 0.22)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
    }

    @ViewBuilder
    private func rows<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if preview {
            VStack(spacing: 7) { content() }
        } else {
            ScrollView {
                LazyVStack(spacing: 7) { content() }
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: 收藏行

    private func favoriteRow(_ item: BankQuestion) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(mint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                if let translation = item.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(item.sourceLabel)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                rowButton("练这句") { onPracticeFavorite(item.id) }
                trashButton { favorites.remove(id: item.id) }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(card)
        )
    }

    private func rowButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(mint.opacity(0.14)))
                .foregroundStyle(mint.opacity(0.9))
        }
        .buttonStyle(.plain)
    }

    private func trashButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 24, height: 22)
                .background(Circle().fill(Color.white.opacity(0.04)))
        }
        .buttonStyle(.plain)
        .help("删除")
    }

    // MARK: 底部

    private var footer: some View {
        Text("收藏在播放时点歌词右侧书签，或在练习中点右上角书签；错题只在真正提交且判错时记录，历史不会自动删除。所有数据只保存在本机。")
            .font(.system(size: 9.5))
            .foregroundStyle(.white.opacity(0.28))
            .lineLimit(2)
    }
}

/// 一条错题：默认收起历史，展开后逐次回看
private struct MistakeRow: View {
    let entry: MistakeEntry
    let preview: Bool
    let mint: Color
    let red: Color
    let onPractice: () -> Void
    let onDelete: () -> Void

    @State private var expanded: Bool

    init(
        entry: MistakeEntry,
        preview: Bool,
        mint: Color,
        red: Color,
        onPractice: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.entry = entry
        self.preview = preview
        self.mint = mint
        self.red = red
        self.onPractice = onPractice
        self.onDelete = onDelete
        _expanded = State(initialValue: preview)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(red.opacity(0.85))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    if let translation = entry.translation, !translation.isEmpty {
                        Text(translation)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(entry.sourceLabel) · 错 ×\(entry.attemptCount) · 最近 \(entry.lastSeenLabel)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.3))
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Button {
                        expanded.toggle()
                    } label: {
                        Text(expanded ? "收起" : "记录 \(entry.attemptCount)")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)

                    Button(action: onPractice) {
                        Text("练这句")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(mint.opacity(0.14)))
                            .foregroundStyle(mint.opacity(0.9))
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(width: 24, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                    .help("删除这条错题")
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(entry.attempts.reversed())) { attempt in
                        attemptRow(attempt)
                    }
                }
                .padding(.leading, 21)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
    }

    private func attemptRow(_ attempt: MistakeAttempt) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label(for: attempt.submittedAt))
                    .monospacedDigit()
                Text(attempt.sourceLabel)
                Text("填空 \(Int((attempt.ratio * 100).rounded()))%")
                if attempt.wasRetry { Text("看答案后重试") }
                Text("错 \(attempt.wrongBlankCount) 空")
                    .foregroundStyle(red.opacity(0.8))
                Spacer(minLength: 0)
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.3))

            Text("输入：\(attempt.inputSummary)")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)

            blankLine(attempt)
                .font(.system(size: 9.5, design: .monospaced))
        }
        .padding(.leading, 8)
        .padding(.vertical, 3)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)
        }
    }

    private func blankLine(_ attempt: MistakeAttempt) -> Text {
        var output = Text("")
        for blank in attempt.blanks {
            let actual = blank.skipped ? "（跳过）" : blank.actual
            let color: Color = blank.isWrong ? red : .white.opacity(0.45)
            output = output + Text("\(blank.expected) → \(actual)   ").foregroundColor(color)
        }
        return output
    }

    private func label(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}

/// 管理窗口：一个独立、轻量的 NSPanel，不改动歌词窗本身
@MainActor
final class LibraryWindowController: NSWindowController {
    private let model: LibraryModel
    private let windowRef: NSWindow

    init(
        favorites: QuestionBank,
        mistakes: MistakeBook,
        initialTab: LibraryTab,
        onPracticeFavorite: @escaping (UUID) -> Void,
        onPracticeAllFavorites: @escaping () -> Void,
        onPracticeMistake: @escaping (UUID) -> Void,
        onPracticeAllMistakes: @escaping () -> Void,
        onClearFavorites: @escaping () -> Void,
        onClearMistakes: @escaping () -> Void
    ) {
        let model = LibraryModel(tab: initialTab)
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "收藏与错题"
        // 与歌词悬浮窗同为 .floating；show 时再 orderFrontRegardless，确保盖在歌词窗前面
        window.level = .floating
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.075, alpha: 1)
        window.minSize = NSSize(width: 620, height: 460)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("GapSongLibrary")

        let root = LibraryView(
            favorites: favorites,
            mistakes: mistakes,
            model: model,
            onPracticeFavorite: onPracticeFavorite,
            onPracticeAllFavorites: onPracticeAllFavorites,
            onPracticeMistake: onPracticeMistake,
            onPracticeAllMistakes: onPracticeAllMistakes,
            onClearFavorites: onClearFavorites,
            onClearMistakes: onClearMistakes,
            onClose: { [weak window] in window?.close() }
        )
        window.contentView = NSHostingView(rootView: root)
        self.windowRef = window
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(tab: LibraryTab) {
        model.tab = tab
        windowRef.level = .floating
        windowRef.orderFrontRegardless()
        windowRef.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        windowRef.close()
    }
}
