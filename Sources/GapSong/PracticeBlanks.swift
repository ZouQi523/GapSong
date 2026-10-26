import Foundation

/// 填空强度：决定一句话里有多少词要被挖空。
///
/// 用户选的是「填写比例」——30% 只挖三成词（其余当提示露出来），100% 就是整句听写。
/// 同一句 + 同一比例永远挖同样的位置：算法只依赖文本本身，不依赖随机数，
/// 否则界面每刷新一次横线就换地方，根本没法打字。
enum PracticeBlanks {

    /// 一个词：raw 用于展示（保留大小写与标点），chars 用于输入/判分
    struct Word: Equatable {
        var raw: String
        var chars: [Character]

        var isEligible: Bool { !chars.isEmpty }
    }

    /// 按空格切词。标点留在 raw 里，但 chars 只保留能打出来的字符
    static func words(in text: String) -> [Word] {
        text.split(whereSeparator: { $0.isWhitespace }).map { slice in
            let raw = String(slice)
            return Word(raw: raw, chars: DictationJudge.comparisonChars(raw))
        }
    }

    /// 需要用户填写的词下标（升序）。没有可输入字符的词（纯标点/非拉丁）永远不挖。
    static func blankIndices(in text: String, ratio: Double) -> [Int] {
        let all = words(in: text)
        let eligible = all.indices.filter { all[$0].isEligible }
        guard !eligible.isEmpty else { return [] }

        let clamped = min(max(ratio, 0.3), 1.0)
        let want = min(eligible.count, max(1, Int((clamped * Double(eligible.count)).rounded())))
        guard want < eligible.count else { return eligible }

        // 用文本做种子旋转起点：不同句子挖的位置不一样，但每句自己是稳定的
        let rotation = Int(stableSeed(text) % UInt64(eligible.count))
        var picked = Set<Int>()
        var slots: [Int] = []
        for i in 0..<want {
            var pos = (rotation + i * eligible.count / want) % eligible.count
            var guardCount = 0
            while picked.contains(pos), guardCount < eligible.count {
                pos = (pos + 1) % eligible.count
                guardCount += 1
            }
            picked.insert(pos)
            slots.append(pos)
        }
        return slots.sorted().map { eligible[$0] }
    }

    /// 判分期望：把所有被挖的词按顺序拼回去
    static func expectedAnswer(in text: String, blankIndices: [Int]) -> String {
        let all = words(in: text)
        return blankIndices
            .filter { all.indices.contains($0) }
            .map { all[$0].raw }
            .joined(separator: " ")
    }

    /// 设置页预览用：把挖空的词换成下划线
    static func maskedText(in text: String, ratio: Double) -> String {
        let all = words(in: text)
        let blanks = Set(blankIndices(in: text, ratio: ratio))
        return all.enumerated().map { index, word in
            guard blanks.contains(index) else { return word.raw }
            return String(repeating: "_", count: max(2, word.chars.count))
        }
        .joined(separator: " ")
    }

    /// 这句有没有可听写的内容（纯中文/日文行返回 false）
    static func isPracticeable(_ text: String) -> Bool {
        words(in: text).contains { $0.isEligible }
    }

    /// FNV-1a：稳定、跨进程一致（Swift 的 hashValue 每次启动都变，不能用）
    static func stableSeed(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}
