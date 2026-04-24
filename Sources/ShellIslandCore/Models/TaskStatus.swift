public enum TaskStatus: String, Codable, Sendable {
    case running
    case succeeded
    case failed
    case terminated

    public var isRunning: Bool { self == .running }

    public var isCompleted: Bool {
        switch self {
        case .succeeded, .failed, .terminated: return true
        case .running: return false
        }
    }
}
