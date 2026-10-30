import AppKit

// 首次以 GapSong 启动：把旧版 LyricFloat 的题库/翻译缓存搬过来（不动已有数据）
Paths.migrateLegacyData()

if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated { SnapshotTool.render(to: CommandLine.arguments[i + 1]) }
}

// 键盘菜单：1 打开后的第一页，数字索引与当前值一眼可见
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-menu"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 620, height: 440, menu: true
        )
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-full"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(to: CommandLine.arguments[i + 1], width: 900, height: 470, full: true)
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 760, height: 330, practice: true
        )
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-setup"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 760, height: 390, setup: true
        )
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-retry"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 760, height: 330, practice: true, retry: true
        )
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-bank"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 760, height: 340, bankPractice: true
        )
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-favorites"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 780, height: 560, library: .favorites
        )
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-mistakes"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 780, height: 620, library: .mistakes
        )
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-mistakes"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 760, height: 360, mistakePractice: true
        )
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-answer"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 760, height: 360, practice: true, answer: true
        )
    }
}

// 最小练习窗（480×380）：验证设置/答题/揭示/结束不被裁掉
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-small"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: Settings.practiceMinSize.width,
            height: Settings.practiceMinSize.height,
            practice: true
        )
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-small-answer"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: Settings.practiceMinSize.width,
            height: Settings.practiceMinSize.height,
            practice: true, answer: true
        )
    }
}

// 最小窗设置页：固定底部「1 菜单 / 4 开始 / 7 返回」不被内容推走
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-setup-small"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: Settings.practiceMinSize.width,
            height: Settings.practiceMinSize.height,
            setup: true
        )
    }
}

// 最小窗离线练习：数字 2 朗读与底部操作在 480×380 下仍可见
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-bank-small"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: Settings.practiceMinSize.width,
            height: Settings.practiceMinSize.height,
            bankPractice: true
        )
    }
}

// 最小窗播放异常：恢复动作固定在底部，不随错误详情滚出屏幕
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-issue-small"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: Settings.practiceMinSize.width,
            height: Settings.practiceMinSize.height,
            practice: true, issue: .unauthorized
        )
    }
}

// 播放异常提示（权限/暂停/没有在播放）：只提示，不自动恢复、不判失败
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-waiting"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 760, height: 330, practice: true, waiting: true
        )
    }
}

// 最小窗下的「全部正确、等句末」：确认文案与句级进度不被裁切
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-waiting-small"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: Settings.practiceMinSize.width,
            height: Settings.practiceMinSize.height,
            practice: true, waiting: true
        )
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-issue"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 760, height: 360, practice: true, issue: .unauthorized
        )
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-practice-paused"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 760, height: 360, practice: true, issue: .paused
        )
    }
}

// 收藏写入失败：警示必须来自真实写失败，而不是写死的文案
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-storage-warning"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(to: CommandLine.arguments[i + 1], storageWarning: true)
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-storage-warning-full"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 900, height: 470, full: true, storageWarning: true
        )
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-storage-warning-practice"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 760, height: 360, practice: true, storageWarning: true
        )
    }
}

// 单条删除的二次确认（取消不写盘）
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-favorites-delete"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 780, height: 560, library: .favorites, libraryConfirmDelete: true
        )
    }
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot-mistakes-delete"),
   CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated {
        SnapshotTool.render(
            to: CommandLine.arguments[i + 1],
            width: 780, height: 620, library: .mistakes, libraryConfirmDelete: true
        )
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
