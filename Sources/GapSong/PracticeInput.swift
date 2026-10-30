import AppKit
import SwiftUI

/// 输入源分类（诊断用）：练习窗的字母现在一律直通，不再交给输入法选字；
/// 这里保留判断只是为了诊断日志和既有自检，不参与真实输入分流。
///
/// 不能只按 `com.apple.keylayout.` 前缀硬分流：隔离 GUI 里出现过非标准输入源，
/// 真实 ABC 字母被误判成输入法后全部走了无声批量入口。这里改用
/// 「Apple 键盘布局前缀 / 第三方 keylayout / 输入法关键字」组合判断；
/// 未知来源在未组字时按普通键盘处理，正在组字时让给输入法，避免吞首键。
enum PracticeInputRouting {
    static func isPlainKeyboardLayout(source: String?, hasMarkedText: Bool) -> Bool {
        guard let source, !source.isEmpty else {
            return !hasMarkedText
        }
        if source.hasPrefix("com.apple.keylayout.") { return true }
        let lower = source.lowercased()
        if lower.contains("inputmethod") || lower.contains("input_method") {
            return false
        }
        if lower.contains("keylayout") { return true }
        return !hasMarkedText
    }
}

/// 隐藏的键盘 / 输入法接收视图。
///
/// 直接字母由 AppDelegate 的 keyDown 监听逐字交给引擎（保证一次按键一次落字、
/// 一次音效）；这个 AppKit 文本视图只负责两件事：
/// 1. 成为第一响应者，让输入法有地方组字；
/// 2. 接收输入法提交和 ⌘V 粘贴，走 `insertBulk`（不发声、不逐字抢自动推进）。
struct PracticeInputSink: NSViewRepresentable {
    let engine: PracticeEngine
    let focusNonce: Int
    let onExit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        let textView = PracticeInputTextView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textColor = .clear
        textView.insertionPointColor = .clear
        textView.font = .systemFont(ofSize: 1)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        // 听写只比较 ASCII 字母/数字/连字符；关掉系统替换，避免弯引号、
        // 自动大写、智能破折号偷偷改写用户输入。
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.usesFindBar = false
        textView.alphaValue = 0.01
        textView.engine = engine
        textView.onExit = onExit
        container.addSubview(textView)
        context.coordinator.textView = textView
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        textView.engine = engine
        textView.onExit = onExit
        if context.coordinator.lastFocusNonce != focusNonce {
            context.coordinator.lastFocusNonce = focusNonce
            context.coordinator.focus(textView)
        }
    }

    final class Coordinator {
        weak var textView: PracticeInputTextView?
        var lastFocusNonce = Int.min

        func focus(_ textView: PracticeInputTextView) {
            DispatchQueue.main.async {
                guard let window = textView.window else { return }
                if window.firstResponder !== textView {
                    window.makeFirstResponder(textView)
                }
            }
        }
    }
}

/// 只做输入法/粘贴接收的 NSTextView。
final class PracticeInputTextView: NSTextView {
    weak var engine: PracticeEngine?
    var onExit: (() -> Void)?
    /// 默认真实剪贴板；自检可注入独立 pasteboard，避免碰用户剪贴板
    var pasteboard: NSPasteboard = .general

    private var isClearing = false
    /// discardPendingComposition 触发的输入法回调可能在同一 runloop 里再次进
    /// insertText；这一轮内全部忽略，避免把已取消的候选当成真实字母。
    private var isDiscarding = false

    override var acceptsFirstResponder: Bool { true }

    /// 所有可打印文本都从这里进来。这里不按输入源前缀分流：
    /// 真实单字母、输入法提交、粘贴都在同一条原生路径上区分。
    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard !isDiscarding else { return }
        let text = (string as? String)
            ?? (string as? NSAttributedString)?.string
            ?? ""
        guard !text.isEmpty else { return }

        // 输入法组字/提交：先让输入法把标记文本收尾，再按批量入口处理，
        // 不逐字发声，也不会把拼音候选重复计入。
        if hasMarkedText() {
            super.insertText(string, replacementRange: replacementRange)
            scheduleCommittedText()
            return
        }

        // 真实单字符：直接落空并触发一次音效；不写入文本视图。
        if text.count == 1, let ch = text.first {
            if ch == " " {
                engine?.advanceBlank()
                return
            }
            if ch == "\n" || ch == "\r" {
                engine?.primaryAction()
                return
            }
            // 数字键在练习窗是功能键（1 打开菜单、2…8 是练习动作），不作为真实答案输入；
            // 这里只接字母/连字符/撇号。整句粘贴仍走下面的批量入口。
            if ch.isASCII, ch.isLetter || ch == "-" || ch == "'" {
                engine?.typeCharacter(ch)
                return
            }
        }

        // 粘贴 / 多字符替换 / 非 ASCII 提交：批量入口，不发声。
        engine?.insertBulk(text)
    }

    /// 切回普通键盘后，输入法可能还留着标记文本或已经取消的候选字符串。
    /// 在真实单字母直通前清掉它，避免残留把后续字母全按批量/无声路径处理。
    func discardPendingComposition() {
        isDiscarding = true
        isClearing = true
        NSTextInputContext.current?.discardMarkedText()
        if hasMarkedText() { unmarkText() }
        if !string.isEmpty { string = "" }
        setSelectedRange(NSRange(location: 0, length: 0))
        isClearing = false
        Diag.log("practice: discarded stale composition before direct key")
        // 输入法可能在同一个 runloop 里再回调一次 insertText；等这一轮过去
        // 再恢复接收，避免把已取消的候选字母补进答案。
        DispatchQueue.main.async { [weak self] in
            self?.isDiscarding = false
        }
    }

    /// 不依赖系统 Edit 菜单/快捷键分发：菜单 paste 也直接走逐空批量入口。
    override func paste(_ sender: Any?) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        engine?.insertBulk(text)
    }

    override func didChangeText() {
        super.didChangeText()
        scheduleCommittedText()
    }

    // 下面是兜底：正常情况下 AppDelegate 的 keyDown 监听会先接住这些键。
    override func insertNewline(_ sender: Any?) { engine?.primaryAction() }
    override func deleteBackward(_ sender: Any?) { engine?.deleteBackward() }
    override func insertTab(_ sender: Any?) { engine?.advanceBlank() }
    override func cancelOperation(_ sender: Any?) { onExit?() }

    /// 输入法提交的批量文本：不发声，也不逐字触发自动推进。
    /// 组字过程中（hasMarkedText）不处理，避免把拼音/候选词重复计入。
    private func scheduleCommittedText() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.hasMarkedText(), !self.isClearing, !self.isDiscarding else { return }
            let text = self.string
            guard !text.isEmpty else { return }
            self.isClearing = true
            self.string = ""
            self.isClearing = false
            self.engine?.insertBulk(text)
        }
    }
}
