import AppKit
import SwiftUI
import Combine

final class LyricPanel: NSPanel {
    // 允许成为 key window，系统下载语言包等弹窗才能正常挂到面板上
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 右键菜单交给 AppKit 弹（SwiftUI 的 contextMenu 会被 20fps 刷新带着闪烁）
    var onContextMenu: ((NSEvent) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        if let onContextMenu {
            onContextMenu(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

@MainActor
final class OverlayController {
    private let panel: LyricPanel
    private let hosting: NSHostingView<OverlayView>
    private let state: PlayerState
    private let settings: Settings

    private var cancellables: Set<AnyCancellable> = []
    private var isApplyingSize = false
    /// 菜单打开前的窗口 frame：菜单需要临时加高，关掉后连位置一起还原
    private var menuRestoreFrame: NSRect?

    /// 练习态需要能放下设置页/答题/揭示/结束四套内容，歌词态保持紧凑 420×110
    static func minSize(practice: Bool) -> NSSize {
        practice
            ? NSSize(width: Settings.practiceMinSize.width, height: Settings.practiceMinSize.height)
            : NSSize(width: Settings.lyricMinSize.width, height: Settings.lyricMinSize.height)
    }

    /// 菜单至少需要的高度：标题 + 9 行 + 底部提示
    static let menuMinSize = NSSize(width: 600, height: 440)

    private var currentMinSize: NSSize { Self.minSize(practice: settings.practiceMode) }

    init(
        state: PlayerState,
        settings: Settings,
        practice: PracticeEngine,
        bank: QuestionBank,
        mistakes: MistakeBook,
        menu: CommandMenu
    ) {
        self.state = state
        self.settings = settings
        self.hosting = NSHostingView(
            rootView: OverlayView(
                state: state,
                settings: settings,
                translator: state.translator,
                practice: practice,
                bank: bank,
                mistakes: mistakes,
                menu: menu
            )
        )

        let minSize = Self.minSize(practice: settings.practiceMode)
        let initial = NSSize(
            width: max(minSize.width, settings.panelWidth),
            height: max(minSize.height, settings.panelHeight)
        )

        panel = LyricPanel(
            contentRect: NSRect(origin: .zero, size: initial),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 普通窗口层级：不压住其它应用的窗口，需要时由用户或系统正常前置
        panel.level = .normal
        // 显式禁用浮动面板行为，保持普通窗口排序
        panel.isFloatingPanel = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        // 保留已有桌面空间行为，窗口层级仍使用 .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.minSize = minSize
        panel.isReleasedWhenClosed = false

        // 关键：不要让 NSHostingView 的 Auto Layout / 固有尺寸反过来改窗口大小
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = NSRect(origin: .zero, size: initial)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.setContentSize(initial)

        restorePosition()

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.savePosition() }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.saveSize() }
        }

        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.applySettings() }
            }
            .store(in: &cancellables)

        applySettings()
    }

    var isVisible: Bool { panel.isVisible }

    /// 给 AppKit 右键菜单定位用
    var window: NSWindow { panel }

    /// 右键弹菜单（面板级的兜底，事件监听没拿到时也能弹）
    var contextMenuHandler: ((NSEvent) -> Void)? {
        get { panel.onContextMenu }
        set { panel.onContextMenu = newValue }
    }

    func show() {
        panel.orderFront(nil)
        // 面板隐藏期间 translationTask 不会运行，重新显示时补一次
        state.translator.retry()
    }

    func hide() { panel.orderOut(nil) }

    /// 幂等：可见性没有变化时不动窗口，避免每次偏好更新都把已显示的窗口重新提到最前
    func setVisible(_ v: Bool) {
        guard v != panel.isVisible else { return }
        v ? show() : hide()
    }

    /// 练习模式需要键盘输入：把面板顶到最前并成为 key window
    func focusForKeyInput() {
        panel.orderFront(nil)
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 键盘菜单需要更多横向/纵向空间，打开时临时放大、关闭时还原。
    ///
    /// 只改运行时 frame，不写 `settings.panelWidth/Height`：
    /// 菜单不是用户调整的窗口尺寸，不该覆盖记住的歌词/练习尺寸。
    func setMenuLayout(_ open: Bool) {
        if open {
            guard menuRestoreFrame == nil else { return }
            menuRestoreFrame = panel.frame
            // 菜单期间不要因为背景拖动而移动窗口：关闭时位置要原样还回去
            panel.isMovableByWindowBackground = false
            let target = NSSize(
                width: max(panel.frame.width, Self.menuMinSize.width),
                height: max(panel.frame.height, Self.menuMinSize.height)
            )
            applyRuntimeSize(target)
        } else if let restore = menuRestoreFrame {
            menuRestoreFrame = nil
            let minSize = currentMinSize
            var frame = restore
            frame.size = NSSize(
                width: max(restore.width, minSize.width),
                height: max(restore.height, minSize.height)
            )
            applyRuntimeFrame(frame)
            panel.isMovableByWindowBackground = !settings.locked
        }
    }

    /// 菜单打开的入口：键盘和「1 菜单」按钮都走这里
    func focusForMenu() {
        focusForKeyInput()
    }

    // MARK: 私有

    /// 只动当前 frame，保持顶部位置不变，并夹在屏幕可见范围内
    private func applyRuntimeSize(_ size: NSSize) {
        var frame = panel.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        applyRuntimeFrame(frame)
    }

    private func applyRuntimeFrame(_ frame: NSRect) {
        var frame = frame
        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            frame.origin.x = min(max(frame.origin.x, visible.minX - 20), visible.maxX - frame.width + 20)
            frame.origin.y = min(max(frame.origin.y, visible.minY - 20), visible.maxY - frame.height + 20)
        }
        panel.setFrame(frame, display: true, animate: false)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func applySettings() {
        // 菜单打开期间保持不可拖动，关闭时 setMenuLayout 会按锁定偏好恢复
        panel.isMovableByWindowBackground = menuRestoreFrame == nil && !settings.locked
        panel.minSize = currentMinSize
        applySize()
        setVisible(settings.visible)
    }

    private func applySize() {
        // 菜单打开期间不改用户尺寸；关闭时 setMenuLayout 会还原
        guard menuRestoreFrame == nil else { return }
        let minSize = currentMinSize
        let target = NSSize(
            width: max(minSize.width, settings.panelWidth),
            height: max(minSize.height, settings.panelHeight)
        )
        let current = panel.frame.size
        guard abs(current.width - target.width) > 0.5 || abs(current.height - target.height) > 0.5 else { return }

        isApplyingSize = true
        var frame = panel.frame
        // 顶部位置保持不动
        frame.origin.y = frame.maxY - target.height
        frame.size = target
        panel.setFrame(frame, display: true, animate: false)
        hosting.frame = NSRect(origin: .zero, size: target)
        isApplyingSize = false
    }

    private func restorePosition() {
        let d = settings.store
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size

        var origin = NSPoint(x: screen.midX - size.width / 2, y: screen.minY + 90)
        if let x = d.object(forKey: "panelX") as? Double,
           let y = d.object(forKey: "panelY") as? Double {
            origin = NSPoint(x: x, y: y)
        }
        origin.x = min(max(origin.x, screen.minX - 40), screen.maxX - size.width + 40)
        origin.y = min(max(origin.y, screen.minY - 20), screen.maxY - size.height + 20)

        panel.setFrameOrigin(origin)
    }

    private func savePosition() {
        guard panel.isVisible else { return }
        let d = settings.store
        d.set(Double(panel.frame.origin.x), forKey: "panelX")
        d.set(Double(panel.frame.origin.y), forKey: "panelY")
    }

    private func saveSize() {
        // 菜单临时加大的尺寸不写回偏好
        guard !isApplyingSize, menuRestoreFrame == nil else { return }
        settings.setSize(width: panel.frame.width, height: panel.frame.height)
    }
}
