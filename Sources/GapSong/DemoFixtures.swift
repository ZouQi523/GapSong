import Foundation

/// 演示与文档截图使用的原创素材。
///
/// 这里的歌词、中文翻译和例句都是为 GapSong 编写的，歌曲 / 歌手 / 专辑均为虚构，
/// 不包含任何第三方歌词。真实运行时仍然使用 Music.app 的当前曲目信息并从 LRCLIB 抓取歌词；
/// 这些素材只用于 `--demo` 与离屏快照。
enum DemoFixtures {

    struct Song {
        var track: Track
        var raw: String
        var translations: [String: String]

        /// 预解析好的时间轴，演示模式无需联网。
        var lines: [LyricLine] { LRCParser.parse(raw).lines }
    }

    // MARK: 第一首（听写 / 截图主素材）

    static let paperLanterns = Song(
        track: Track(
            title: "Paper Lanterns",
            artist: "The Quiet Harbor",
            album: "Low Tide Letters",
            duration: 242
        ),
        raw: """
        [00:12.00]I kept the lanterns burning low
        [00:17.20]We folded paper lanterns by the shore
        [00:22.40]The river carried names we never said
        [00:27.60]Morning found the harbor painted gold
        [00:33.00]Every window held a brighter sky
        [00:38.90]You drew the compass points in chalk
        [00:46.10]Now every doorway hums a different tune
        [00:53.30]We trade the shadows for a steady light
        """,
        translations: [
            "I kept the lanterns burning low": "我让灯笼低低地燃着",
            "We folded paper lanterns by the shore": "我们在岸边折起纸灯笼",
            "The river carried names we never said": "河水带走了我们从未说出口的名字",
            "Morning found the harbor painted gold": "清晨发现港湾被染成了金色",
            "Every window held a brighter sky": "每一扇窗都盛着更亮的天空",
            "You drew the compass points in chalk": "你用粉笔画下罗盘的方位",
            "Now every doorway hums a different tune": "如今每道门都哼着不同的曲调",
            "We trade the shadows for a steady light": "我们用影子换一盏不灭的灯",
            "lanterns": "灯笼；提灯"
        ]
    )

    // MARK: 第二首（演示模式切歌）

    static let signalFires = Song(
        track: Track(
            title: "Signal Fires",
            artist: "The Quiet Harbor",
            album: "Low Tide Letters",
            duration: 213
        ),
        raw: """
        [00:05.00]We lit signal fires on the eastern hill
        [00:12.40]The wind rehearsed our names against the glass
        [00:19.80]Every quiet street became a river
        [00:27.20]You kept the map folded in your coat
        """,
        translations: [
            "We lit signal fires on the eastern hill": "我们在东边的山丘上点起信号火",
            "The wind rehearsed our names against the glass": "风把我们的名字贴着玻璃反复念着",
            "Every quiet street became a river": "每一条安静的街道都变成了河流",
            "You kept the map folded in your coat": "你把地图折好收进外套"
        ]
    )

    // MARK: 常用句子

    static let firstLine = "I kept the lanterns burning low"
    static let firstTranslation = "我让灯笼低低地燃着"
    static let secondLine = "We folded paper lanterns by the shore"
    static let secondTranslation = "我们在岸边折起纸灯笼"
    static let thirdLine = "The river carried names we never said"
    static let thirdTranslation = "河水带走了我们从未说出口的名字"
}
