import Foundation

// MARK: - 菜单动作

/// 键盘菜单里的一项动作。与具体呈现方式（窗口内数字菜单）解耦，
/// 由 `AppDelegate.perform(_:)` 统一执行；原生菜单栏/右键菜单也复用同一套动作。
enum CommandAction: Equatable, Hashable {
    case toggleVisible
    case toggleTranslation
    case togglePractice
    case practiceSong
    case practiceFavorites
    case practiceMistakes
    case openLibrary
    case openMistakesLibrary
    case clearFavorites
    case clearMistakes
    case setRatio(Double)
    case setTail(Double)
    case toggleTypingSound
    case toggleLock
    case setTransparency(Double)
    case setFont(Double)
    case fontUp
    case fontDown
    case setWindowSize(width: Double, height: Double)
    case toggleFull
    case setLanguage(String)
    case reloadLyrics
    case retryTranslation
    case returnToSetup
    case quit
}

// MARK: - 菜单项

/// 一页菜单里的一项：可以是动作、开关，或带下级的子菜单。
struct CommandMenuItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    /// 行尾的当前值/数量说明
    var detail: String?
    /// 开关/单选项是否选中
    var isOn: Bool
    var isEnabled: Bool
    /// 叶子动作；有下级时为 nil
    var action: CommandAction?
    var children: [CommandMenuItem]

    init(
        id: UUID = UUID(),
        title: String,
        detail: String? = nil,
        isOn: Bool = false,
        isEnabled: Bool = true,
        action: CommandAction? = nil,
        children: [CommandMenuItem] = []
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.action = action
        self.children = children
    }

    var isSubmenu: Bool { !children.isEmpty }
}

// MARK: - 菜单内容（纯数据，自检可直接构造）

/// 生成菜单需要的全部当前状态。刻意只放值，不放 Settings/PracticeEngine，
/// 这样自检可以脱离真实偏好构造菜单并检查编号与可用性。
struct CommandMenuContext {
    var lyricsVisible = true
    var showTranslation = true
    var practiceMode = false
    var songLineCount = 0
    var bankCount = 0
    var mistakeCount = 0
    var ratio = 0.5
    var tail = 0.2
    var typingSound = false
    var locked = false
    var transparency = 0.0
    var fontSize = 24.0
    var fullMode = false
    var languageID = "zh-Hans"
    var panelWidth = 836.0
    var panelHeight = 155.0
    var lyricSource: String?
    var translationNotice: String?
}

/// 菜单结构：每个层级最多 9 项（键盘 1…9 直接索引），
/// 不依赖鼠标悬停，也不需要翻页。
@MainActor
enum CommandMenuCatalog {
    /// 与原生菜单共用同一份选项，避免两处漂移
    static let languages: [(title: String, id: String)] = [
        ("简体中文", "zh-Hans"),
        ("繁體中文", "zh-Hant"),
        ("English", "en"),
        ("日本語", "ja"),
        ("한국어", "ko")
    ]

    static let fontPresets: [(title: String, size: Double)] = [
        ("小", 18), ("标准", 24), ("大", 30), ("特大", 38)
    ]

    static let windowPresets: [(title: String, width: Double, height: Double)] = [
        ("紧凑", 836, 155), ("标准", 900, 320), ("大", 1000, 520), ("宽屏", 1200, 600)
    ]

    static func root(_ c: CommandMenuContext) -> [CommandMenuItem] {
        [
            CommandMenuItem(
                title: "练习",
                detail: c.practiceMode ? "进行中" : nil,
                children: practice(c)
            ),
            CommandMenuItem(
                title: "收藏与错题",
                detail: "收藏 \(c.bankCount) · 错题 \(c.mistakeCount)",
                children: library(c)
            ),
            CommandMenuItem(
                title: "外观",
                detail: "\(Settings.backgroundTransparencyLabel(c.transparency))"
                    + (c.locked ? " · 已锁定" : "")
                    + (c.fullMode ? " · 全文" : ""),
                children: appearance(c)
            ),
            CommandMenuItem(
                title: "字号",
                detail: "\(Int(c.fontSize.rounded()))",
                children: font(c)
            ),
            CommandMenuItem(
                title: "窗口大小",
                detail: "\(Int(c.panelWidth.rounded()))×\(Int(c.panelHeight.rounded()))",
                children: window(c)
            ),
            CommandMenuItem(
                title: "翻译",
                detail: translationDetail(c),
                children: translation(c)
            ),
            CommandMenuItem(
                title: "歌词",
                detail: c.lyricSource,
                children: lyrics(c)
            ),
            // 隐藏窗口放在靠后：避免「1 → 1」误触后键盘用户找不到窗口回来
            CommandMenuItem(
                title: c.lyricsVisible ? "隐藏歌词窗" : "显示歌词窗",
                isOn: c.lyricsVisible,
                action: .toggleVisible
            ),
            CommandMenuItem(title: "退出 GapSong", action: .quit)
        ]
    }

    // MARK: 各页

    private static func practice(_ c: CommandMenuContext) -> [CommandMenuItem] {
        [
            CommandMenuItem(
                title: c.practiceMode ? "退出练习（听写）" : "开始练习（听写）…",
                action: .togglePractice
            ),
            CommandMenuItem(
                title: "练当前歌曲",
                detail: "\(c.songLineCount) 句",
                isEnabled: c.songLineCount > 0,
                action: .practiceSong
            ),
            CommandMenuItem(
                title: "练收藏歌词",
                detail: "\(c.bankCount) 句",
                isEnabled: c.bankCount > 0,
                action: .practiceFavorites
            ),
            CommandMenuItem(
                title: "练错题本",
                detail: "\(c.mistakeCount) 条",
                isEnabled: c.mistakeCount > 0,
                action: .practiceMistakes
            ),
            CommandMenuItem(
                title: "填空强度",
                detail: Settings.ratioLabel(c.ratio),
                children: ratio(c)
            ),
            CommandMenuItem(
                title: "句末停得早/晚",
                detail: Settings.practiceTailLabel(c.tail),
                children: tail(c)
            ),
            CommandMenuItem(
                title: "打字机音效",
                isOn: c.typingSound,
                action: .toggleTypingSound
            ),
            CommandMenuItem(
                title: "返回设置页",
                isEnabled: c.practiceMode,
                action: .returnToSetup
            )
        ]
    }

    private static func ratio(_ c: CommandMenuContext) -> [CommandMenuItem] {
        Settings.practiceRatioChoices.map { value in
            CommandMenuItem(
                title: "填空 \(Settings.ratioLabel(value))",
                isOn: abs(c.ratio - value) < 0.001,
                action: .setRatio(value)
            )
        }
    }

    private static func tail(_ c: CommandMenuContext) -> [CommandMenuItem] {
        Settings.practiceTailChoices.map { value in
            CommandMenuItem(
                title: Settings.practiceTailLabel(value),
                isOn: abs(c.tail - value) < 0.001,
                action: .setTail(value)
            )
        }
    }

    private static func library(_ c: CommandMenuContext) -> [CommandMenuItem] {
        [
            CommandMenuItem(
                title: "查看收藏与错题…",
                detail: "收藏 \(c.bankCount) · 错题 \(c.mistakeCount)",
                action: .openLibrary
            ),
            CommandMenuItem(title: "查看错题本…", action: .openMistakesLibrary),
            CommandMenuItem(
                title: "清空收藏…",
                detail: "\(c.bankCount) 句",
                isEnabled: c.bankCount > 0,
                action: .clearFavorites
            ),
            CommandMenuItem(
                title: "清空错题本…",
                detail: "\(c.mistakeCount) 条",
                isEnabled: c.mistakeCount > 0,
                action: .clearMistakes
            )
        ]
    }

    private static func appearance(_ c: CommandMenuContext) -> [CommandMenuItem] {
        [
            CommandMenuItem(title: "锁定位置", isOn: c.locked, action: .toggleLock),
            CommandMenuItem(
                title: "背景透明度",
                detail: Settings.backgroundTransparencyLabel(c.transparency),
                children: transparency(c)
            ),
            CommandMenuItem(title: "全文模式", isOn: c.fullMode, action: .toggleFull)
        ]
    }

    private static func transparency(_ c: CommandMenuContext) -> [CommandMenuItem] {
        Settings.backgroundTransparencyChoices.map { value in
            CommandMenuItem(
                title: Settings.backgroundTransparencyLabel(value),
                isOn: abs(c.transparency - value) < 0.001,
                action: .setTransparency(value)
            )
        }
    }

    private static func font(_ c: CommandMenuContext) -> [CommandMenuItem] {
        var items = fontPresets.map { preset in
            CommandMenuItem(
                title: preset.title,
                detail: "\(Int(preset.size))",
                isOn: abs(c.fontSize - preset.size) < 0.5,
                action: .setFont(preset.size)
            )
        }
        items.append(CommandMenuItem(title: "放大字号", action: .fontUp))
        items.append(CommandMenuItem(title: "缩小字号", action: .fontDown))
        return items
    }

    private static func window(_ c: CommandMenuContext) -> [CommandMenuItem] {
        windowPresets.map { preset in
            CommandMenuItem(
                title: preset.title,
                detail: "\(Int(preset.width))×\(Int(preset.height))",
                isOn: abs(c.panelWidth - preset.width) < 1 && abs(c.panelHeight - preset.height) < 1,
                action: .setWindowSize(width: preset.width, height: preset.height)
            )
        }
    }

    private static func translationDetail(_ c: CommandMenuContext) -> String? {
        guard c.showTranslation else { return "已关闭" }
        return languages.first(where: { $0.id == c.languageID })?.title ?? c.languageID
    }

    private static func translation(_ c: CommandMenuContext) -> [CommandMenuItem] {
        var items = [
            CommandMenuItem(title: "显示翻译", isOn: c.showTranslation, action: .toggleTranslation)
        ]
        items.append(contentsOf: languages.map { language in
            CommandMenuItem(
                title: language.title,
                isOn: c.showTranslation && c.languageID == language.id,
                action: .setLanguage(language.id)
            )
        })
        return items
    }

    private static func lyrics(_ c: CommandMenuContext) -> [CommandMenuItem] {
        var items: [CommandMenuItem] = [
            CommandMenuItem(title: "重新匹配歌词", action: .reloadLyrics),
            CommandMenuItem(title: "重试翻译", action: .retryTranslation)
        ]
        if let source = c.lyricSource, !source.isEmpty {
            items.append(CommandMenuItem(
                title: "歌词来源：\(source)", isEnabled: false
            ))
        }
        if let notice = c.translationNotice, !notice.isEmpty {
            items.append(CommandMenuItem(
                title: TextUtil.short(notice, limit: 40), isEnabled: false
            ))
        }
        return items
    }
}

// MARK: - 状态机

/// 窗口内键盘菜单：1 打开；打开后数字 1…9 选项、0/Esc 返回/关闭。
/// 打开期间练习的数字快捷键全部暂停（由按键路由保证）。
@MainActor
final class CommandMenu: ObservableObject {
    struct Page: Equatable {
        var title: String
        var items: [CommandMenuItem]
    }

    @Published private(set) var isOpen = false
    @Published private(set) var page = Page(title: "菜单", items: [])
    @Published private(set) var breadcrumb = ""
    @Published private(set) var notice: String?

    /// 生成根菜单（由 AppDelegate 提供，读取实时偏好与数量）
    var rootProvider: (() -> [CommandMenuItem])?
    /// 选中叶子动作后执行
    var onPerform: ((CommandAction) -> Void)?
    /// 打开/关闭时通知（用于展开/还原窗口高度）
    var onOpenChange: ((Bool) -> Void)?

    private var stack: [Page] = []

    /// 当前页最多 9 项：数字 1…9 一一对应
    private static let maxItemsPerPage = 9

    var canGoBack: Bool { stack.count > 1 }

    func open() {
        guard !isOpen else { return }
        let root = rootProvider?() ?? []
        guard !root.isEmpty else { return }
        stack = [Page(title: "菜单", items: root)]
        notice = nil
        isOpen = true
        applyTop()
        onOpenChange?(true)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        stack = []
        page = Page(title: "菜单", items: [])
        breadcrumb = ""
        notice = nil
        onOpenChange?(false)
    }

    /// 数字 1…9 选择当前页对应项
    func select(_ digit: Int) {
        guard isOpen, digit >= 1, digit <= CommandMenu.maxItemsPerPage else { return }
        guard page.items.indices.contains(digit - 1) else { return }
        let item = page.items[digit - 1]
        guard item.isEnabled else {
            notice = "这一项现在不可用"
            return
        }
        notice = nil

        if item.isSubmenu {
            guard item.children.count <= CommandMenu.maxItemsPerPage else {
                notice = "这一页超出 9 项，无法用数字打开"
                return
            }
            stack.append(Page(title: item.title, items: item.children))
            applyTop()
            return
        }

        guard let action = item.action else { return }
        let perform = onPerform
        // 先关闭菜单：窗口尺寸会还原，动作再按自己的需要改变界面
        close()
        perform?(action)
    }

    /// 0 / Esc：返回上一级；根菜单直接关闭
    func back() {
        guard isOpen else { return }
        notice = nil
        if stack.count > 1 {
            stack.removeLast()
            applyTop()
        } else {
            close()
        }
    }

    private func applyTop() {
        guard let top = stack.last else { return }
        page = top
        // 根页不再重复写「菜单」；子页显示从根往下的路径
        breadcrumb = stack.dropFirst().map(\.title).joined(separator: " › ")
    }
}
