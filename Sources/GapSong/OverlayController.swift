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

    private static let minSize = NSSize(width: 420, height: 110)

    init(
        state: PlayerState,
        settings: Settings,
        practice: PracticeEngine,
        bank: QuestionBank,
        mistakes: MistakeBook
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
                mistakes: mistakes
            )
        )

        let initial = NSSize(
            width: max(Self.minSize.width, settings.panelWidth),
            height: max(Self.minSize.height, settings.panelHeight)
        )

        panel = LyricPanel(
            contentRect: NSRect(origin: .zero, size: initial),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.minSize = Self.minSize
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

    func setVisible(_ v: Bool) {
        v ? show() : hide()
    }

    /// 练习模式需要键盘输入：把面板顶到最前并成为 key window
    func focusForKeyInput() {
        panel.orderFront(nil)
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 私有

    private func applySettings() {
        panel.isMovableByWindowBackground = !settings.locked
        applySize()
        setVisible(settings.visible)
    }

    private func applySize() {
        let target = NSSize(
            width: max(Self.minSize.width, settings.panelWidth),
            height: max(Self.minSize.height, settings.panelHeight)
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
        let d = UserDefaults.standard
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
        let d = UserDefaults.standard
        d.set(Double(panel.frame.origin.x), forKey: "panelX")
        d.set(Double(panel.frame.origin.y), forKey: "panelY")
    }

    private func saveSize() {
        guard !isApplyingSize else { return }
        settings.setSize(width: panel.frame.width, height: panel.frame.height)
    }
}
