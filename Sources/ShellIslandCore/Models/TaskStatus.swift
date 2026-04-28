public enum TaskStatus: String, Codable, Sendable {
    case running
    case terminating
    case succeeded
    case failed
    case terminated

    public var isRunning: Bool { self == .running }

    public var isTerminating: Bool { self == .terminating }

    public var isCompleted: Bool {
        switch self {
        case .succeeded, .failed, .terminated: return true
        case .running, .terminating: return false
        }
    }
}
