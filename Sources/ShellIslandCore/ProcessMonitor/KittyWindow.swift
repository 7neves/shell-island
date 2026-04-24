import Foundation

/// kitty @ ls 返回的顶层窗口结构
public struct KittyWindow: Codable, Sendable, Equatable {
    public let id: UInt64
    public let tabs: [KittyTab]

    public init(id: UInt64, tabs: [KittyTab]) {
        self.id = id
        self.tabs = tabs
    }
}

/// kitty 窗口中的标签页
public struct KittyTab: Codable, Sendable, Equatable {
    public let id: UInt64
    public let title: String
    public let windows: [KittyTabWindow]

    public init(id: UInt64, title: String, windows: [KittyTabWindow]) {
        self.id = id
        self.title = title
        self.windows = windows
    }
}

/// kitty 标签页内的 shell 窗口
public struct KittyTabWindow: Codable, Sendable, Equatable {
    public let id: UInt64
    public let title: String
    public let pid: Int32
    public let cwd: String?
    public let env: [String: String]?

    public init(id: UInt64, title: String, pid: Int32, cwd: String?, env: [String: String]? = nil) {
        self.id = id
        self.title = title
        self.pid = pid
        self.cwd = cwd
        self.env = env
    }

    /// 从 kitty @ ls JSON 中查找 TTY 环境变量
    public var ttyFromEnv: String? {
        env?["KITTY_WINDOW_TTY"]
    }
}