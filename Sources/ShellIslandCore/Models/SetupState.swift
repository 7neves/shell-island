public struct SetupState: Codable, Sendable {
    public var accessibilityGranted: Bool = false
    public var kittyRemoteControlReady: Bool = false

    public var isReady: Bool {
        accessibilityGranted && kittyRemoteControlReady
    }

    public init() {}
}
