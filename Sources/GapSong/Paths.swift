import Foundation

enum Paths {
    /// 自定义数据目录（测试/免沙箱运行）：优先 GAPSONG_HOME，兼容旧版的 LYRICFLOAT_HOME
    private static var overrideHome: URL? {
        let env = ProcessInfo.processInfo.environment
        let raw = env["GAPSONG_HOME"] ?? env["LYRICFLOAT_HOME"]
        guard let raw, !raw.isEmpty else { return nil }
        let url = URL(fileURLWithPath: raw)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 缓存（诊断日志、翻译缓存）
    static var base: URL {
        if let overrideHome { return overrideHome }
        if AppRuntime.isIsolated { return AppRuntime.isolatedRoot }
        let fm = FileManager.default
        let root = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = root.appendingPathComponent("GapSong", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 用户数据（收藏/错题）：放 Application Support，别被系统清理缓存时一起删掉
    static var data: URL {
        if let overrideHome { return overrideHome }
        if AppRuntime.isIsolated { return AppRuntime.isolatedRoot }
        let fm = FileManager.default
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = root.appendingPathComponent("GapSong", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 用户收藏的歌词（沿用旧文件名，保证旧数据与 ID 不变）
    static var bankURL: URL { data.appendingPathComponent("questions.json") }

    /// 错题本（与收藏分开）
    static var mistakesURL: URL { data.appendingPathComponent("mistakes.json") }

    /// 从旧版 LyricFloat 迁移数据（只在新目录缺文件时复制，不覆盖已有内容）
    static func migrateLegacyData() {
        // 测试/快照/自定义目录不做迁移
        if overrideHome != nil || AppRuntime.isIsolated { return }

        let fm = FileManager.default
        func migrate(_ searchPath: FileManager.SearchPathDirectory, fallback: URL) {
            let parent = fm.urls(for: searchPath, in: .userDomainMask).first ?? fallback
            let old = parent.appendingPathComponent("LyricFloat")
            let new = parent.appendingPathComponent("GapSong")
            guard fm.fileExists(atPath: old.path) else { return }

            if !fm.fileExists(atPath: new.path) {
                try? fm.copyItem(at: old, to: new)
                return
            }

            // 新目录已经存在（可能只是空目录或缺少某个文件）：逐个补齐
            guard let names = try? fm.contentsOfDirectory(atPath: old.path) else { return }
            for name in names {
                let src = old.appendingPathComponent(name)
                let dst = new.appendingPathComponent(name)
                if !fm.fileExists(atPath: dst.path) {
                    try? fm.copyItem(at: src, to: dst)
                }
            }
        }

        migrate(
            .applicationSupportDirectory,
            fallback: URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        )
        migrate(
            .cachesDirectory,
            fallback: URL(fileURLWithPath: NSTemporaryDirectory())
        )
    }
}
