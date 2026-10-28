import Foundation
import AVFoundation

/// 朗读器的可注入接口。
///
/// 真实运行注入 `AppleSpeechSpeaker`（系统 AVSpeechSynthesizer，公开 API，无网络）；
/// 自检、快照和隔离运行默认注入 `SilentSpeechSpeaker`，绝不发真实语音。
///
/// `token` 是每次朗读请求的身份：实现只对「当前这次请求」回调 onFinish，
/// 迟到的旧句取消回调必须被丢弃，不能清掉新句的状态。
@MainActor
protocol SpeechSpeaking: AnyObject {
    /// 当前是否还在出声（排队未启动时可能暂时为 false）
    var isSpeaking: Bool { get }
    /// 当前请求自然读完（或被系统取消）时回调，带回请求 token
    var onFinish: ((UInt64) -> Void)? { get set }

    /// 开始朗读一句英文。返回 false 表示系统里没有可用的英语音色。
    /// 不会静默改用中文音色，也不排队：调用前上一次朗读必须已经停止。
    func speak(_ text: String, token: UInt64) -> Bool
    func stop()
}

/// Apple 原生 TTS：只用实际安装的英语音色，语速按听写放慢。
@MainActor
final class AppleSpeechSpeaker: NSObject, SpeechSpeaking, AVSpeechSynthesizerDelegate {
    var onFinish: ((UInt64) -> Void)?

    /// 默认语速 0.5 对听写偏快；0.45 稍慢，仍是一句自然的话
    static let dictationRate: Float = 0.45

    private let synthesizer = AVSpeechSynthesizer()
    /// 当前这一次请求：utterance 身份 + token。stop 时先失效，再发取消。
    private var activeUtteranceID: ObjectIdentifier?
    private var activeToken: UInt64?
    private(set) var lastVoiceLanguage: String?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, token: UInt64) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let voice = Self.englishVoice() else { return false }

        // 新请求先失效旧身份，再取消旧句（包括已排队但还没出声的）
        activeUtteranceID = nil
        activeToken = nil
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = Self.dictationRate
        utterance.volume = 1
        utterance.pitchMultiplier = 1
        lastVoiceLanguage = voice.language

        activeUtteranceID = ObjectIdentifier(utterance)
        activeToken = token
        synthesizer.speak(utterance)
        return true
    }

    func stop() {
        // 关键：不能只判断 isSpeaking。排队但尚未出声的句子 isSpeaking 为 false，
        // 必须显式取消，否则换题后旧句才开口。先失效身份，再发取消。
        activeUtteranceID = nil
        activeToken = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    /// 只从实际安装的英语音色里挑。优先 en-US / en-GB，其次其它英语地区；
    /// 没有英语候选就返回 nil（由界面提示），绝不构造可能不可用的默认对象。
    static func englishVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en")
        }
        guard !voices.isEmpty else { return nil }

        let order = ["en-US", "en-GB"]
        return voices.sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.language) ?? order.count
            let right = order.firstIndex(of: rhs.language) ?? order.count
            if left != right { return left < right }
            return lhs.quality.rawValue > rhs.quality.rawValue
        }.first
    }

    // AVSpeechSynthesizerDelegate 的回调不保证在主线程；跳回主 actor 后
    // 再核对 utterance 身份，旧句的 didCancel 不会清掉新句。
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finishIfCurrent(id) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finishIfCurrent(id) }
    }

    private func finishIfCurrent(_ id: ObjectIdentifier) {
        guard activeUtteranceID == id, let token = activeToken else { return }
        activeUtteranceID = nil
        activeToken = nil
        onFinish?(token)
    }
}

/// 隔离运行/快照用：接受调用但不出声。
@MainActor
final class SilentSpeechSpeaker: SpeechSpeaking {
    var onFinish: ((UInt64) -> Void)?
    private(set) var isSpeaking: Bool = false
    private(set) var lastToken: UInt64?

    func speak(_ text: String, token: UInt64) -> Bool {
        // 假装成功，避免隔离运行弹出「没有英语音色」；实际不创建任何音频。
        lastToken = token
        return true
    }

    func stop() {
        lastToken = nil
    }
}

/// 极薄的朗读状态机：负责句子归属、重复点击不叠音、无音色提示。
///
/// 不判断“该不该朗读”（那是练习页的规则），只保证：
/// 同一时刻最多一句；换句前一定 stop；旧 token 的迟到回调不会清掉新句。
@MainActor
final class SpeechReader {
    /// 状态变化（开始/停止/提示）时通知界面刷新
    var onChange: (() -> Void)?

    private var speaker: SpeechSpeaking
    /// 当前正在读（或已请求、等待开口）的句子
    private(set) var lineID: UUID?
    private(set) var isSpeaking = false
    private(set) var notice: String?

    /// 请求代次：每次开/停都 +1，在途旧回调凭 token 直接丢弃
    private var serial: UInt64 = 0
    private var activeToken: UInt64?

    /// 默认参数不能在这里构造主 actor 隔离对象；由 init 内部兜底选静默实现。
    init(speaker: SpeechSpeaking? = nil) {
        self.speaker = speaker ?? SilentSpeechSpeaker()
        wireSpeaker()
    }

    /// 替换实现（正常 App 注入 Apple 原生朗读；自检注入 spy）
    func install(_ newSpeaker: SpeechSpeaking) {
        invalidateCurrent()
        speaker.onFinish = nil
        speaker.stop()
        speaker = newSpeaker
        wireSpeaker()
        onChange?()
    }

    /// 朗读/停止同一句：再点一次就是停，不会叠音。
    func toggle(text: String, lineID: UUID) {
        if isSpeaking, self.lineID == lineID {
            cancel()
            return
        }

        invalidateCurrent()
        speaker.stop()
        notice = nil

        serial &+= 1
        let token = serial
        if speaker.speak(text, token: token) {
            activeToken = token
            isSpeaking = true
            self.lineID = lineID
        } else {
            activeToken = nil
            isSpeaking = false
            self.lineID = nil
            notice = "没有可用的英语语音"
        }
        onChange?()
    }

    /// 换题/重试/切来源/结束练习/退出练习都要走这里：停声、清掉旧句归属与提示
    func cancel() {
        invalidateCurrent()
        speaker.stop()
        let changed = isSpeaking || lineID != nil || notice != nil
        isSpeaking = false
        lineID = nil
        notice = nil
        if changed { onChange?() }
    }

    /// 只停声，不清「没有英语音色」提示
    func stop() {
        invalidateCurrent()
        speaker.stop()
        let changed = isSpeaking || lineID != nil
        isSpeaking = false
        lineID = nil
        if changed { onChange?() }
    }

    private func invalidateCurrent() {
        serial &+= 1
        activeToken = nil
    }

    private func wireSpeaker() {
        speaker.onFinish = { [weak self] token in
            guard let self, let active = self.activeToken, token == active else { return }
            self.activeToken = nil
            let changed = self.isSpeaking || self.lineID != nil
            self.isSpeaking = false
            self.lineID = nil
            if changed { self.onChange?() }
        }
    }
}
