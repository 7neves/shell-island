public struct TerminalSessionRef: Codable, Sendable, Equatable {
    public let terminalApp: String
    /// 用于 kitty remote control 的 socket（例如 unix:/tmp/kitty-quick-access-9343）
    public let kittySocketAddress: String?
    /// kitty 顶层 OS 窗口 id（来自 kitty @ ls 的 Window.id）
    public let kittyWindowId: UInt64
    public let kittyTabId: UInt64
    /// kitty leaf window id（来自 kitty @ ls 的 TabWindow.id，用于 focus-window）
    public let kittyLeafWindowId: UInt64
    public let tty: String

    public init(
        terminalApp: String,
        kittySocketAddress: String?,
        kittyWindowId: UInt64,
        kittyTabId: UInt64,
        kittyLeafWindowId: UInt64,
        tty: String
    ) {
        self.terminalApp = terminalApp
        self.kittySocketAddress = kittySocketAddress
        self.kittyWindowId = kittyWindowId
        self.kittyTabId = kittyTabId
        self.kittyLeafWindowId = kittyLeafWindowId
        self.tty = tty
    }

    public init(terminalApp: String, kittyWindowId: UInt64, kittyTabId: UInt64, tty: String) {
        self.init(
            terminalApp: terminalApp,
            kittySocketAddress: nil,
            kittyWindowId: kittyWindowId,
            kittyTabId: kittyTabId,
            kittyLeafWindowId: 0,
            tty: tty
        )
    }

    public static func unknown(forTTY tty: String?) -> TerminalSessionRef {
        TerminalSessionRef(
            terminalApp: "kitty",
            kittySocketAddress: nil,
            kittyWindowId: 0,
            kittyTabId: 0,
            kittyLeafWindowId: 0,
            tty: tty ?? ""
        )
    }
}
