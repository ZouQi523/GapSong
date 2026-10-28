import SwiftUI
import AppKit

/// 悬浮窗的窗口级外观：顶部拖拽条与背景透明度。
///
/// 拖拽条是一条固定高度的真实留白（落在内容上内边距里，不额外占高度），
/// 只覆盖顶部一条窄带，不遮挡按钮、填空、滚动和右下角缩放手柄。
enum WindowChrome {
    /// 顶部留白拖拽条的高度：正好落在现有 12pt 上内边距里
    static let dragStripHeight: CGFloat = 12
    /// 左右内缩：左边给关闭按钮让位，右边保持对称
    static let dragStripInset: CGFloat = 36

    /// 默认背景不透明度（保持本轮之前的视觉）
    static let baseBackgroundAlpha: Double = 0.82
    /// 背景透明度上限：再高文字就会和桌面打架
    static let maxTransparency: Double = 0.45

    /// 「锁定位置」时拖拽条不响应鼠标
    static func dragStripEnabled(locked: Bool) -> Bool { !locked }

    /// 透明度 → 背景底色不透明度。0 时就是原有的 0.82，桌面透出程度真实变化。
    static func backgroundFillAlpha(transparency: Double) -> Double {
        let value = min(max(transparency, 0), maxTransparency)
        return baseBackgroundAlpha * (1 - value)
    }

    /// 透明时叠一层系统材质（毛玻璃）：文字/按钮仍清晰，不是只在不透明底上刷透明色。
    /// 0 时完全不加材质，默认视觉保持不变。
    static func backgroundBlurAlpha(transparency: Double) -> Double {
        let value = min(max(transparency, 0), maxTransparency)
        return min(1, value * 2)
    }
}

/// 顶部透明拖拽条：用 AppKit 原生鼠标事件拖窗。
///
/// 不再依赖 `isMovableByWindowBackground` —— SwiftUI 的 hosting view 会
/// 吃掉背景拖动，练习态此前的拖拽条高度又是 0，实际没有可拖的位置。
struct WindowDragBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DragBarView()
        view.toolTip = "拖动这里移动窗口（右键可锁定位置）"
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragBarView: NSView {
        private var startFrame: NSRect = .zero
        private var startScreenPoint: NSPoint = .zero
        private var dragging = false
        private var hover = false
        private var hoverArea: NSTrackingArea?

        /// 很克制的短横抓手：真实窗口也画，提示这里能拖
        override func draw(_ dirtyRect: NSRect) {
            let width: CGFloat = 26
            let height: CGFloat = 2.5
            let rect = NSRect(
                x: (bounds.width - width) / 2,
                y: (bounds.height - height) / 2,
                width: width,
                height: height
            )
            NSColor.white.withAlphaComponent(hover ? 0.40 : 0.18).setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            hoverArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            hover = true
            needsDisplay = true
        }

        override func mouseExited(with event: NSEvent) {
            hover = false
            needsDisplay = true
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            // 非激活面板也能直接拖动；不依赖 performDrag，避免首次点击被“吃掉”
            window.makeKey()
            // 用事件自己的位置算屏幕点：可访问性/合成鼠标事件不一定更新全局指针，
            // NSEvent.mouseLocation 可能停在旧位置。真实物理鼠标同样适用。
            startFrame = window.frame
            startScreenPoint = window.convertPoint(toScreen: event.locationInWindow)
            dragging = true
            NSCursor.closedHand.set()
        }

        override func mouseDragged(with event: NSEvent) {
            guard dragging, let window else { return }
            let now = window.convertPoint(toScreen: event.locationInWindow)
            window.setFrameOrigin(NSPoint(
                x: startFrame.origin.x + (now.x - startScreenPoint.x),
                y: startFrame.origin.y + (now.y - startScreenPoint.y)
            ))
        }

        override func mouseUp(with event: NSEvent) {
            dragging = false
            window?.invalidateCursorRects(for: self)
            NSCursor.openHand.set()
        }

        override func rightMouseDown(with event: NSEvent) {
            // 右键菜单仍然归 AppKit 弹
            nextResponder?.rightMouseDown(with: event)
        }

        // 不重写 hitTest：AppKit 的点属于 superview 坐标，默认实现会正确
        // 转换到本视图 bounds；手动 bounds.contains 会在有布局偏移时误判不可拖。

        override var mouseDownCanMoveWindow: Bool { false }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        // App 不在最前时，第一次点击也要立刻能拖
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

/// 透明背景下的系统材质层：只做视觉，不参与点击。
struct WindowMaterialBackground: NSViewRepresentable {
    var alpha: Double
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = alpha
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? NSVisualEffectView else { return }
        view.material = material
        view.alphaValue = alpha
    }

    /// 材质层吃不到鼠标：点击继续落到下面的填空/按钮/滚动上
    final class PassThroughEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
