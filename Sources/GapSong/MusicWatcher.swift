import Foundation
import AppKit

/// 可以下发给 Music.app 的播放控制命令
enum MusicCommand {
    case play
    case pause

    var source: String {
        switch self {
        case .play:  return "tell application \"Music\" to play"
        case .pause: return "tell application \"Music\" to pause"
        }
    }
}

/// 播放控制接口：测试/快照可以注入不会碰真实 Music 的替身。
protocol MusicControlling: AnyObject {
    func send(_ command: MusicCommand)
    func seek(to seconds: TimeInterval, play: Bool)
}

/// 通过 AppleScript 读取 Music.app 的播放状态
final class MusicWatcher {
    var onSnapshot: ((MusicSnapshot?) -> Void)?
    var onProblem: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.gapsong.music", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var script: NSAppleScript?
    private var commandScripts: [String: NSAppleScript] = [:]
    private var reportedProblem = false

    private static let source = """
    with timeout of 4 seconds
        tell application "Music"
            if it is not running then return {"", "", "", 0, 0, "notrunning"}
            set pstate to (player state as string)
            if pstate is "stopped" then return {"", "", "", 0, 0, "stopped"}
            tell current track
                set tname to name
                set tartist to artist
                set talbum to album
                set tdur to duration
            end tell
            set tpos to player position
            return {tname, tartist, talbum, tdur, tpos, pstate}
        end tell
    end timeout
    """

    init() {
        script = NSAppleScript(source: Self.source)
        script?.compileAndReturnError(nil)
        for command in [MusicCommand.play, .pause] {
            let compiled = NSAppleScript(source: command.source)
            compiled?.compileAndReturnError(nil)
            commandScripts[command.source] = compiled
        }
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(400), leeway: .milliseconds(80))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        guard Self.musicIsRunning(), let script else {
            deliver(nil)
            return
        }

        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)

        if let err {
            let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -1743 {
                reportOnce("需要授权控制「音乐」：系统设置 › 隐私与安全性 › 自动化")
            } else if code != -1712 {
                reportOnce("读取音乐播放状态失败（\(code)）")
            }
            return
        }

        deliver(Self.snapshot(from: result))
    }

    /// 解析 AppleScript 返回的 {name, artist, album, duration, position, state}
    static func snapshot(from desc: NSAppleEventDescriptor) -> MusicSnapshot? {
        guard desc.numberOfItems >= 6 else { return nil }

        func str(_ i: Int) -> String { desc.atIndex(i + 1)?.stringValue ?? "" }

        let state = str(5)
        guard state == "playing" || state == "paused", !str(0).isEmpty else { return nil }

        let track = Track(
            title: str(0),
            artist: str(1),
            album: str(2),
            duration: desc.atIndex(4)?.doubleValue ?? 0
        )
        return MusicSnapshot(
            track: track,
            position: desc.atIndex(5)?.doubleValue ?? 0,
            playing: state == "playing",
            sampledAt: Date()
        )
    }

    static func scriptCompiles() -> Bool {
        let s = NSAppleScript(source: source)
        var err: NSDictionary?
        s?.compileAndReturnError(&err)
        return err == nil
    }

    // MARK: 控制

    /// 播放 / 暂停。命令与轮询共用同一条队列，避免 NSAppleScript 并发使用。
    func send(_ command: MusicCommand) {
        queue.async { [weak self] in
            guard let self, let script = self.commandScripts[command.source] else { return }
            guard Self.musicIsRunning() else { return }

            var err: NSDictionary?
            script.executeAndReturnError(&err)
            if let err {
                self.reportControlError(err)
                return
            }
            self.poll()
            // 流媒体起播有延迟，半秒后再补一次采样
            self.queue.asyncAfter(deadline: .now() + 0.5) { self.poll() }
        }
    }

    /// 跳到指定播放位置（秒）。`play: true` 时在同一条脚本里顺带开始播放。
    func seek(to seconds: TimeInterval, play: Bool = false) {
        let target = max(0, seconds)
        queue.async { [weak self] in
            guard let self else { return }
            guard Self.musicIsRunning() else { return }

            let body = play
                ? "set player position to \(String(format: "%.2f", target))\n        play"
                : "set player position to \(String(format: "%.2f", target))"
            let source = """
            with timeout of 4 seconds
                tell application "Music"
                    \(body)
                end tell
            end timeout
            """
            guard let script = NSAppleScript(source: source) else { return }
            var err: NSDictionary?
            script.executeAndReturnError(&err)
            if let err {
                self.reportControlError(err)
                return
            }
            self.poll()
            self.queue.asyncAfter(deadline: .now() + 0.3) { self.poll() }
        }
    }

    /// 立刻重新采样一次（UI 想马上看到最新状态时用）
    func resample() {
        queue.async { [weak self] in self?.poll() }
    }

    private static func musicIsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music" && !$0.isTerminated
        }
    }

    private func reportControlError(_ err: NSDictionary) {
        let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
        if code == -1743 {
            reportOnce("需要授权控制「音乐」：系统设置 › 隐私与安全性 › 自动化")
        } else {
            reportOnce("控制音乐失败（\(code)）")
        }
    }

    private func deliver(_ snap: MusicSnapshot?) {
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot?(snap)
        }
    }

    private func reportOnce(_ msg: String) {
        guard !reportedProblem else { return }
        reportedProblem = true
        DispatchQueue.main.async { [weak self] in self?.onProblem?(msg) }
    }
}

extension MusicWatcher: MusicControlling {}

/// 预览/测试用：不下发任何真实命令
final class NoopMusicController: MusicControlling {
    func send(_ command: MusicCommand) {}
    func seek(to seconds: TimeInterval, play: Bool) {}
}
