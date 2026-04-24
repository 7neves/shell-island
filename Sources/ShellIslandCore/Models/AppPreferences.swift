public struct AppPreferences: Codable, Sendable {
    public var launchAtLogin: Bool = false
    public var pollIntervalSeconds: Double = 1.0
    public var keepCompletedUntilManualClear: Bool = true

    public init() {}
}
