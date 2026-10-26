import AppKit
import SwiftUI
import Combine
import Translation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings = Settings()
    let state = PlayerState()
    let watcher = MusicWatcher()
    let bank = QuestionBank()
    let mistakes = MistakeBook()
    private(set) var practice: PracticeEngine!
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var cancellables: Set<AnyCancellable> = []
    private var sizeBeforePractice: (Double, Double)?
    private var contextMenuMonitor: Any?
    private var practiceKeyMonitor: Any?
    private var libraryWindow: LibraryWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let demo = CommandLine.arguments.contains("--demo") || UserDefaults.standard.bool(forKey: "demoMode")
        practice = PracticeEngine(
            state: state,
            watcher: demo ? NoopMusicController() : watcher,
            settings: settings,
            bank: bank,
            mistakes: mistakes
        )
        overlay = OverlayController(
            state: state,
            settings: settings,
            practice: practice,
            bank: bank,
            mistakes: mistakes
        )
        installContextMenu()
        installPracticeKeyMonitor()
        practice.onRequestFocus = { [weak self] in
            self?.overlay.focusForKeyInput()
        }
        state.targetLanguage = settings.targetLanguage
        state.setTranslationEnabled(settings.showTranslation)

        watcher.onSnapshot = { [weak self] snap in
            self?.state.ingest(snap)
        }
        watcher.onProblem = { [weak self] msg in
            self?.state.setHint(msg)
        }
        if !demo { watcher.start() }

        state.translator.onNeedsDownload = { [weak self] in
            guard let self else { return }
            self.overlay.show()
            NSApp.activate(ignoringOtherApps: true)
        }

        buildStatusItem()
        overlay.setVisible(settings.visible)

        // 上次退出时停在练习模式：把引擎也一起恢复，否则界面和状态会对不上
        if settings.practiceMode {
            practice.setEnabled(true)
            applyPracticeLayout(true)   // 窗口也要恢复到能答题的尺寸
        }

        if demo {
            Diag.log("demo mode start")
            // 演示模式只用内置原创素材，避免把真实曲库或商业歌词带进截图。
            let practiceDemo = settings.practiceMode
            let first = DemoFixtures.paperLanterns
            state.debugInject(
                track: first.track,
                position: practiceDemo ? 12 : 33.5,
                playing: true,
                lines: first.lines,
                translations: first.translations
            )
            if !practiceDemo {
                // 12 秒后切到第二首原创示例，用来验证“换歌后仍能翻译”
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                    Diag.log("demo switch track")
                    let second = DemoFixtures.signalFires
                    self?.state.debugInject(
                        track: second.track,
                        position: 20,
                        playing: true,
                        lines: second.lines,
                        translations: second.translations
                    )
                }
            }

            // 调试用：直接从题库出题（不播放、不控制音乐）
            if CommandLine.arguments.contains("--practice-bank") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    guard let self else { return }
                    self.settings.practiceMode = true
                    self.practice.begin(source: .bank, ratio: self.settings.practiceRatio)
                }
            }

            // 调试用：不等播放边界，直接进答题态，方便验证键盘输入（演示模式不控制音乐）
            if CommandLine.arguments.contains("--practice-ask") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.practice.debugForceAsking()
                }
            }
        }

        settings.$targetLanguageID
            .dropFirst()
            .sink { [weak self] id in
                self?.state.setTargetLanguage(Locale.Language(identifier: id))
            }
            .store(in: &cancellables)

        settings.$showTranslation
            .dropFirst()
            .sink { [weak self] on in
                self?.state.setTranslationEnabled(on)
            }
            .store(in: &cancellables)

        settings.$practiceMode
            .dropFirst()
            .sink { [weak self] on in
                guard let self else { return }
                self.practice.setEnabled(on)
                self.applyPracticeLayout(on)
            }
            .store(in: &cancellables)
    }

    /// 听写需要更大的窗口；退出时恢复原来的尺寸
    private func applyPracticeLayout(_ on: Bool) {
        if on {
            if settings.panelHeight < 320 {
                sizeBeforePractice = (settings.panelWidth, settings.panelHeight)
                settings.setSize(width: max(720, settings.panelWidth), height: 400)
            }
            overlay.show()
            overlay.focusForKeyInput()
        } else if let saved = sizeBeforePractice {
            settings.setSize(width: saved.0, height: saved.1)
            sizeBeforePractice = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
    }

    // MARK: 菜单栏

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "GapSong")
            button.image?.isTemplate = true
        }
        let menu = makeMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    /// 菜单的启用状态由我们自己维护（空库入口要稳定置灰），关闭 AppKit 的自动启用
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

    /// 歌词窗右键用的原生菜单：与状态栏菜单同一套动作。
    /// 不走 SwiftUI 的 contextMenu —— 歌词窗 20fps 刷新会让菜单反复重建、闪烁。
    private func installContextMenu() {
        // 兜底：事件先到面板（非激活 App 右键偶尔不进 local monitor）
        overlay.contextMenuHandler = { [weak self] event in
            guard let self, let view = event.window?.contentView else { return }
            NSMenu.popUpContextMenu(self.makeContextMenu(), with: event, for: view)
        }

        contextMenuMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self,
                  let window = event.window,
                  window === self.overlay.window,
                  let view = window.contentView else { return event }
            NSMenu.popUpContextMenu(self.makeContextMenu(), with: event, for: view)
            return nil
        }
    }

    /// 练习时的键盘约定：
    /// - 空格：切换当前要填的横线（用户不必填满所有空）
    /// - ⌘A / Shift+方向键：暂不提供选中文字，直接吃掉
    private func installPracticeKeyMonitor() {
        practiceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === self.overlay.window,
                  self.settings.practiceMode else { return event }

            // 输入法正在组字：空格和方向键先给输入法
            if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() {
                return event
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // 不提供选中文字：⌘A 与 Shift+方向键都不做选区
            if flags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "a" {
                return nil
            }
            if flags.contains(.shift),
               [123, 124, 125, 126, 115, 116, 119, 121].contains(Int(event.keyCode)) {
                return nil
            }

            // 纯空格：切到下一个横线（带修饰键的空格留给输入法/系统）
            if event.keyCode == 49, flags.isEmpty, self.practice.phase == .asking {
                self.practice.advanceBlank()
                return nil
            }
            return event
        }
    }

    private func makeContextMenu() -> NSMenu {
        let menu = makeMenu()
        populate(menu)
        return menu
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = NSMenuItem(
            title: settings.visible ? "隐藏歌词窗" : "显示歌词窗",
            action: #selector(toggleOverlay), keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let trans = NSMenuItem(
            title: "显示翻译", action: #selector(toggleTranslation), keyEquivalent: ""
        )
        trans.target = self
        trans.state = settings.showTranslation ? .on : .off
        menu.addItem(trans)

        let practiceItem = NSMenuItem(
            title: settings.practiceMode ? "退出练习" : "开始练习（听写）…",
            action: #selector(togglePractice), keyEquivalent: "l"
        )
        practiceItem.target = self
        practiceItem.state = settings.practiceMode ? .on : .off
        menu.addItem(practiceItem)

        // 直接入口：右键菜单与菜单栏共用；空库也保留并置灰解释
        menu.addItem(quickPracticeItem(
            title: "练当前歌曲", count: songPracticeCount, unit: "句",
            emptyHint: "先播放一首英文歌", action: #selector(practiceSong)
        ))
        menu.addItem(quickPracticeItem(
            title: "练收藏歌词", count: bank.count, unit: "句",
            emptyHint: "在歌词右侧点书签收藏", action: #selector(practiceFavorites)
        ))
        menu.addItem(quickPracticeItem(
            title: "练错题本", count: mistakes.count, unit: "条",
            emptyHint: "答错后自动记录", action: #selector(practiceMistakes)
        ))

        let viewLibraryItem = NSMenuItem(
            title: "查看收藏与错题…", action: #selector(openLibrary), keyEquivalent: ""
        )
        viewLibraryItem.target = self
        menu.addItem(viewLibraryItem)

        let practiceMenu = makeMenu()

        let intensityMenu = makeMenu()
        for value in Settings.practiceRatioChoices {
            let item = NSMenuItem(
                title: "填空 \(Settings.ratioLabel(value))",
                action: #selector(setPracticeRatio(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = value
            item.state = abs(settings.practiceRatio - value) < 0.001 ? .on : .off
            intensityMenu.addItem(item)
        }
        let intensityItem = NSMenuItem(
            title: "练习强度（\(settings.practiceRatioLabel)）", action: nil, keyEquivalent: ""
        )
        intensityItem.submenu = intensityMenu
        practiceMenu.addItem(intensityItem)

        practiceMenu.addItem(quickPracticeItem(
            title: "练当前歌曲", count: songPracticeCount, unit: "句",
            emptyHint: "先播放一首英文歌", action: #selector(practiceSong)
        ))
        practiceMenu.addItem(quickPracticeItem(
            title: "练收藏歌词", count: bank.count, unit: "句",
            emptyHint: "在歌词右侧点书签收藏", action: #selector(practiceFavorites)
        ))
        practiceMenu.addItem(quickPracticeItem(
            title: "练错题本", count: mistakes.count, unit: "条",
            emptyHint: "答错后自动记录", action: #selector(practiceMistakes)
        ))

        practiceMenu.addItem(.separator())
        let setupItem = NSMenuItem(
            title: "返回设置页", action: #selector(returnToSetup), keyEquivalent: ""
        )
        setupItem.target = self
        practiceMenu.addItem(setupItem)

        let practiceSub = NSMenuItem(title: "练习选项", action: nil, keyEquivalent: "")
        practiceSub.submenu = practiceMenu
        menu.addItem(practiceSub)

        let bankMenu = makeMenu()
        let viewFavorites = NSMenuItem(
            title: "查看收藏…", action: #selector(openLibrary), keyEquivalent: ""
        )
        viewFavorites.target = self
        bankMenu.addItem(viewFavorites)
        let clearBankItem = NSMenuItem(
            title: "清空收藏…", action: #selector(clearFavorites), keyEquivalent: ""
        )
        clearBankItem.target = self
        clearBankItem.isEnabled = bank.count > 0
        bankMenu.addItem(clearBankItem)
        let bankItem = NSMenuItem(title: "收藏歌词（\(bank.count) 句）", action: nil, keyEquivalent: "")
        bankItem.submenu = bankMenu
        menu.addItem(bankItem)

        let mistakeMenu = makeMenu()
        let viewMistakes = NSMenuItem(
            title: "查看错题本…", action: #selector(openMistakesLibrary), keyEquivalent: ""
        )
        viewMistakes.target = self
        mistakeMenu.addItem(viewMistakes)
        let clearMistakesItem = NSMenuItem(
            title: "清空错题本…", action: #selector(clearMistakes), keyEquivalent: ""
        )
        clearMistakesItem.target = self
        clearMistakesItem.isEnabled = mistakes.count > 0
        mistakeMenu.addItem(clearMistakesItem)
        let mistakeItem = NSMenuItem(title: "错题本（\(mistakes.count) 条）", action: nil, keyEquivalent: "")
        mistakeItem.submenu = mistakeMenu
        menu.addItem(mistakeItem)

        let lock = NSMenuItem(
            title: "锁定位置", action: #selector(toggleLock), keyEquivalent: ""
        )
        lock.target = self
        lock.state = settings.locked ? .on : .off
        menu.addItem(lock)

        menu.addItem(.separator())

        let fontMenu = makeMenu()
        for (title, size) in [("小", 18.0), ("标准", 24.0), ("大", 30.0), ("特大", 38.0)] {
            let item = NSMenuItem(title: title, action: #selector(setFont(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size
            item.state = abs(settings.fontSize - size) < 0.5 ? .on : .off
            fontMenu.addItem(item)
        }
        fontMenu.addItem(.separator())
        let bigger = NSMenuItem(title: "放大字号", action: #selector(fontUp), keyEquivalent: "=")
        bigger.target = self
        fontMenu.addItem(bigger)
        let smaller = NSMenuItem(title: "缩小字号", action: #selector(fontDown), keyEquivalent: "-")
        smaller.target = self
        fontMenu.addItem(smaller)
        let fontItem = NSMenuItem(title: "字号（当前 \(Int(settings.fontSize))）", action: nil, keyEquivalent: "")
        fontItem.submenu = fontMenu
        menu.addItem(fontItem)

        let sizeMenu = makeMenu()
        for (title, w, h) in [("紧凑", 836.0, 155.0), ("标准", 900.0, 320.0), ("大", 1000.0, 520.0), ("宽屏", 1200.0, 600.0)] {
            let item = NSMenuItem(title: title, action: #selector(setWindowSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [w, h]
            item.state = (abs(settings.panelWidth - w) < 1 && abs(settings.panelHeight - h) < 1) ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "窗口大小", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let fullItem = NSMenuItem(title: "全文模式", action: #selector(toggleFull), keyEquivalent: "")
        fullItem.target = self
        fullItem.state = settings.forceFull ? .on : .off
        menu.addItem(fullItem)

        let langMenu = makeMenu()
        for (title, id) in [("简体中文", "zh-Hans"), ("繁體中文", "zh-Hant"), ("English", "en"), ("日本語", "ja"), ("한국어", "ko")] {
            let item = NSMenuItem(title: title, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = settings.targetLanguageID == id ? .on : .off
            langMenu.addItem(item)
        }
        let langItem = NSMenuItem(title: "翻译为", action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        menu.addItem(langItem)

        menu.addItem(.separator())

        let reloadItem = NSMenuItem(title: "重新匹配歌词", action: #selector(reloadLyrics), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let retryItem = NSMenuItem(title: "重试翻译", action: #selector(retryTranslation), keyEquivalent: "")
        retryItem.target = self
        menu.addItem(retryItem)

        if let source = state.lyrics?.source {
            let info = NSMenuItem(title: "歌词来源：\(source)", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }
        if case .unavailable(let msg) = state.translator.status {
            let info = NSMenuItem(title: msg, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 GapSong", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: 动作

    @objc private func toggleOverlay() { settings.visible.toggle() }

    @objc private func toggleTranslation() { settings.showTranslation.toggle() }

    @objc private func togglePractice() { settings.practiceMode.toggle() }

    @objc private func setPracticeRatio(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        // 正在练：当前这句立刻按新强度重挖；在设置页：只改偏好
        if settings.practiceMode, practice.phase != .setup {
            practice.changeRatio(value)
        } else {
            settings.practiceRatio = value
        }
    }

    @objc private func practiceSong() {
        startPractice(source: .song, onlyID: nil)
    }

    @objc private func practiceFavorites() {
        startPractice(source: .bank, onlyID: nil)
    }

    @objc private func practiceMistakes() {
        startPractice(source: .mistakes, onlyID: nil)
    }

    @objc private func openLibrary() {
        showLibrary(tab: .favorites)
    }

    @objc private func openMistakesLibrary() {
        showLibrary(tab: .mistakes)
    }

    @objc private func clearFavorites() {
        confirmClearFavorites()
    }

    @objc private func clearMistakes() {
        confirmClearMistakes()
    }

    @objc private func returnToSetup() {
        settings.practiceMode = true
        practice.returnToSetup()
    }

    /// 统一从菜单/管理窗口开始练习；onlyID 表示只练某一条收藏或错题
    private func startPractice(source: PracticeEngine.Source, onlyID: UUID?) {
        libraryWindow?.closeWindow()
        if !settings.practiceMode {
            settings.practiceMode = true
        }
        practice.begin(source: source, ratio: settings.practiceRatio, onlyID: onlyID)
        overlay.show()
        overlay.focusForKeyInput()
    }

    private func showLibrary(tab: LibraryTab) {
        if libraryWindow == nil {
            libraryWindow = LibraryWindowController(
                favorites: bank,
                mistakes: mistakes,
                initialTab: tab,
                onPracticeFavorite: { [weak self] id in
                    self?.startPractice(source: .bank, onlyID: id)
                },
                onPracticeAllFavorites: { [weak self] in
                    self?.startPractice(source: .bank, onlyID: nil)
                },
                onPracticeMistake: { [weak self] id in
                    self?.startPractice(source: .mistakes, onlyID: id)
                },
                onPracticeAllMistakes: { [weak self] in
                    self?.startPractice(source: .mistakes, onlyID: nil)
                },
                onClearFavorites: { [weak self] in
                    self?.confirmClearFavorites()
                },
                onClearMistakes: { [weak self] in
                    self?.confirmClearMistakes()
                }
            )
        }
        libraryWindow?.show(tab: tab)
    }

    private func confirmClearFavorites() {
        showClearConfirmation(
            title: "清空收藏歌词？",
            message: "将删除全部 \(bank.count) 句收藏，错题本不受影响。此操作不可撤销。"
        ) { [weak self] in
            self?.bank.clear()
        }
    }

    private func confirmClearMistakes() {
        showClearConfirmation(
            title: "清空错题本？",
            message: "将删除全部 \(mistakes.count) 条错题及其 \(mistakes.totalAttempts) 次错误历史。此操作不可撤销。"
        ) { [weak self] in
            self?.mistakes.clear()
        }
    }

    private func showClearConfirmation(title: String, message: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            action()
        }
    }

    /// 菜单里的“练 X（N）”入口：空库保留但置灰，并解释怎么产生内容
    private func quickPracticeItem(
        title: String,
        count: Int,
        unit: String,
        emptyHint: String,
        action: Selector
    ) -> NSMenuItem {
        let text = count > 0
            ? "\(title)（\(count) \(unit)）"
            : "\(title)（0 \(unit)，\(emptyHint)）"
        let item = NSMenuItem(title: text, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = count > 0
        return item
    }

    /// 当前歌曲里可听写的句数（菜单里显示）
    private var songPracticeCount: Int {
        guard let lyrics = state.lyrics, !lyrics.lines.isEmpty else { return 0 }
        return PracticeFilter.practiceableIndices(
            lines: lyrics.lines,
            trackDuration: state.snapshot?.track.duration ?? 0
        ).count
    }

    @objc private func toggleLock() { settings.locked.toggle() }

    @objc private func setFont(_ sender: NSMenuItem) {
        if let size = sender.representedObject as? Double { settings.fontSize = size }
    }

    @objc private func fontUp() { settings.bumpFont(by: 2) }

    @objc private func fontDown() { settings.bumpFont(by: -2) }

    @objc private func setWindowSize(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? [Double], v.count == 2 else { return }
        settings.setSize(width: v[0], height: v[1])
    }

    @objc private func toggleFull() { settings.forceFull.toggle() }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { settings.targetLanguageID = id }
    }

    @objc private func reloadLyrics() {
        state.reload()
    }

    @objc private func retryTranslation() {
        state.translator.retry()
        state.reload()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
