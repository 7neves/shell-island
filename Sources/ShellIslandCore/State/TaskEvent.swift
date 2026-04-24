public enum TaskEvent: Sendable, Equatable {
    case taskDiscovered(ObservedTask)
    case taskStatusChanged(String, TaskStatus)
    case taskTerminated(String, Int32?)
    case taskCompleted(String, Int32?)
    case sessionRefUpdated(String, TerminalSessionRef?)
}
