public struct SetupState: Codable, Sendable {
    public var accessibilityGranted: Bool = false
    public var kittyRemoteControlReady: Bool = false
    public var hookConfigured: Bool = false

    public var isReady: Bool {
        accessibilityGranted && kittyRemoteControlReady
    }

    public init() {}

    /// Hook 功能已全链路就绪：配置已安装 + kitty remote control 可用
    public var isHookReady: Bool {
        hookConfigured && kittyRemoteControlReady
    }
}
