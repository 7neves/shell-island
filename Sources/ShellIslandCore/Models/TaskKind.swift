public enum TaskKind: String, Codable, Sendable {
    case brew
    case claudeCode
    case npmRun
    case pnpmRun
    case yarnRun

    public var displayName: String {
        switch self {
        case .brew: return "brew"
        case .claudeCode: return "Claude Code"
        case .npmRun: return "npm run"
        case .pnpmRun: return "pnpm"
        case .yarnRun: return "yarn"
        }
    }

    public var isNodePackageManager: Bool {
        switch self {
        case .npmRun, .pnpmRun, .yarnRun:
            return true
        case .brew, .claudeCode:
            return false
        }
    }

    public func matches(command: String) -> Bool {
        let executable = executableName(of: command)
        switch self {
        case .brew:
            return executable == "brew"
        case .claudeCode:
            return executable == "claude"
        case .npmRun:
            if executable == "npm" {
                return command.contains(" run ") || command.hasSuffix(" run")
                    || command.contains(" start") || command.hasSuffix(" start")
            }
            // npm 也可能以 node wrapper 形式运行：node /path/npm-cli.js run dev
            if executable == "node", let script = nodeScriptName(of: command), script.hasPrefix("npm") {
                return command.contains(" run ") || command.hasSuffix(" run")
                    || command.contains(" start") || command.hasSuffix(" start")
            }
            return false
        case .pnpmRun:
            if executable == "pnpm" { return matchesNodeScriptLike(command) }
            // pnpm 常以 node wrapper 形式运行：node /path/pnpm.cjs run dev
            if executable == "node", let script = nodeScriptName(of: command), script.hasPrefix("pnpm") {
                return matchesNodeScriptLike(command)
            }
            return false
        case .yarnRun:
            if executable == "yarn" { return matchesNodeScriptLike(command) }
            // yarn 常以 node wrapper 形式运行：node /path/yarn run dev
            if executable == "node", let script = nodeScriptName(of: command), script.hasPrefix("yarn") {
                return matchesNodeScriptLike(command)
            }
            return false
        }
    }

    /// 从完整命令行中提取可执行文件名（去掉路径和参数）
    private func executableName(of command: String) -> String {
        let firstToken = command.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? command
        return firstToken.split(separator: "/").last.map(String.init) ?? firstToken
    }

    /// 当 node 作为解释器时，提取被执行脚本的文件名
    /// 例："node /path/to/pnpm.cjs run dev" → "pnpm.cjs"
    private func nodeScriptName(of command: String) -> String? {
        let tokens = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 2 else { return nil }
        return tokens[1].split(separator: "/").last.map(String.init)
    }

    private func matchesNodeScriptLike(_ command: String) -> Bool {
        let lower = command.lowercased()
        if lower.contains(" install") || lower.contains(" add ") || lower.hasSuffix(" add") {
            return false
        }

        if lower.contains(" run ") || lower.hasSuffix(" run") { return true }

        // 在除第一个 token 以外的所有 token 中查找常见脚本别名
        // 这样既能处理 `pnpm start`，也能处理 `node pnpm.cjs start`
        let aliases = Set(["start", "dev", "build", "test"])
        let tokens = lower.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return tokens.dropFirst().contains { aliases.contains($0) }
    }
}
