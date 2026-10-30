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
    /// 1 打开的窗口内键盘菜单：不依赖鼠标也能完成所有操作
    let menu = CommandMenu()
    private(set) var practice: PracticeEngine!
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var cancellables: Set<AnyCancellable> = []
    private var sizeBeforePractice: (width: Double, height: Double)?
    private var contextMenuMonitor: Any?
    private var practiceKeyMonitor: Any?
    /// 字号快捷键：菜单项与本地 keyDown 监视器共用
    private var fontShortcuts: FontShortcutMonitor?
    /// 只在输入源变化时写一条诊断，避免每个字母刷日志
    private var lastLoggedInputSource: String?
    private var libraryWindow: LibraryWindowController?
    /// 是否真的控制 Music：隔离/演示运行不碰真实播放，管理窗口也不暂停音乐
    private var controlsMusic = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 偏好一律走注入的 suite：隔离启动绝不读真实偏好的 demoMode
        let demo = CommandLine.arguments.contains("--demo") || settings.store.bool(forKey: "demoMode")
        // 隔离/演示运行不启动真实播放链路：不轮询 Music，也不触发自动化授权
        let controlMusic = !demo && !AppRuntime.isIsolated
        controlsMusic = controlMusic
        practice = PracticeEngine(
            state: state,
            watcher: controlMusic ? watcher : NoopMusicController(),
            settings: settings,
            bank: bank,
            mistakes: mistakes
        )
        // 隔离/快照/自检绝不真的发声；正常运行时用本地合成的键击音
        practice.typingSoundPlayer = AppRuntime.isIsolated
            ? SilentTypingSoundPlayer()
            : TypewriterSoundPlayer()
        // 英语朗读同理：隔离运行保持静默，正常 App 才接 Apple 原生 TTS
        if !AppRuntime.isIsolated {
            practice.installSpeechSpeaker(AppleSpeechSpeaker())
        }
        overlay = OverlayController(
            state: state,
            settings: settings,
            practice: practice,
            bank: bank,
            mistakes: mistakes,
            menu: menu
        )
        // 键盘菜单与真实状态解耦：每次按 1 打开时用当前偏好/数量生成一页
        menu.rootProvider = { [weak self] in
            guard let self else { return [] }
            return CommandMenuCatalog.root(self.menuContext())
        }
        menu.onPerform = { [weak self] action in
            self?.perform(action)
        }
        menu.onOpenChange = { [weak self] open in
            guard let self else { return }
            self.overlay.setMenuLayout(open)
            if open { self.overlay.focusForMenu() }
        }
        installContextMenu()
        // 状态栏/右键菜单不是 mainMenu，菜单关闭时 ⌘= / ⌘- 不会被 AppKit 自动路由，
        // 所以在本地 keyDown 监视器里显式接住，只处理 GapSong 自己的窗口。
        let fontShortcuts = FontShortcutMonitor(settings: settings) { window in
            NSApp.windows.contains { $0 === window }
        }
        fontShortcuts.install()
        self.fontShortcuts = fontShortcuts
        installPracticeKeyMonitor()
        // 面板失去键盘焦点时收起菜单：用户去点别的窗口后不会留下一个
        // 一直「暂停练习按键」的菜单，也不会把窗口停在临时加大的尺寸。
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: overlay.window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.menu.close() }
        }
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
        watcher.onProblemKind = { [weak self] problem in
            self?.state.setHint(problem.message)
            self?.practice.reportMusicProblem(problem)
        }
        // 采样恢复正常后清掉过期的授权/控制提示（练习里的异常仍由用户显式处理）
        watcher.onRecovered = { [weak self] in
            self?.state.clearHint()
        }
        if controlMusic { watcher.start() }

        // 演示/隔离运行不要去触发系统语言包下载弹窗
        if controlMusic {
            state.translator.onNeedsDownload = { [weak self] in
                guard let self else { return }
                self.overlay.show()
                NSApp.activate(ignoringOtherApps: true)
            }
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

            // 验收用：只在隔离数据目录里预置演示收藏与错题，绝不写真实数据
            if CommandLine.arguments.contains("--demo-seed") {
                if AppRuntime.isIsolated {
                    seedDemoLibrary()
                } else {
                    Diag.log("demo-seed refused: 需要 GAPSONG_ISOLATED=1")
                    print("⚠️ --demo-seed 只在隔离运行（GAPSONG_ISOLATED=1）下写入，已跳过")
                }
            }

            // 验收用：模拟练习中的播放异常（不发任何真实播放命令）
            if CommandLine.arguments.contains("--practice-playback-error") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    self?.practice.reportMusicProblem(.unauthorized)
                }
            }

            // 验收用：直接打开收藏/错题管理窗口
            if CommandLine.arguments.contains("--demo-library") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.showLibrary(tab: .favorites)
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
                // 换模式时菜单不该继续盖着（动作本身会先关菜单，这里是兜底）
                self.menu.close()
                self.practice.setEnabled(on)
                self.applyPracticeLayout(on)
            }
            .store(in: &cancellables)

        settings.$visible
            .dropFirst()
            .sink { [weak self] visible in
                // 窗口被隐藏时菜单也必须收起，否则下次显示还停在菜单层
                if !visible { self?.menu.close() }
            }
            .store(in: &cancellables)
    }

    /// 听写需要更大的窗口；退出时恢复「歌词态」记住的尺寸（跨重启也生效）。
    ///
    /// 关键：练习态写回的 panelWidth/Height 不覆盖 lyricPanel*，所以
    /// 「启动时 practiceMode 已经是 true」也能在退出练习后回到原来的紧凑尺寸。
    private func applyPracticeLayout(_ on: Bool) {
        if on {
            // 先记下进入练习前的歌词态尺寸，再放大窗口（顺序不能反）
            settings.captureLyricSizeIfNeeded()
            sizeBeforePractice = settings.rememberedLyricSize
            let targetW = max(Settings.practiceComfortableSize.width, settings.panelWidth)
            let targetH = max(Settings.practiceMinSize.height, Settings.practiceComfortableSize.height)
            if settings.panelWidth < targetW || settings.panelHeight < targetH {
                settings.setSize(width: targetW, height: targetH)
            }
            overlay.show()
            overlay.focusForKeyInput()
        } else {
            let remembered = sizeBeforePractice ?? settings.rememberedLyricSize
            sizeBeforePractice = nil
            settings.setSize(width: remembered.width, height: remembered.height)
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
            // 键盘菜单打开时是模态的：右键不再叠一个原生菜单
            guard let self, !self.menu.isOpen, let view = event.window?.contentView else { return }
            NSMenu.popUpContextMenu(self.makeContextMenu(), with: event, for: view)
        }

        contextMenuMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self,
                  let window = event.window,
                  window === self.overlay.window,
                  let view = window.contentView else { return event }
            guard !self.menu.isOpen else { return nil }
            NSMenu.popUpContextMenu(self.makeContextMenu(), with: event, for: view)
            return nil
        }
    }

    /// 窗口内键盘入口：菜单、练习数字命令、英文直输、粘贴都在这里分流。
    ///
    /// 1 固定打开键盘菜单（歌词态与练习态都适用）；菜单打开期间练习按键全部暂停，
    /// 数字 1…9 只用于选菜单项，0/Esc 返回/关闭；其余按键（含 ⌘V / ⌘R）也会被吞掉，
    /// 不会把字或旧快捷键漏进菜单后面的练习。字号快捷键在菜单之前处理，仍然可用。
    ///
    /// 菜单关闭时（仅练习态）：
    /// - 2…8：重听/朗读、看答案/再试、主操作、跳过、设置、返回、歌曲清晰朗读
    /// - 字母/连字符/撇号：直接写入当前空；数字键只做功能，不落字
    /// - 空格：切到下一个空，末尾回到第一个未填的空
    /// - 退格：删当前空，删空后回到上一个空
    /// - ⏎：提交/下一句/再来一遍（主提示仍是回车）
    /// - Esc：兼容退出练习回歌词（主提示是 7）
    private func installPracticeKeyMonitor() {
        practiceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = event.window else { return event }

            // 字号快捷键在菜单和输入路径之前消费：⌘=/⌘+/⌘- 只改字号，
            // 不会把 =/+/- 写进答案，也不触发打字机音效。
            if self.fontShortcuts?.handle(event) == true { return nil }

            guard window === self.overlay.window else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasModifier = flags.contains(.command)
                || flags.contains(.control)
                || flags.contains(.option)

            // A) 菜单打开：数字索引，0/Esc 返回；其余按键（包括 ⌘V / ⌘R 等
            //    会打到菜单后面按钮的组合）一律吞掉，避免菜单期间改动练习。
            //    字号快捷键已在上面处理，⌘= / ⌘- 仍可用。
            if self.menu.isOpen {
                if hasModifier { return nil }
                if event.keyCode == 53 {            // Esc
                    self.menu.back()
                    return nil
                }
                if let digit = PracticeNumericKeys.digit(forKeyCode: event.keyCode),
                   !flags.contains(.shift) {
                    if digit == 0 {
                        self.menu.back()
                    } else {
                        self.menu.select(digit)
                    }
                }
                return nil
            }

            // 1) 1 是菜单进入键：歌词态和练习态都先处理它
            let keyIntent = PracticeKeyRouting.intent(
                keyCode: event.keyCode,
                modifiers: flags,
                characters: event.charactersIgnoringModifiers
            )
            if case .openMenu = keyIntent {
                // 打开菜单前清掉练习框里残留的组字/候选，
                // 否则输入法提交的文字可能绕过菜单写进答案
                if let textView = window.firstResponder as? PracticeInputTextView,
                   textView.hasMarkedText() || !textView.string.isEmpty {
                    textView.discardPendingComposition()
                }
                self.menu.open()
                return nil
            }

            // 歌词态只接管菜单键，其余按键还给系统
            guard self.settings.practiceMode else { return event }

            let editor = event.window?.firstResponder as? NSTextView
            // 练习窗不使用输入法选字：任何键到来时先清掉残留组字/候选。
            if let textView = editor as? PracticeInputTextView,
               textView.hasMarkedText() || !textView.string.isEmpty {
                textView.discardPendingComposition()
            }

            // 2) 设置页：2 减少比例、3 增加比例；
            //    这两个键在设置页没有练习动作，不会落到 `PracticeEngine.perform`。
            if self.practice.phase == .setup {
                switch keyIntent {
                case .command(.replayOrRead):
                    self.practice.adjustSetupRatio(by: -1)
                    return nil
                case .command(.revealOrRetry):
                    self.practice.adjustSetupRatio(by: 1)
                    return nil
                default:
                    break
                }
            }

            // 3) 数字命令必须先于输入法候选/marked text：
            //    2…8 直接执行动作；9、0 没有命令也消费。
            //    数字不作为真实按键输入，不写答案、不响音效、不选候选。
            switch keyIntent {
            case .command(let command):
                self.practice.perform(command)
                return nil
            case .consumedDigit:
                return nil
            case .openMenu, .letter, .passThrough:
                break
            }

            let source = NSTextInputContext.current?.selectedKeyboardInputSource
            let plainLayout = PracticeInputRouting.isPlainKeyboardLayout(
                source: source,
                hasMarkedText: editor?.hasMarkedText() ?? false
            )
            if source != self.lastLoggedInputSource {
                self.lastLoggedInputSource = source
                Diag.log("practice: input source \(source ?? "nil") plain=\(plainLayout)")
            }

            let phase = self.practice.phase

            // 3) 粘贴先于组字处理：只读剪贴板，不覆盖用户内容，也不发声。
            if flags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "v" {
                guard phase == .asking || phase == .listening else { return event }
                if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                    self.practice.insertBulk(text)
                }
                return nil
            }

            // 4) 其余带 ⌘/⌃/⌥ 的按键留给菜单、按钮和系统输入法切换
            if hasModifier { return event }

            // Esc 兼容退出；界面主提示是 7 返回
            if event.keyCode == 53 {
                self.practice.exitPractice()
                return nil
            }

            switch event.keyCode {
            case 36, 76:   // Return / keypad Enter
                switch phase {
                case .asking, .listening, .revealed, .idle:
                    self.practice.primaryAction()
                    return nil
                case .setup:
                    return event
                }
            case 49:       // Space
                if phase == .asking || phase == .listening {
                    self.practice.advanceBlank()
                    return nil
                }
            case 51:       // Delete / Backspace
                if phase == .asking || phase == .listening {
                    self.practice.deleteBackward()
                    return nil
                }
            default:
                break
            }

            guard phase == .asking || phase == .listening else { return event }
            // 5) 英文字母直接直通（即使系统当前是中文输入法）：
            //    一次按键 = 一次落字 = 一次音效，不弹候选、不等上屏。
            if case .letter(let ch) = keyIntent {
                self.practice.typeCharacter(ch)
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

        // 键盘优先入口：不需要鼠标也能完成本菜单里的所有操作
        let commandMenu = NSMenuItem(
            title: "键盘菜单（按 1）", action: #selector(openCommandMenu), keyEquivalent: ""
        )
        commandMenu.target = self
        menu.addItem(commandMenu)
        menu.addItem(.separator())

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
            emptyHint: songEmptyHint, action: #selector(practiceSong)
        ))
        menu.addItem(quickPracticeItem(
            title: "练收藏歌词", count: bank.count, unit: "句",
            emptyHint: "全文模式下点歌词右侧书签收藏", action: #selector(practiceFavorites)
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

        // 句末停顿补偿：LRC 整体偏移时用这里自救（默认延后 0.2s）
        let tailMenu = makeMenu()
        for value in Settings.practiceTailChoices {
            let item = NSMenuItem(
                title: Settings.practiceTailLabel(value),
                action: #selector(setPracticeTail(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = value
            item.state = abs(settings.practiceTail - value) < 0.001 ? .on : .off
            tailMenu.addItem(item)
        }
        let tailItem = NSMenuItem(
            title: "句末停得早/晚（\(settings.practiceTailLabel)）", action: nil, keyEquivalent: ""
        )
        tailItem.submenu = tailMenu
        practiceMenu.addItem(tailItem)

        let soundItem = NSMenuItem(
            title: "打字机音效", action: #selector(toggleTypingSound), keyEquivalent: ""
        )
        soundItem.target = self
        soundItem.state = settings.typingSound ? .on : .off
        practiceMenu.addItem(soundItem)

        practiceMenu.addItem(quickPracticeItem(
            title: "练当前歌曲", count: songPracticeCount, unit: "句",
            emptyHint: songEmptyHint, action: #selector(practiceSong)
        ))
        practiceMenu.addItem(quickPracticeItem(
            title: "练收藏歌词", count: bank.count, unit: "句",
            emptyHint: "全文模式下点歌词右侧书签收藏", action: #selector(practiceFavorites)
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

        // 背景透明度：只改窗口背景，文字/按钮保持清晰；默认「不透明」= 原有视觉
        let transparencyMenu = makeMenu()
        for value in Settings.backgroundTransparencyChoices {
            let item = NSMenuItem(
                title: Settings.backgroundTransparencyLabel(value),
                action: #selector(setBackgroundTransparency(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = value
            item.state = abs(settings.backgroundTransparency - value) < 0.001 ? .on : .off
            transparencyMenu.addItem(item)
        }
        let transparencyItem = NSMenuItem(
            title: "背景透明度（\(settings.backgroundTransparencyLabel)）",
            action: nil,
            keyEquivalent: ""
        )
        transparencyItem.submenu = transparencyMenu
        menu.addItem(transparencyItem)

        menu.addItem(.separator())

        let fontMenu = makeMenu()
        for preset in CommandMenuCatalog.fontPresets {
            let (title, size) = (preset.title, preset.size)
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
        for preset in CommandMenuCatalog.windowPresets {
            let (title, w, h) = (preset.title, preset.width, preset.height)
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
        for language in CommandMenuCatalog.languages {
            let (title, id) = (language.title, language.id)
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

    /// 所有菜单动作的唯一实现：窗口内键盘菜单、状态栏菜单和右键菜单共用，
    /// 避免两套菜单各自演化出不同的行为。
    private func perform(_ action: CommandAction) {
        switch action {
        case .toggleVisible:
            settings.visible.toggle()
        case .toggleTranslation:
            settings.showTranslation.toggle()
        case .togglePractice:
            settings.practiceMode.toggle()
        case .practiceSong:
            openPracticeSetup(source: .song)
        case .practiceFavorites:
            openPracticeSetup(source: .bank)
        case .practiceMistakes:
            openPracticeSetup(source: .mistakes)
        case .openLibrary:
            showLibrary(tab: .favorites)
        case .openMistakesLibrary:
            showLibrary(tab: .mistakes)
        case .clearFavorites:
            confirmClearFavorites()
        case .clearMistakes:
            confirmClearMistakes()
        case .setRatio(let value):
            // 正在练：当前这句立刻按新强度重挖；在设置页：只改偏好。
            // 选中当前档时引擎会直接返回，不会清空已填内容。
            if settings.practiceMode, practice.phase != .setup {
                practice.changeRatio(value)
            } else {
                settings.practiceRatio = value
            }
        case .setTail(let value):
            settings.practiceTail = value
        case .toggleTypingSound:
            settings.typingSound.toggle()
        case .toggleLock:
            settings.locked.toggle()
        case .setTransparency(let value):
            settings.backgroundTransparency = value
        case .setFont(let size):
            settings.fontSize = size
        case .fontUp:
            fontShortcuts?.applyFromMenu(.bigger)
        case .fontDown:
            fontShortcuts?.applyFromMenu(.smaller)
        case .setWindowSize(let width, let height):
            settings.setSize(width: width, height: height)
        case .toggleFull:
            settings.forceFull.toggle()
        case .setLanguage(let id):
            settings.targetLanguageID = id
        case .reloadLyrics:
            state.reload()
        case .retryTranslation:
            state.translator.retry()
            state.reload()
        case .returnToSetup:
            returnToSetup()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    /// 菜单内容：只取当前值，不在菜单里持有 Settings/引擎
    private func menuContext() -> CommandMenuContext {
        var context = CommandMenuContext()
        context.lyricsVisible = settings.visible
        context.showTranslation = settings.showTranslation
        context.practiceMode = settings.practiceMode
        context.songLineCount = songPracticeCount
        context.bankCount = bank.count
        context.mistakeCount = mistakes.count
        context.ratio = settings.practiceRatio
        context.tail = settings.practiceTail
        context.typingSound = settings.typingSound
        context.locked = settings.locked
        context.transparency = settings.backgroundTransparency
        context.fontSize = settings.fontSize
        context.fullMode = settings.forceFull
        context.languageID = settings.targetLanguageID
        context.panelWidth = settings.panelWidth
        context.panelHeight = settings.panelHeight
        context.lyricSource = state.lyrics?.source
        if case .unavailable(let message) = state.translator.status {
            context.translationNotice = message
        }
        return context
    }

    // MARK: 原生菜单入口（鼠标仍可用；行为统一走 perform）

    @objc private func openCommandMenu() {
        // 从原生菜单点进来时，菜单还在收尾；下一轮 runloop 再打开，
        // 避免在菜单追踪期间激活窗口
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // 窗口隐藏时从菜单栏点进来：先把窗口显示出来，避免菜单画在隐藏面板上
            if !self.settings.visible { self.settings.visible = true }
            self.menu.open()
        }
    }

    @objc private func toggleOverlay() { perform(.toggleVisible) }

    @objc private func toggleTranslation() { perform(.toggleTranslation) }

    @objc private func togglePractice() { perform(.togglePractice) }

    @objc private func setPracticeRatio(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        perform(.setRatio(value))
    }

    @objc private func setPracticeTail(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        perform(.setTail(value))
    }

    @objc private func toggleTypingSound() {
        perform(.toggleTypingSound)
    }

    @objc private func setBackgroundTransparency(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        perform(.setTransparency(value))
    }

    @objc private func practiceSong() {
        perform(.practiceSong)
    }

    @objc private func practiceFavorites() {
        perform(.practiceFavorites)
    }

    @objc private func practiceMistakes() {
        perform(.practiceMistakes)
    }

    @objc private func openLibrary() {
        perform(.openLibrary)
    }

    @objc private func openMistakesLibrary() {
        perform(.openMistakesLibrary)
    }

    @objc private func clearFavorites() {
        perform(.clearFavorites)
    }

    @objc private func clearMistakes() {
        perform(.clearMistakes)
    }

    @objc private func returnToSetup() {
        settings.practiceMode = true
        practice.returnToSetup()
    }

    /// 菜单里的「练当前歌曲 / 练收藏歌词 / 练错题本」：先进入只含填写比例的
    /// 设置页（来源随入口带入），用户按 2/3 调比例、4 开始；不再直接开练。
    private func openPracticeSetup(source: PracticeEngine.Source) {
        libraryWindow?.closeWindow()
        if !settings.practiceMode {
            settings.practiceMode = true       // sink 会放大窗口；下面再显式回到设置页
        }
        // 不依赖 sink 的执行顺序：显式重置到设置页，再带入来源，保证不会被默认来源覆盖
        practice.setEnabled(true)
        practice.selectSetupSource(source)
        overlay.show()
        overlay.focusForKeyInput()
    }

    /// 管理窗口「练这句 / 练全部」仍直接开始；onlyID 表示只练某一条
    private func startPractice(source: PracticeEngine.Source, onlyID: UUID?) {
        if !settings.practiceMode {
            settings.practiceMode = true
        }
        // 先开始练习，让引擎接手管理窗口暂停的音乐，再关窗口；
        // 否则关窗会先把音乐恢复一下，紧接着又被练习暂停，听众会听到一声。
        practice.begin(source: source, ratio: settings.practiceRatio, onlyID: onlyID)
        libraryWindow?.closeWindow()
        overlay.show()
        overlay.focusForKeyInput()
    }

    private func showLibrary(tab: LibraryTab) {
        // 进入「收藏与错题」管理窗口时先停住音乐：回看时不该有音乐盖着朗读/思考。
        // 关窗时恢复；如果从这里开始练习，暂停会交给练习会话，退出练习再恢复。
        if controlsMusic {
            practice.beginLibraryReview()
        }
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
                },
                confirmDelete: { [weak self] title, message in
                    self?.confirmDestructive(title: title, message: message) ?? false
                },
                onWindowClose: { [weak self] in
                    self?.practice.endLibraryReview()
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
            guard let self else { return }
            if !self.bank.clear() {
                self.showStorageError(self.bank.storageWarning ?? "收藏写入失败")
            }
        }
    }

    private func confirmClearMistakes() {
        showClearConfirmation(
            title: "清空错题本？",
            message: "将删除全部 \(mistakes.count) 条错题及其 \(mistakes.totalAttempts) 次错误历史。此操作不可撤销。"
        ) { [weak self] in
            guard let self else { return }
            if !self.mistakes.clear() {
                self.showStorageError(self.mistakes.saveError ?? "错题本写入失败")
            }
        }
    }

    /// 单条删除的确认框：点「取消」返回 false，调用方因此不会写文件
    private func confirmDestructive(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 写入失败必须看得见，不能只写日志
    private func showStorageError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "保存失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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

    /// 「练当前歌曲」空库时的解释：区分「没在播放」「歌词还在匹配」和「真的没有可练句」
    private var songEmptyHint: String {
        guard state.snapshot != nil else { return "先播放一首英文歌" }
        switch state.loadState {
        case .loading: return "歌词匹配中…"
        case .notFound: return "没有找到这首歌的歌词"
        case .failed: return "歌词加载失败"
        case .idle, .loaded: return "这首歌没有适合听写的英文句子"
        }
    }

    /// 只在隔离目录里预置演示收藏/错题（全部是原创演示素材）
    private func seedDemoLibrary() {
        let first = DemoFixtures.paperLanterns
        let samples: [(DemoFixtures.Song, String)] = [
            (first, DemoFixtures.firstLine),
            (first, DemoFixtures.secondLine),
            (first, DemoFixtures.thirdLine),
            (DemoFixtures.signalFires, "We lit signal fires on the eastern hill")
        ]
        for (song, text) in samples {
            let translation = song.translations[text]
            let time = song.lines.first(where: { $0.text == text })?.time ?? 0
            _ = bank.add(
                text: text, translation: translation,
                title: song.track.title, artist: song.track.artist, lineTime: time
            )
        }
        if mistakes.isEmpty {
            let target = PracticeQuestion(
                text: DemoFixtures.secondLine,
                translation: DemoFixtures.secondTranslation,
                title: first.track.title,
                artist: first.track.artist,
                start: 17.2, end: 22.4, lineTime: 17.2
            )
            for (offset, actual) in [0.0, 40.0].enumerated() {
                let attempt = MistakeAttempt(
                    submittedAt: Date().addingTimeInterval(-3600 * (offset == 0 ? 2 : 1)),
                    source: "song",
                    ratio: 0.6,
                    rawInput: "we folded paper lanterns",
                    translation: DemoFixtures.secondTranslation,
                    wasRetry: false,
                    blanks: [
                        MistakeBlank(ordinal: 0, wordIndex: 1, expected: "folded", actual: actual == 0 ? "fold" : "folded", skipped: false),
                        MistakeBlank(ordinal: 1, wordIndex: 2, expected: "paper", actual: "paper", skipped: false),
                        MistakeBlank(ordinal: 2, wordIndex: 3, expected: "lanterns", actual: "lanters", skipped: false)
                    ]
                )
                _ = mistakes.record(question: target, translation: DemoFixtures.secondTranslation, attempt: attempt)
            }
        }
        Diag.log("demo-seed: bank=\(bank.count) mistakes=\(mistakes.count)")
        print("✅ demo seed: 收藏 \(bank.count) 句 · 错题 \(mistakes.count) 条（隔离目录 \(Paths.data.path)）")
    }

    /// 当前歌曲里可听写的句数（菜单里显示）
    private var songPracticeCount: Int {
        guard let lyrics = state.lyrics, !lyrics.lines.isEmpty else { return 0 }
        return PracticeFilter.practiceableIndices(
            lines: lyrics.lines,
            trackDuration: state.snapshot?.track.duration ?? 0
        ).count
    }

    @objc private func toggleLock() { perform(.toggleLock) }

    @objc private func setFont(_ sender: NSMenuItem) {
        if let size = sender.representedObject as? Double { perform(.setFont(size)) }
    }

    @objc private func fontUp() { perform(.fontUp) }

    @objc private func fontDown() { perform(.fontDown) }

    @objc private func setWindowSize(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? [Double], v.count == 2 else { return }
        perform(.setWindowSize(width: v[0], height: v[1]))
    }

    @objc private func toggleFull() { perform(.toggleFull) }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { perform(.setLanguage(id)) }
    }

    @objc private func reloadLyrics() { perform(.reloadLyrics) }

    @objc private func retryTranslation() { perform(.retryTranslation) }

    @objc private func quit() { perform(.quit) }
}


/// 字号快捷键接收：⌘= / ⌘+ / ⌘-（含数字区）。
///
/// 状态栏菜单和右键菜单都不是 `NSApp.mainMenu`，菜单关闭时 AppKit 不会把
/// keyEquivalent 自动路由给我们的窗口，所以这里用一个本地 keyDown 监视器显式接住。
/// 只处理 GapSong 自己窗口上的事件，不做全局监听；Ctrl / Option 组合一律放行，
/// 普通字符和输入法候选（没有 ⌘）也不受影响。
///
/// 监视器在练习输入路径之前消费事件，`=`/`+`/`-` 不会写进答案，也不会打字机音效；
/// 改字号只写 `settings.fontSize`，不碰题目、输入、分数、播放时序和重试状态。
@MainActor
final class FontShortcutMonitor {
    enum Action {
        case bigger
        case smaller

        /// 每次 2pt；边界由 `Settings.bumpFont` 收在 14…72
        var delta: Double { self == .bigger ? 2 : -2 }
    }

    private let settings: Settings
    private let isOwnWindow: (NSWindow) -> Bool
    private var lastTimestamp: TimeInterval = -1
    private var monitor: Any?

    init(settings: Settings, isOwnWindow: @escaping (NSWindow) -> Bool) {
        self.settings = settings
        self.isOwnWindow = isOwnWindow
    }

    func install() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// 返回 true 表示已消费：调用方必须吞掉事件，不能再交给练习输入。
    func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let window = event.window,
              isOwnWindow(window),
              let action = Self.action(for: event) else { return false }
        apply(action, timestamp: event.timestamp)
        return true
    }

    /// 菜单点击与菜单 keyEquivalent 的兜底入口，和监视器共用同一个去重状态：
    /// 万一同一物理事件同时走了菜单和监视器，也只放大/缩小一次。
    func applyFromMenu(_ action: Action) {
        apply(action, timestamp: NSApp.currentEvent?.timestamp)
    }

    private func apply(_ action: Action, timestamp: TimeInterval?) {
        if let timestamp {
            guard timestamp != lastTimestamp else { return }
            lastTimestamp = timestamp
        }
        settings.bumpFont(by: action.delta)
    }

    /// 只认 ⌘ + `=` / `+` / `-`；⌃/⌥ 组合不抢，没有 ⌘ 的普通字符不抢。
    /// 按键按物理键位匹配（主键盘 = / -、数字区 + / -），再按字符兜底非 US 布局。
    static func action(for event: NSEvent) -> Action? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.control),
              !flags.contains(.option) else { return nil }

        switch event.keyCode {
        case 24, 69: return .bigger    // 主键盘 =（⌘⇧= 即 ⌘+）与数字区 +
        case 27, 78: return .smaller   // 主键盘 - 与数字区 -
        default: break
        }

        switch event.charactersIgnoringModifiers ?? "" {
        case "=", "+": return .bigger
        case "-": return .smaller
        default: return nil
        }
    }
}
