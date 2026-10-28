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
    /// 打字机音效：每次真实输入一个英文字母时轻响一次。默认关闭，避免改变听歌体验
    @Published var typingSound: Bool { didSet { d.set(typingSound, forKey: "typingSound") } }
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
    /// 窗口背景透明度：0 = 保持原有视觉（默认），数值越大桌面透出越多。
    /// 只改窗口背景，文字/按钮仍是不透明前景；上限 45%，再高就和桌面打架。
    @Published var backgroundTransparency: Double {
        didSet {
            let clamped = min(max(backgroundTransparency, 0), WindowChrome.maxTransparency)
            let snapped = (clamped * 20).rounded() / 20
            if abs(snapped - backgroundTransparency) > 0.0001 {
                backgroundTransparency = snapped
                return
            }
            d.set(backgroundTransparency, forKey: "backgroundTransparency")
        }
    }

    /// 背景透明度的简洁百分比选项
    static let backgroundTransparencyChoices: [Double] = [0, 0.15, 0.3, 0.45]

    static func backgroundTransparencyLabel(_ value: Double) -> String {
        value < 0.005 ? "不透明" : "\(Int((value * 100).rounded()))%"
    }

    var backgroundTransparencyLabel: String {
        Self.backgroundTransparencyLabel(backgroundTransparency)
    }

    /// 可选值（秒）
    static let practiceTailChoices: [Double] = [-0.2, -0.1, 0, 0.1, 0.2, 0.35, 0.5]

    /// 练习态窗口的最小尺寸（歌词态仍是 420×110）
    static let lyricMinSize = (width: 420.0, height: 110.0)
    static let practiceMinSize = (width: 480.0, height: 380.0)
    /// 进入练习时把窗口撑到的高度
    static let practiceComfortableSize = (width: 720.0, height: 400.0)

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
            "practiceRatio": 0.5,
            "typingSound": false,
            "backgroundTransparency": 0.0
            // 注意：不要给 lyricPanelWidth/Height 注册默认值。
            // rememberedLyricSize 要靠「这两项是否真的存过」来判断用户有没有
            // 独立记录歌词态尺寸；一旦注册了默认值，判断就永远为真，
            // 老用户自定义的 panelWidth/panelHeight 会被新默认值顶掉。
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
        typingSound = d.bool(forKey: "typingSound")
        backgroundTransparency = d.double(forKey: "backgroundTransparency")
    }

    /// 旧版 LyricFloat（bundle id com.lyricfloat.app）的偏好一次性搬到 GapSong
    private static func migrateLegacyDefaults(into d: UserDefaults) {
        guard d.object(forKey: "fontSize") == nil,
              let old = UserDefaults(suiteName: "com.lyricfloat.app") else { return }
        let keys = [
            "fontSize", "showTranslation", "locked", "visible", "targetLanguageID",
            "panelWidth", "panelHeight", "forceFull", "practiceMode",
            "practiceTail", "practiceRatio", "typingSound"
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

    // MARK: 存储

    /// 窗口位置等也走同一份注入的 UserDefaults：隔离运行时绝不碰真实偏好
    var store: UserDefaults { d }

    func setSize(width: Double, height: Double) {
        panelWidth = min(max(width, 420), 4000)
        panelHeight = min(max(height, 110), 2400)
        // 歌词态尺寸单独留一份：练习态放大/缩小时不覆盖，退出练习据此恢复。
        if !practiceMode {
            d.set(panelWidth, forKey: "lyricPanelWidth")
            d.set(panelHeight, forKey: "lyricPanelHeight")
        }
    }

    /// 进入练习放大窗口之前，先把「当前歌词态尺寸」记进 lyricPanel*。
    ///
    /// 练习态会改 panelWidth/panelHeight，如果不先快照，退出练习就只能读到被练习
    /// 放大过的值。只在还没有记录时写一次，避免覆盖用户后来的歌词态尺寸。
    func captureLyricSizeIfNeeded() {
        if d.object(forKey: "lyricPanelWidth") == nil {
            d.set(panelWidth, forKey: "lyricPanelWidth")
        }
        if d.object(forKey: "lyricPanelHeight") == nil {
            d.set(panelHeight, forKey: "lyricPanelHeight")
        }
    }

    /// 上一次歌词态（非练习）的窗口尺寸；没有记录时退回默认紧凑尺寸
    var rememberedLyricSize: (width: Double, height: Double) {
        // 老版本只有 panelWidth/panelHeight：升级后第一次运行时它们才是用户真正的
        // 歌词窗尺寸。没有 lyricPanel* 记录时必须回落到它们，否则会把用户自定义的
        // 尺寸换成新默认值。一旦有 lyricPanel*（用户重新拉过窗口），以它为准。
        let w = (d.object(forKey: "lyricPanelWidth") as? Double)
            ?? (d.object(forKey: "panelWidth") as? Double)
            ?? 836.0
        let h = (d.object(forKey: "lyricPanelHeight") as? Double)
            ?? (d.object(forKey: "panelHeight") as? Double)
            ?? 155.0
        return (width: w, height: h)
    }

    func bumpFont(by delta: Double) {
        fontSize = min(max(fontSize + delta, 14), 72)
    }

    /// 练习页正文字号系数：默认字号 24 = 1，保证默认排版不变。
    ///
    /// 练习页原来只按窗口尺寸等比缩放，完全不读 `fontSize`，于是菜单「字号」
    /// 只影响歌词窗，练习设置/答题/揭示毫无反应。这里把字号换算成纯文字系数，
    /// 只乘到正文、填空和下划线与提示文案上；按钮、胶囊、间距仍跟窗口走，
    /// 避免大字号把整页按钮一起撑宽、在 480pt 窄窗里横向裁切。
    ///
    /// 14…72 全程线性单调（0.58…3.0），不做区间内 clamp，
    /// 否则大半量程看起来都没变化；纵向放不下由练习页自己的 ScrollView 兜底。
    static func practiceFontFactor(_ fontSize: Double) -> CGFloat {
        CGFloat(min(max(fontSize, 14), 72) / 24)
    }
}
