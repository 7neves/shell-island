public struct TaskState: Equatable, Sendable {
    public private(set) var tasksByID: [String: ObservedTask]

    public init(tasks: [ObservedTask] = []) {
        self.tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    }

    public var tasks: [ObservedTask] {
        tasksByID.values.sorted { $0.startedAt > $1.startedAt }
    }

    public var runningTasks: [ObservedTask] {
        tasksByID.values.filter { $0.status == .running }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public var runningCount: Int {
        tasksByID.values.filter { $0.status == .running }.count
    }

    public mutating func apply(_ event: TaskEvent) {
        switch event {
        case let .taskDiscovered(task):
            tasksByID[task.id] = task

        case let .taskStatusChanged(id, status):
            tasksByID[id]?.status = status

        case let .taskTerminated(id, exitCode):
            tasksByID[id]?.endedAt = .now
            tasksByID[id]?.exitCode = exitCode
            tasksByID[id]?.status = .terminated

        case let .taskCompleted(id, exitCode):
            tasksByID[id]?.endedAt = .now
            tasksByID[id]?.exitCode = exitCode
            let exit = exitCode ?? 0
            tasksByID[id]?.status = exit == 0 ? .succeeded : .failed

        case let .sessionRefUpdated(id, sessionRef):
            tasksByID[id]?.sessionRef = sessionRef
        }
    }

    public mutating func removeCompletedTasks() {
        tasksByID = tasksByID.filter { !$0.value.status.isCompleted }
    }

    public func task(id: String) -> ObservedTask? {
        tasksByID[id]
    }
}
