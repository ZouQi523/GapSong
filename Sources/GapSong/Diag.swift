import Foundation

/// 轻量诊断日志，便于排查“为什么没有歌词/翻译”
enum Diag {
    static let url: URL = {
        return Paths.base.appendingPathComponent("diag.log")
    }()

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        let line = "[\(fmt.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}
