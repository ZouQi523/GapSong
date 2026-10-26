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

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
