import AppKit

/// 练习窗里 2…8 数字键对应的动作。数字 1 固定留给键盘菜单（见 `CommandMenu`）。
///
/// 可见按钮和键盘走同一份判定：`PracticeEngine.commandTitle(_:)` 决定是否显示，
/// `PracticeEngine.perform(_:)` 执行。不同阶段可以共享同一个数字。
enum PracticeCommand: Int, CaseIterable {
    /// 2：歌曲重听；收藏/错题朗读（朗读中再按一次停止）
    case replayOrRead = 2
    /// 3：看答案；揭示后再试一次
    case revealOrRetry = 3
    /// 4：当前阶段的主操作（设置开始 / 揭示下一句 / 结束再来一遍）。
    /// 答题阶段不设主操作：提交只走回车，避免与回车重复。
    case primary = 4
    /// 5：跳过
    case skip = 5
    /// 6：返回练习设置
    case backToSetup = 6
    /// 7：退出练习回歌词（不退出 App）
    case exitPractice = 7
    /// 8：歌曲练习里用清晰朗读替代听不清的音乐（收藏/错题由 2 朗读）
    case readAloud = 8

    /// 底部主操作区的显示顺序
    static let primaryRow: [PracticeCommand] = [
        .replayOrRead, .readAloud, .revealOrRetry, .primary, .skip
    ]
    /// 固定在右下角的导航操作
    static let secondaryRow: [PracticeCommand] = [.backToSetup, .exitPractice]
}

/// 主键盘与小键盘数字键的物理键码 → 数字。
///
/// 用 keyCode 而不是 characters：Shift/输入法组合下不会把数字认错，
/// 也不受键盘布局产生的符号影响。1 是菜单键；2…8 是练习命令；
/// 9、0 没有命令，但仍会消费。
enum PracticeNumericKeys {
    static func digit(forKeyCode keyCode: UInt16) -> Int? {
        switch keyCode {
        // 主键盘数字行
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        case 25: return 9
        case 29: return 0
        // 小键盘
        case 83: return 1
        case 84: return 2
        case 85: return 3
        case 86: return 4
        case 87: return 5
        case 88: return 6
        case 89: return 7
        case 91: return 8
        case 92: return 9
        case 82: return 0
        default: return nil
        }
    }

    static func command(forKeyCode keyCode: UInt16) -> PracticeCommand? {
        guard let digit = digit(forKeyCode: keyCode) else { return nil }
        return PracticeCommand(rawValue: digit)
    }

    /// 是否数字键（含菜单键 1 与没有命令的 9/0）：
    /// 练习窗里统一吃掉，不写进答案、不选输入法候选
    static func isDigitKey(_ keyCode: UInt16) -> Bool {
        digit(forKeyCode: keyCode) != nil
    }
}

/// 一次 keyDown 在练习窗里的归属：
/// 菜单键 / 数字命令 / 无命令数字（消费）/ 直接字母 / 交给系统。
enum PracticeKeyIntent: Equatable {
    /// 1：打开键盘菜单（歌词态和练习态都适用）
    case openMenu
    case command(PracticeCommand)
    case consumedDigit
    case letter(Character)
    case passThrough
}

/// 纯函数路由：只看物理键码、修饰键和基础字符，不看输入法是否在组字。
/// 1 是菜单键，2…8 是练习功能键，字母是直输，⌘/⌃/⌥ 组合交回系统。
enum PracticeKeyRouting {
    static func intent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String?
    ) -> PracticeKeyIntent {
        if !modifiers.intersection([.command, .control, .option]).isEmpty {
            return .passThrough
        }

        if PracticeNumericKeys.isDigitKey(keyCode) {
            // Shift+数字不触发功能，也不当作真实答案输入
            guard !modifiers.contains(.shift) else { return .passThrough }
            if PracticeNumericKeys.digit(forKeyCode: keyCode) == 1 {
                return .openMenu
            }
            guard let command = PracticeNumericKeys.command(forKeyCode: keyCode) else {
                return .consumedDigit
            }
            return .command(command)
        }

        let raw = characters ?? ""
        if raw.count == 1, let ch = raw.first, ch.isASCII, ch.isLetter {
            return .letter(ch)
        }
        return .passThrough
    }
}
