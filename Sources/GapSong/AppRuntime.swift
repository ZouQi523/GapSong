import Foundation

/// 运行模式：正常 App 用真实偏好/缓存；自检与离屏快照统一走隔离目录与独立 UserDefaults。
enum AppRuntime {
    static var isIsolated: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["GAPSONG_ISOLATED"] == "1" { return true }
        let args = CommandLine.arguments
        return args.contains("--selftest")
            || args.contains(where: { $0.hasPrefix("--snapshot") })
    }

    /// 自检/快照的临时数据根目录（含翻译缓存、诊断日志）
    static var isolatedRoot: URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("gapsong-isolated-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 自检/快照使用的独立偏好 suite；正常启动仍然使用标准偏好。
    ///
    /// 同一个进程里只创建并清空一次：歌词窗位置等模块会反复取这份 defaults，
    /// 每次都 `removePersistentDomain` 会把当前会话刚写下的设置抹掉。
    static func settingsDefaults() -> UserDefaults {
        guard isIsolated else { return .standard }
        if let cached = cachedIsolatedDefaults { return cached }
        let name = "gapsong.isolated.\(ProcessInfo.processInfo.processIdentifier)"
        // 极端情况下 suite 创建失败也绝不回落到真实偏好
        let defaults = UserDefaults(suiteName: name) ?? UserDefaults(suiteName: "gapsong.isolated.fallback")!
        defaults.removePersistentDomain(forName: name)
        cachedIsolatedDefaults = defaults
        return defaults
    }

    private static var cachedIsolatedDefaults: UserDefaults?
}
