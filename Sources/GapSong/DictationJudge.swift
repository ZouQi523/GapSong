import Foundation

/// 听写判分：正规化 → 逐词比较 → 词级对齐（用于高亮差异）
///
/// 判分刻意「宽进严出」：大小写、标点、弯引号、缩写的撇号都不计较，
/// 但词本身必须对——听成 wanna 而原文是 want to，这恰恰是要暴露的问题。
enum DictationJudge {

    /// 一个词：key 用于比较（小写、去标点、去撇号、数字转英文），text 用于展示（保留原大小写）
    struct Word {
        var key: String
        var text: String
    }

    /// 对齐后的一段：expected 是原文里的词，actual 是输入里的词
    struct Token: Identifiable {
        let id = UUID()
        var expected: String?
        var actual: String?
        var matched: Bool
    }

    struct Result {
        var isCorrect: Bool
        var tokens: [Token]
        var expectedText: String
        var actualText: String
    }

    static func judge(expected: String, actual: String) -> Result {
        let e = parse(expected)
        let a = parse(actual)
        let wordMatch = !a.isEmpty && e.map(\.key) == a.map(\.key)
        // 横线着色是按「忽略空格的字符序列」逐格比较的，判分必须用同一口径，
        // 否则会出现「满屏绿字却判错」——连写、空格位置不同都算对。
        let letterMatch = !a.isEmpty && comparisonChars(expected) == comparisonChars(actual)

        return Result(
            isCorrect: wordMatch || letterMatch,
            tokens: align(e, a),
            expectedText: expected,
            actualText: actual
        )
    }

    /// 参与比较的字符序列：ASCII 字母 / 数字 / 连字符，小写。
    ///
    /// 这是判分与横线着色的唯一口径。改这里等于同时改两边，
    /// 不要再在别处复制一套过滤规则。
    static func comparisonChars(_ raw: String) -> [Character] {
        raw.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    /// 切成词，同时保留「比较形式」和「展示形式」
    static func parse(_ raw: String) -> [Word] {
        var s = raw
        for (from, to) in [("’", "'"), ("‘", "'"), ("`", "'"), ("´", "'"),
                           ("–", "-"), ("—", "-"), ("‐", "-")] {
            s = s.replacingOccurrences(of: from, with: to)
        }

        var buffer = ""
        buffer.reserveCapacity(s.count)
        for ch in s {
            if ch.isLetter || ch.isNumber {
                buffer.append(ch)
            } else if ch == "'" || ch == "-" {
                buffer.append(ch)
            } else {
                buffer.append(" ")
            }
        }

        return buffer.split(whereSeparator: { $0 == " " }).compactMap { sub in
            let text = String(sub)
            // 缩写漏了撇号不该判错：don't / dont 视为同一个词
            let key = expandDigits(text.lowercased().replacingOccurrences(of: "'", with: ""))
            guard !key.isEmpty else { return nil }
            return Word(key: key, text: text)
        }
    }

    private static let numberWords: [String: String] = [
        "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
        "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten",
        "11": "eleven", "12": "twelve", "13": "thirteen", "14": "fourteen", "15": "fifteen",
        "16": "sixteen", "17": "seventeen", "18": "eighteen", "19": "nineteen", "20": "twenty"
    ]

    private static func expandDigits(_ word: String) -> String {
        numberWords[word] ?? word
    }

    /// 词级 LCS 对齐，生成两行对照所需的 token 序列
    static func align(_ expected: [Word], _ actual: [Word]) -> [Token] {
        let n = expected.count
        let m = actual.count
        var tokens: [Token] = []

        guard n > 0, m > 0 else {
            for word in expected { tokens.append(Token(expected: word.text, actual: nil, matched: false)) }
            for word in actual { tokens.append(Token(expected: nil, actual: word.text, matched: false)) }
            return tokens
        }

        // dp[i][j] = expected[i...] 与 actual[j...] 的 LCS 长度
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = expected[i].key == actual[j].key
                    ? dp[i + 1][j + 1] + 1
                    : max(dp[i + 1][j], dp[i][j + 1])
            }
        }

        var i = 0
        var j = 0
        while i < n && j < m {
            if expected[i].key == actual[j].key {
                tokens.append(Token(expected: expected[i].text, actual: actual[j].text, matched: true))
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                tokens.append(Token(expected: expected[i].text, actual: nil, matched: false))
                i += 1
            } else {
                tokens.append(Token(expected: nil, actual: actual[j].text, matched: false))
                j += 1
            }
        }
        while i < n {
            tokens.append(Token(expected: expected[i].text, actual: nil, matched: false))
            i += 1
        }
        while j < m {
            tokens.append(Token(expected: nil, actual: actual[j].text, matched: false))
            j += 1
        }
        return tokens
    }
}
