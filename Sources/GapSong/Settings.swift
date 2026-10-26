import Foundation
import SwiftUI
import Translation

@MainActor
final class Settings: ObservableObject {
    private let d: UserDefaults

    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize") } }
    @Published var showTranslation: Bool { didSet { d.set(showTranslation, forKey: "showTranslation") } }
    @Published var locked: Bool { didSet { d.set(locked, forKey: "locked") } }
    @Published var visible: Bool { didSet { d.set(visible, forKey: "visible") } }
    @Published var targetLanguageID: String { didSet { d.set(targetLanguageID, forKey: "targetLanguageID") } }
    @Published var panelWidth: Double { didSet { d.set(panelWidth, forKey: "panelWidth") } }
    @Published var panelHeight: Double { didSet { d.set(panelHeight, forKey: "panelHeight") } }
    @Published var forceFull: Bool { didSet { d.set(forceFull, forKey: "forceFull") } }
    @Published var practiceMode: Bool { didSet { d.set(practiceMode, forKey: "practiceMode") } }
    /// 填空比例：30% = 只挖三成词，100% = 整句听写。按 5% 步进吸附
    @Published var practiceRatio: Double {
        didSet {
            let clamped = min(max(practiceRatio, 0.3), 1.0)
            let snapped = (clamped * 20).rounded() / 20
            if abs(snapped - practiceRatio) > 0.0001 {
                practiceRatio = snapped
                return
            }
            d.set(practiceRatio, forKey: "practiceRatio")
        }
    }
    /// 听写句末延迟：正数 = 多放一点再停，负数 = 提前停。默认延后，避免切掉最后一个音
    @Published var practiceTail: Double {
        didSet {
            let clamped = min(max(practiceTail, -0.5), 1.5)
            if clamped != practiceTail {
                practiceTail = clamped
                return
            }
            d.set(practiceTail, forKey: "practiceTail")
        }
    }

    /// 可选值（秒）
    static let practiceTailChoices: [Double] = [-0.2, -0.1, 0, 0.1, 0.2, 0.35, 0.5]

    static func practiceTailLabel(_ value: Double) -> String {
        if abs(value) < 0.01 { return "准时停" }
        let amount = String(format: "%.2g", abs(value))
        return value > 0 ? "延后 \(amount)s" : "提前 \(amount)s"
    }

    var practiceTailLabel: String { Self.practiceTailLabel(practiceTail) }

    /// 强度预设
    static let practiceRatioChoices: [Double] = [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]

    static func ratioLabel(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    var practiceRatioLabel: String { Self.ratioLabel(practiceRatio) }

    init(defaults: UserDefaults = AppRuntime.settingsDefaults()) {
        self.d = defaults
        if defaults === UserDefaults.standard {
            Self.migrateLegacyDefaults(into: defaults)
        }
        defaults.register(defaults: [
            "fontSize": 24.0,
            "showTranslation": true,
            "locked": false,
            "visible": true,
            "targetLanguageID": "zh-Hans",
            "panelWidth": 836.0,
            "panelHeight": 155.0,
            "forceFull": false,
            "practiceMode": false,
            "practiceTail": 0.2,
            "practiceRatio": 0.5
        ])
        fontSize = d.double(forKey: "fontSize")
        showTranslation = d.bool(forKey: "showTranslation")
        locked = d.bool(forKey: "locked")
        visible = d.bool(forKey: "visible")
        targetLanguageID = d.string(forKey: "targetLanguageID") ?? "zh-Hans"
        panelWidth = d.double(forKey: "panelWidth")
        panelHeight = d.double(forKey: "panelHeight")
        forceFull = d.bool(forKey: "forceFull")
        practiceMode = d.bool(forKey: "practiceMode")
        practiceTail = d.double(forKey: "practiceTail")
        practiceRatio = d.double(forKey: "practiceRatio")
    }

    /// 旧版 LyricFloat（bundle id com.lyricfloat.app）的偏好一次性搬到 GapSong
    private static func migrateLegacyDefaults(into d: UserDefaults) {
        guard d.object(forKey: "fontSize") == nil,
              let old = UserDefaults(suiteName: "com.lyricfloat.app") else { return }
        let keys = [
            "fontSize", "showTranslation", "locked", "visible", "targetLanguageID",
            "panelWidth", "panelHeight", "forceFull", "practiceMode",
            "practiceTail", "practiceRatio"
        ]
        for key in keys {
            if let value = old.object(forKey: key) {
                d.set(value, forKey: key)
            }
        }
    }

    var targetLanguage: Locale.Language {
        Locale.Language(identifier: targetLanguageID)
    }

    func targetLabel() -> String {
        Locale.current.localizedString(forIdentifier: targetLanguageID) ?? targetLanguageID
    }

    func setSize(width: Double, height: Double) {
        panelWidth = min(max(width, 420), 4000)
        panelHeight = min(max(height, 110), 2400)
    }

    func bumpFont(by delta: Double) {
        fontSize = min(max(fontSize + delta, 14), 72)
    }
}
