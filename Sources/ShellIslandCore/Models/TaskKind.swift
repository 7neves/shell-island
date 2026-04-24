public enum TaskKind: String, Codable, Sendable {
    case brew
    case codex
    case npmRun

    public var displayName: String {
        switch self {
        case .brew: return "brew"
        case .codex: return "codex"
        case .npmRun: return "npm run"
        }
    }

    public func matches(command: String) -> Bool {
        switch self {
        case .brew:
            return command.hasPrefix("brew") || command.contains("/brew")
        case .codex:
            return command.hasPrefix("codex") || command.contains("/codex")
        case .npmRun:
            // Accept both `npm run <script>` and `npm start` (common dev entrypoint).
            if !command.hasPrefix("npm") { return false }
            return command.contains(" run ") || command.hasSuffix(" run") || command.contains(" start") || command.hasSuffix(" start")
        }
    }
}
