import Foundation

/// 用户注意力需要介入的类型，按优先级从高到低排列。
public enum AttentionType: String, Sendable, CaseIterable {
    case password           // [sudo] password / enter passphrase
    case confirmation       // (y/n) / are you sure
    case pressEnter         // press enter to continue
    case claudeCodePrompt   // Claude Code TUI 权限提示
    case generic            // 兜底

    /// 是否可以直接通过发送文本响应（无需跳转到 kitty 手动操作）
    /// 密码类不可直接发送，因为 sudo 读 /dev/tty 而非 stdin
    public var isActionable: Bool {
        switch self {
        case .confirmation, .pressEnter, .claudeCodePrompt:
            return true
        case .password, .generic:
            return false
        }
    }

    /// 在弹窗中显示的标签
    public var displayLabel: String {
        switch self {
        case .password: return "Password Required"
        case .confirmation: return "Confirm (y/n)"
        case .pressEnter: return "Press Enter"
        case .claudeCodePrompt: return "Claude Code Prompt"
        case .generic: return "Input Needed"
        }
    }
}
