import SwiftUI
import AppKit

private struct PreviewKey: EnvironmentKey {
    static let defaultValue = false
}

private struct PracticePreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var lyricPreview: Bool {
        get { self[PreviewKey.self] }
        set { self[PreviewKey.self] = newValue }
    }

    /// 离屏预览时强制进入听写界面，但不动用户偏好
    var practicePreview: Bool {
        get { self[PracticePreviewKey.self] }
        set { self[PracticePreviewKey.self] = newValue }
    }
}

struct OverlayView: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var settings: Settings
    @ObservedObject var translator: TranslationEngine
    @ObservedObject var practice: PracticeEngine
    @ObservedObject var bank: QuestionBank
    @ObservedObject var mistakes: MistakeBook
    /// 仅离屏预览用：预置被点开的词
    var previewSelectedWord: String? = nil
    @Environment(\.lyricPreview) private var isPreview
    @Environment(\.practicePreview) private var practicePreview

    private var inPractice: Bool { settings.practiceMode || practicePreview }

    /// 全文模式下用户手动滚动时暂停自动跟随
    @State private var follow = true
    @State private var hoverClose = false
    @State private var resumeTask: Task<Void, Never>?
    /// 收藏成功的轻提示
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if inPractice {
                Group {
                    if practice.phase == .setup {
                        PracticeSetupView(
                            state: state,
                            settings: settings,
                            engine: practice,
                            bank: bank,
                            mistakes: mistakes
                        )
                    } else {
                        PracticeView(
                            state: state,
                            settings: settings,
                            engine: practice,
                            translator: translator,
                            bank: bank,
                            mistakes: mistakes,
                            initialSelectedWord: previewSelectedWord
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 12)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                    GeometryReader { geo in
                        let full = settings.forceFull || geo.size.height >= 250
                        Group {
                            if full {
                                fullBody(now: context.date)
                            } else {
                                compactBody(now: context.date)
                            }
                        }
                        .padding(.horizontal, full ? 22 : 28)
                        .padding(.top, 12)
                        .padding(.bottom, full ? 8 : 16)
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
        }
        .background(background)
        .overlay(alignment: .bottom) {
            if !inPractice { progressBar }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                toastView(toast)
            }
        }
        .overlay(alignment: .top) { dragStrip }
        .overlay(alignment: .topLeading) {
            if !isPreview { closeButton }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isPreview {
                // 练习态窗口下限更高（480×380），歌词态仍是紧凑 420×110
                ResizeGrip(
                    minWidth: inPractice ? Settings.practiceMinSize.width : Settings.lyricMinSize.width,
                    minHeight: inPractice ? Settings.practiceMinSize.height : Settings.lyricMinSize.height
                )
                .frame(width: 22, height: 22)
                .padding(4)
            }
        }
        .translationTask(translator.config) { session in
            await translator.consume(session)
        }
        .onChange(of: settings.visible) { _, visible in
            // 窗被隐藏时不能继续在后台读英语句子
            if !visible { practice.stopReading() }
        }
    }

    // MARK: 背景 / 装饰

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let transparency = settings.backgroundTransparency

        return ZStack {
            // 透明时加一层系统材质，文字和按钮仍然清晰；默认 0 时完全不加，视觉不变
            if transparency > 0.001, !isPreview {
                WindowMaterialBackground(
                    alpha: WindowChrome.backgroundBlurAlpha(transparency: transparency)
                )
            }
            Color(white: 0.05)
                .opacity(WindowChrome.backgroundFillAlpha(transparency: transparency))
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var dragStrip: some View {
        if isPreview {
            // 快照里也画出拖拽抓手，验收能看到可发现的位置
            dragAffordance
        } else if WindowChrome.dragStripEnabled(locked: settings.locked) {
            // 固定顶部留白：只覆盖 12pt 窄带，不碰按钮、填空、滚动和右下角缩放手柄
            WindowDragBar()
                .frame(height: WindowChrome.dragStripHeight)
                .padding(.horizontal, WindowChrome.dragStripInset)
        }
        // 锁定位置：同高度留白，但不接受拖动
    }

    /// 顶部居中的短横线：提示「这里可以拖」
    private var dragAffordance: some View {
        Capsule()
            .fill(Color.white.opacity(0.18))
            .frame(width: 26, height: 2.5)
            .frame(maxWidth: .infinity)
            .padding(.top, 5)
            .allowsHitTesting(false)
    }

    private var closeButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white.opacity(hoverClose ? 1.0 : 0.55))
                .frame(width: 19, height: 19)
                .background(Circle().fill(Color.white.opacity(hoverClose ? 0.26 : 0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("退出 GapSong")
        .onHover { hoverClose = $0 }
        .padding(.leading, 12)
        .padding(.top, 9)
    }

    @ViewBuilder
    private var progressBar: some View {
        if let snap = state.snapshot, snap.track.duration > 0 {
            GeometryReader { geo in
                let p = min(max(state.position() / snap.track.duration, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Color.white.opacity(0.35))
                        .frame(width: max(2, geo.size.width * p))
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
            .allowsHitTesting(false)
        }
    }

    // MARK: 紧凑模式

    /// 收藏/错题持久化异常的统一提示：紧凑、全文、练习、管理窗口都要能看见
    var storageWarning: String? {
        bank.storageWarning ?? mistakes.storageWarning
    }

    @ViewBuilder
    private func compactBody(now: Date) -> some View {
        if let snap = state.snapshot {
            VStack(spacing: 6) {
                header(snap)
                if let warning = storageWarning {
                    StorageWarningBanner(text: warning, compact: true)
                }
                Spacer(minLength: 2)
                lyricBlock(now: now)
                Spacer(minLength: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            idleBody
        }
    }

    @ViewBuilder
    private func lyricBlock(now: Date) -> some View {
        if let lyrics = state.lyrics, lyrics.synced,
           let idx = state.lineIndex(at: state.position(at: now)) {
            let line = lyrics.lines[idx]
            let next = idx + 1 < lyrics.lines.count ? lyrics.lines[idx + 1] : nil
            let size = settings.fontSize
            VStack(spacing: 6) {
                Text(line.text)
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .id(idx)
                    .frame(maxWidth: .infinity)

                if settings.showTranslation, translator.isNeeded {
                    Text(translator.translation(for: line.text) ?? " ")
                        .font(.system(size: size * 0.68))
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity)
                }

                Text(next?.text ?? " ")
                    .font(.system(size: size * 0.66))
                    .foregroundStyle(.white.opacity(0.26))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            .animation(.easeInOut(duration: 0.28), value: idx)
        } else if let lyrics = state.lyrics {
            unsyncedBody(lyrics)
        } else {
            switch state.loadState {
            case .loading: placeholder("正在匹配歌词…")
            case .notFound: placeholder("未找到这首歌的歌词")
            case .failed(let m): placeholder(m)
            default: placeholder(" ")
            }
        }
    }

    // MARK: 全文模式

    @ViewBuilder
    private func fullBody(now: Date) -> some View {
        if let snap = state.snapshot {
            VStack(spacing: 6) {
                header(snap)
                if let warning = storageWarning {
                    StorageWarningBanner(text: warning, compact: false)
                }
                Divider().overlay(Color.white.opacity(0.08))
                if let lyrics = state.lyrics, !lyrics.lines.isEmpty {
                    lyricList(lyrics, now: now)
                } else {
                    Spacer()
                    placeholder("正在匹配歌词…")
                    Spacer()
                }
            }
        } else {
            idleBody
        }
    }

    @ViewBuilder
    private func lyricList(_ lyrics: Lyrics, now: Date) -> some View {
        let idx = state.lineIndex(at: state.position(at: now))
        let size = settings.fontSize

        if isPreview {
            // 离屏渲染画不了 ScrollView 的内容，预览时直接平铺（开发/CI 截图用）
            previewLyricRows(lyrics, current: idx, size: size)
        } else {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { i, line in
                                row(line, index: i, current: idx, size: size)
                                    .id(i)
                            }
                            Color.clear.frame(height: 8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        // 给系统滚动条留一条沟槽，避免「＋」被压在滚动条下面
                        .padding(.trailing, 24)
                    }
                    .onScrollPhaseChange { _, newPhase in
                        if newPhase == .interacting { pauseFollow() }
                    }
                    .onChange(of: idx) { _, newValue in
                        guard follow, let n = newValue else { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(n, anchor: .center)
                        }
                    }
                    .onAppear {
                        if let n = idx { proxy.scrollTo(n, anchor: .center) }
                    }

                    if !follow {
                        Button {
                            resumeFollow(proxy)
                        } label: {
                            Text("↓ 回到当前")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private func previewLyricRows(_ lyrics: Lyrics, current: Int?, size: Double) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { i, line in
                row(line, index: i, current: current, size: size)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.trailing, 24)
    }

    private func row(_ line: LyricLine, index: Int, current: Int?, size: Double) -> some View {
        let isCurrent = current == index
        let translation = settings.showTranslation ? translator.translation(for: line.text) : nil
        let title = state.snapshot?.track.title ?? ""

        // 当前正在唱的这一句再放大一点，和上下句拉开层次
        let lineScale = isCurrent ? 1.18 : 0.9
        let translationScale = isCurrent ? 0.74 : 0.58

        return ZStack(alignment: .trailing) {
            VStack(spacing: 3) {
                Text(line.text)
                    .font(.system(size: size * lineScale,
                                  weight: isCurrent ? .semibold : .regular,
                                  design: .rounded))
                    .foregroundStyle(.white.opacity(isCurrent ? 1.0 : 0.38))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                if let translation, !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: size * translationScale))
                        .foregroundStyle(.white.opacity(isCurrent ? 0.75 : 0.24))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)

            if !isPreview {
                BankAddButton(
                    added: bank.contains(text: line.text, title: title),
                    enabled: PracticeBlanks.isPracticeable(line.text)
                ) {
                    toggleBank(line)
                }
                .padding(.trailing, 6)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isCurrent)
    }

    private func pauseFollow() {
        follow = false
        resumeTask?.cancel()
        resumeTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            follow = true
        }
    }

    private func resumeFollow(_ proxy: ScrollViewProxy) {
        follow = true
        resumeTask?.cancel()
        if let n = state.lineIndex(at: state.position()) {
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(n, anchor: .center) }
        }
    }

    // MARK: 公共块

    private func header(_ snap: MusicSnapshot) -> some View {
        HStack(spacing: 8) {
            // 给左上角的关闭按钮留位
            Color.clear.frame(width: 12, height: 1)
            Text(snap.track.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.25))
            Text(snap.track.artist)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
            Spacer(minLength: 0)
            if settings.locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.trailing, 4)
            }
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch translator.status {
        case .unavailable(let msg):
            Text(TextUtil.short(msg, limit: 44))
                .font(.system(size: 10))
                .foregroundStyle(.orange.opacity(0.85))
                .lineLimit(1)
        case .working(let msg):
            Text(msg)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
        default:
            if let src = state.lyrics?.source {
                Text(src)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.22))
                    .lineLimit(1)
            }
        }
    }

    private func unsyncedBody(_ lyrics: Lyrics) -> some View {
        let lines = Array(lyrics.lines.prefix(4))
        return VStack(spacing: 5) {
            ForEach(lines) { l in
                Text(l.text)
                    .font(.system(size: settings.fontSize * 0.62))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text("纯文本歌词 · 无时间轴")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.22))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity)
    }

    private var idleBody: some View {
        VStack(spacing: 6) {
            Text("♫ 在 Apple Music 里播放一首歌")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Text(state.hint ?? "歌词会自动匹配并翻译 · 右键查看更多")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
            if let warning = storageWarning {
                StorageWarningBanner(text: warning, compact: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 收藏歌词

    private func toggleBank(_ line: LyricLine) {
        guard let track = state.snapshot?.track else { return }
        guard PracticeBlanks.isPracticeable(line.text) else {
            showToast("这句没有可听写的英文内容")
            return
        }
        let result = bank.toggle(
            text: line.text,
            translation: translator.translation(for: line.text),
            title: track.title,
            artist: track.artist,
            lineTime: line.time
        )
        showToast(result.toastText(count: bank.count))
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { toast = text }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { toast = nil }
        }
    }

    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.bottom, 18)
            .transition(.opacity)
            .allowsHitTesting(false)
    }

}

/// 全文模式里每句右侧的收藏书签：点一下收藏，再点一下取消。
/// 紧凑歌词窗和练习页不再放顶部收藏入口，这里保留逐句收藏能力。
private struct BankAddButton: View {
    let added: Bool
    let enabled: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: added ? "bookmark.fill" : "bookmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    added
                        ? Color(red: 0.45, green: 0.86, blue: 0.55).opacity(enabled ? 1 : 0.4)
                        : Color.white.opacity(enabled ? (hover ? 0.95 : 0.62) : 0.15)
                )
                .frame(width: 22, height: 22)
                .background(
                    Capsule().fill(Color.white.opacity(hover && enabled ? 0.14 : 0))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hover = $0 }
        .help(
            !enabled
                ? "这句没有可听写的英文内容"
                : (added ? "已收藏，点击取消" : "收藏这句歌词（全文模式下每句右侧都有书签）")
        )
    }
}

/// 收藏/错题的持久化异常提示（紧凑、全文、练习、管理窗口共用同一套说法）
struct StorageWarningBanner: View {
    var text: String
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: compact ? 8.5 : 10, weight: .semibold))
                .padding(.top, compact ? 1 : 1.5)
            Text(text)
                .font(.system(size: compact ? 9 : 10))
                .lineLimit(compact ? 1 : 2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: compact)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(red: 1.0, green: 0.67, blue: 0.45))
        .padding(.horizontal, 7)
        .padding(.vertical, compact ? 2.5 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

/// 顶部透明拖拽区，用 AppKit 原生拖窗
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        private var startFrame: NSRect = .zero
        private var startMouse: NSPoint = .zero
        private var dragging = false

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            // 非激活面板也能直接拖动；不依赖 performDrag，避免首次点击被“吃掉”
            window.makeKey()
            startFrame = window.frame
            startMouse = NSEvent.mouseLocation
            dragging = true
        }

        override func mouseDragged(with event: NSEvent) {
            guard dragging, let window else { return }
            let now = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(
                x: startFrame.origin.x + (now.x - startMouse.x),
                y: startFrame.origin.y + (now.y - startMouse.y)
            ))
        }

        override func mouseUp(with event: NSEvent) {
            dragging = false
        }

        override func rightMouseDown(with event: NSEvent) {
            // 让右键菜单仍然能弹出来
            nextResponder?.rightMouseDown(with: event)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override var mouseDownCanMoveWindow: Bool { false }

        // 关键：App 不在最前时，第一次点击也要立刻能拖，而不是被“激活窗口”吃掉
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

/// 右下角缩放手柄
struct ResizeGrip: NSViewRepresentable {
    var minWidth: CGFloat
    var minHeight: CGFloat

    func makeNSView(context: Context) -> NSView {
        GripView(minWidth: minWidth, minHeight: minHeight)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class GripView: NSView {
        let minWidth: CGFloat
        let minHeight: CGFloat

        init(minWidth: CGFloat, minHeight: CGFloat) {
            self.minWidth = minWidth
            self.minHeight = minHeight
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.withAlphaComponent(0.28).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.2
            for i in 0..<3 {
                let off = CGFloat(4 + i * 4)
                path.move(to: NSPoint(x: bounds.maxX - off, y: bounds.minY + 3))
                path.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.minY + off))
            }
            path.stroke()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            var frame = window.frame
            frame.size.width = max(minWidth, frame.width + event.deltaX)
            frame.size.height = max(minHeight, frame.height - event.deltaY)
            window.setFrame(frame, display: true)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
