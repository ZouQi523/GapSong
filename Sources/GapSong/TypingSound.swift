import AppKit

/// 打字机音效的可注入接口。
///
/// 真实运行时用 `TypewriterSoundPlayer`：在本地合成一段 24ms 左右的短促键击声
/// （宽带噪声 + 低频“thock” + 一点高频 click），不依赖网络、系统铃声或外部素材。
/// 自检、快照和隔离运行默认注入 `SilentTypingSoundPlayer`，不会真的发声。
@MainActor
protocol TypingSoundPlaying: AnyObject {
    func playTick()
}

@MainActor
final class TypewriterSoundPlayer: TypingSoundPlaying {
    private let sounds: [NSSound]
    private var nextIndex = 0

    /// - Parameters:
    ///   - volume: 默认比系统提示音轻，避免盖住音乐
    ///   - voices: 预生成几个独立播放器，快速输入时可以重叠，不排长队
    init(volume: Float = 0.45, voices: Int = 4) {
        let data = Self.makeClickWAV()
        var pool: [NSSound] = []
        for _ in 0..<max(1, voices) {
            if let sound = NSSound(data: data) {
                sound.volume = volume
                pool.append(sound)
            }
        }
        sounds = pool
    }

    func playTick() {
        guard !sounds.isEmpty else { return }
        let count = sounds.count
        var index = nextIndex % count
        // 优先找空闲的播放器；全在响（极快输入）时复用当前这个，最多截断上一声，
        // 不会把声音排队拖慢输入。
        for offset in 0..<count {
            let candidate = (nextIndex + offset) % count
            if !sounds[candidate].isPlaying {
                index = candidate
                break
            }
        }
        let sound = sounds[index]
        if sound.isPlaying { sound.stop() }
        sound.play()
        nextIndex = (index + 1) % count
    }

    /// 本地生成 44.1kHz / 16-bit / 单声道 WAV。
    ///
    /// 形态：一个很短的冲击 + 快速衰减的宽带噪声，混一点 420Hz 的“thock”
    /// 和 1800Hz 的清脆 click。总长约 24ms，听起来是键击而不是提示铃声。
    static func makeClickWAV() -> Data {
        let sampleRate = 44_100
        let duration = 0.024
        let sampleCount = Int(Double(sampleRate) * duration)

        var pcm = Data(capacity: sampleCount * 2)
        var lcg: UInt32 = 0x9E37_79B9
        func nextNoise() -> Double {
            lcg = lcg &* 1_664_525 &+ 1_013_904_223
            return Double((lcg >> 8) & 0xFFFF) / 32_767.5 - 1.0
        }

        for index in 0..<sampleCount {
            let t = Double(index) / Double(sampleRate)
            // 2ms 起音，之后指数衰减；整体足够短，快速连打不会糊成一片
            let attack = min(1.0, t / 0.002)
            let decay = exp(-t * 190.0)
            let envelope = attack * decay

            let noise = nextNoise() * 0.62
            let thock = sin(2.0 * .pi * 420.0 * t) * 0.34
            let click = sin(2.0 * .pi * 1_800.0 * t) * 0.22
            // 最开头 0.6ms 加一个极短的冲击，让“嗒”的起音更清楚
            let transient = t < 0.0006 ? 0.9 : 0.0
            let mixed = (noise + thock + click + transient) * envelope * 0.72
            let clamped = max(-1.0, min(1.0, mixed))
            let sample = Int16(clamping: Int(clamped * 32_767.0))
            withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
        }

        var wav = Data()
        func appendASCII(_ text: String) {
            wav.append(contentsOf: text.utf8)
        }
        func appendUInt32(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) }
        }
        func appendUInt16(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + pcm.count))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)                               // PCM fmt chunk size
        appendUInt16(1)                                // PCM
        appendUInt16(1)                                // mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))           // byte rate
        appendUInt16(2)                                // block align
        appendUInt16(16)                               // bits per sample
        appendASCII("data")
        appendUInt32(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }
}

/// 静音替身：自检 / 快照 / 隔离运行默认使用
@MainActor
final class SilentTypingSoundPlayer: TypingSoundPlaying {
    func playTick() {}
}
