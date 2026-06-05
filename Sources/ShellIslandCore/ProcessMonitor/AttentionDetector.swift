import Foundation

public enum AttentionDetector: Sendable {

    // MARK: - 公开 API

    /// 检测是否需要用户输入（向后兼容）。
    public static func needsUserInput(text: String, kind: TaskKind) -> Bool {
        detectType(text: text, kind: kind) != nil
    }

    /// 按优先级匹配 AttentionType，返回匹配到的最高优先级类型。
    public static func detectType(text: String, kind: TaskKind) -> AttentionType? {
        let clean = stripANSI(text)
        for type in AttentionType.allCases {
            if matches(type: type, text: clean, kind: kind) {
                return type
            }
        }
        return nil
    }

    // MARK: - ANSI 剥离

    /// 移除 ANSI 转义码（CSI 序列），避免干扰模式匹配。
    private static let ansiPattern = try! NSRegularExpression(pattern: #"\x1b\[[0-9;]*[a-zA-Z]"#)

    private static func stripANSI(_ text: String) -> String {
        ansiPattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    // MARK: - 分类匹配

    private static func matches(type: AttentionType, text: String, kind: TaskKind) -> Bool {
        switch type {
        case .password:       return matchPassword(text)
        case .pressEnter:     return matchPressEnter(text)
        case .confirmation:   return matchConfirmation(text, kind: kind)
        case .claudeCodePrompt: return kind == .claudeCode && claudeCodeNeedsUserInput(text)
        case .generic:        return genericNeedsUserInput(text, kind: kind)
        }
    }

    // MARK: - 各类型模式

    private static func matchPassword(_ text: String) -> Bool {
        let t = text.lowercased()
        // sudo 显式密码提示
        if t.contains("[sudo] password") { return true }
        if t.contains("password for") { return true }
        // passphrase / SSH key 密码
        if t.contains("enter passphrase") { return true }
        if t.contains("enter password") { return true }
        if t.contains("enter your password") { return true }
        return false
    }

    private static func matchPressEnter(_ text: String) -> Bool {
        text.lowercased().contains("press enter")
    }

    /// 对于 Claude Code 任务，仅匹配尾部行以避免对话历史中的误触发。
    private static let confirmationTailLines = 10

    private static func matchConfirmation(_ text: String, kind: TaskKind) -> Bool {
        let search: String
        if kind == .claudeCode {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            search = lines.suffix(confirmationTailLines).joined(separator: "\n").lowercased()
        } else {
            search = text.lowercased()
        }
        if search.contains("(y/n)") || search.contains("[y/n]") { return true }
        if search.contains("are you sure you want to continue") { return true }
        return false
    }

    /// 对于 Claude Code 任务，仅匹配尾部行以避免对话历史中的误触发。
    private static let genericTailLines = 5

    private static func genericNeedsUserInput(_ text: String, kind: TaskKind) -> Bool {
        let search: String
        if kind == .claudeCode {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            search = lines.suffix(genericTailLines).joined(separator: "\n").lowercased()
        } else {
            search = text.lowercased()
        }
        guard !matchPassword(text) else { return false }
        guard !matchPressEnter(text) else { return false }
        guard !matchConfirmation(text, kind: kind) else { return false }
        if search.contains("continue?") { return true }
        if search.contains("proceed?") { return true }
        return false
    }

    // MARK: - Claude Code 专属

    private static let tailLineCount = 40

    /// 匹配编号列表：先剥离 "❯"、"▸" 等光标装饰符，再匹配 "1. Yes" 格式
    private static let numberedPattern = try! NSRegularExpression(pattern: #"^\s*\d+[\.\)]\s+(\S+)"#)
    private static let cursorChars = CharacterSet(charactersIn: "❯▸▶●○»›")

    /// Claude Code TUI 中作为按钮出现的核心词
    private static let primaryButtonWords: Set<String> = [
        "allow", "deny", "approve", "reject",
        "yes", "no",
    ]

    /// 仅在并排按钮检测中使用的扩展词（单行出现 2+ 个才算）
    private static let inlineOnlyButtonWords: Set<String> = [
        "allow", "deny", "approve", "reject",
    ]

    private static func claudeCodeNeedsUserInput(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = lines.suffix(tailLineCount)
        let tailText = tail.joined(separator: "\n").lowercased()

        // 一层：强信号匹配（Claude Code 专属确认语）
        if tailText.contains("do you want to proceed") { return true }
        if tailText.contains("proceed anyway") { return true }
        if tailText.contains("this action requires") && tailText.contains("allow") { return true }

        // 二层：TUI 按钮布局（尾部 20 行）
        let candidates = tail.suffix(20).map { stripCursorPrefix(String($0)) }

        // 模式 1：编号选择列表 — 仅匹配短行（TUI 按钮通常 ≤ 60 字符），且用 primary 词
        var numberedHitCount = 0
        var numberedHitLines: [String] = []
        for line in candidates {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count <= 60 else { continue }
            let nsLine = line as NSString
            guard let m = numberedPattern.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
                continue
            }
            let word = nsLine.substring(with: m.range(at: 1))
                .trimmingCharacters(in: .punctuationCharacters)
                .lowercased()
            if primaryButtonWords.contains(word) {
                numberedHitCount += 1
                numberedHitLines.append(trimmed)
            }
        }
        // 需要至少 2 个编号行命中，且 hit 行集中在连续区域（真正的 TUI 是紧凑的）
        if numberedHitCount >= 2, numberedHitLinesAreCompact(numberedHitLines, in: candidates) {
            return true
        }

        // 模式 2：并排按钮（同一短行出现 2+ 个专用按钮词）
        for line in candidates {
            let t = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard t.count < 40 else { continue }
            let tokens = t.components(separatedBy: .whitespaces)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty }
            let hitCount = tokens.filter { inlineOnlyButtonWords.contains($0) }.count
            if hitCount >= 2 { return true }
        }
        return false
    }

    /// 检查编号命中行是否在 candidates 中紧凑出现（间距 ≤ 3 行），
    /// 防止散落在对话不同位置的口语化"Yes/No"被误判为 TUI 按钮。
    private static func numberedHitLinesAreCompact(_ hits: [String], in candidates: [String]) -> Bool {
        let trimmedCandidates = candidates.map { $0.trimmingCharacters(in: .whitespaces) }
        var hitIndices: [Int] = []
        for hit in hits {
            if let idx = trimmedCandidates.firstIndex(of: hit) {
                hitIndices.append(idx)
            }
        }
        guard hitIndices.count >= 2 else { return false }
        // 所有命中行的最大间距 ≤ 3 行
        let sorted = hitIndices.sorted()
        return (sorted.last! - sorted.first!) <= 3
    }

    /// 去掉行首的光标装饰符（如 "❯ "）
    private static func stripCursorPrefix(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.unicodeScalars.first,
              cursorChars.contains(first) else {
            return line
        }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}
