import Foundation

public enum AttentionDetector: Sendable {

    public static func needsUserInput(text: String, kind: TaskKind) -> Bool {
        if genericNeedsUserInput(text) { return true }
        if kind == .claudeCode && claudeCodeNeedsUserInput(text) { return true }
        return false
    }

    // MARK: - 通用模式

    private static func genericNeedsUserInput(_ text: String) -> Bool {
        let t = text.lowercased()
        if t.contains("[sudo] password") { return true }
        if t.contains("password:") { return true }
        if t.contains("enter passphrase") { return true }
        if t.contains("press enter") { return true }
        if t.contains("(y/n)") || t.contains("[y/n]") { return true }
        if t.contains("are you sure you want to continue") { return true }
        return false
    }

    // MARK: - Claude Code 专属

    private static let tailLineCount = 40

    private static func claudeCodeNeedsUserInput(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = lines.suffix(tailLineCount)
        let tailText = tail.joined(separator: "\n").lowercased()

        // 一层：强信号匹配
        if tailText.contains("do you want to proceed") { return true }
        if tailText.contains("proceed anyway") { return true }
        if tailText.contains("this action requires") && tailText.contains("allow") { return true }

        // 二层：TUI 按钮布局（尾部 20 行）
        let candidates = tail.suffix(20).map { String($0) }

        // 模式 1：编号选择列表（如 Claude Code 的 "❯ 1. Yes / 2. No"）
        // 要求数字后的词是按钮词，避免误匹配 Claude 对话中的普通编号输出
        let numberedPattern = try! NSRegularExpression(pattern: #"^\s*\d+[\.\)]\s+(\S+)"#)
        let buttonWords: Set<String> = [
            "allow", "deny", "approve", "reject",
            "yes", "no", "skip", "cancel", "accept",
        ]
        let numberedCount = candidates.filter { line in
            let nsLine = line as NSString
            guard let m = numberedPattern.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
                return false
            }
            let word = nsLine.substring(with: m.range(at: 1))
                .trimmingCharacters(in: .punctuationCharacters)
                .lowercased()
            return buttonWords.contains(word)
        }.count
        if numberedCount >= 2 { return true }

        // 模式 2：并排按钮（同一行出现 2+ 个按钮词，如 "Allow    Deny    Skip"）
        for line in candidates {
            let t = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard t.count < 40 else { continue }
            let tokens = t.components(separatedBy: .whitespaces)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty }
            let hitCount = tokens.filter { buttonWords.contains($0) }.count
            if hitCount >= 2 { return true }
        }
        return false
    }
}
