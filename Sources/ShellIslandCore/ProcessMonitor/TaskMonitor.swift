import Combine
import ApplicationServices
import Foundation

@MainActor
public final class TaskMonitor: ObservableObject {
    @Published public var taskState = TaskState()
    @Published public var preferences = AppPreferences()
    @Published public var setupState = SetupState()

    private var pollTimer: Timer?
    private let processDiscovery: ProcessDiscovery
    private let kittyIntegration: KittyIntegration
    private let logger = ShellLogger(category: "TaskMonitor")

    public init(
        processDiscovery: ProcessDiscovery = ProcessDiscovery(),
        kittyIntegration: KittyIntegration = KittyIntegration()
    ) {
        self.processDiscovery = processDiscovery
        self.kittyIntegration = kittyIntegration
    }

    public func startMonitoring() {
        guard pollTimer == nil else { return }

        refreshSetupState()

        let interval = preferences.pollIntervalSeconds
        let timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.poll()
            }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    public func applyPreferences(_ preferences: AppPreferences) {
        let shouldRestartTimer = self.preferences.pollIntervalSeconds != preferences.pollIntervalSeconds
        self.preferences = preferences

        if shouldRestartTimer, pollTimer != nil {
            stopMonitoring()
            startMonitoring()
        }
    }

    public func refreshSetupState() {
        setupState.accessibilityGranted = AXIsProcessTrusted()
        setupState.kittyRemoteControlReady = kittyIntegration.checkRemoteControlReady()
    }

    private func apply(_ event: TaskEvent) {
        var next = taskState
        next.apply(event)
        taskState = next
    }

    private func removeCompletedTasks() {
        var next = taskState
        next.removeCompletedTasks()
        taskState = next
    }

    func poll() {
        // 在后台线程执行进程扫描
        Task {
            let snapshots = await Task.detached {
                self.processDiscovery.discoverTaskProcesses()
            }.value

            let windows = await Task.detached {
                self.kittyIntegration.listWindowsBySocket()
            }.value

            // 回到 MainActor 更新状态
            applySnapshot(snapshots, windows: windows)
        }
    }

    func applySnapshot(_ snapshots: [ProcessSnapshot], windows: [(socket: String, windows: [KittyWindow])]) {
        let currentRunningPIDs = Set(taskState.runningTasks.map { $0.pid })
        let newPIDs = Set(snapshots.map { $0.pid })

        // 发现新任务
        for snapshot in snapshots {
            if !currentRunningPIDs.contains(snapshot.pid) {
                let now = Date()
                let signature = ObservedTask.signature(
                    kind: snapshot.kind,
                    commandLine: snapshot.command,
                    workingDirectory: snapshot.workingDirectory
                )
                let task = ObservedTask(
                    id: signature,
                    kind: snapshot.kind,
                    pid: snapshot.pid,
                    startTime: now,
                    status: .running,
                    commandLine: snapshot.command,
                    workingDirectory: snapshot.workingDirectory,
                    tty: snapshot.tty,
                    sessionRef: nil,
                    startedAt: now,
                    endedAt: nil,
                    exitCode: nil
                )
                apply(.taskDiscovered(task))
                logger.info("发现任务: \(snapshot.kind.displayName) pid=\(snapshot.pid)")
            }
        }

        // 已消失的 running 任务标记完成
        for task in taskState.runningTasks {
            if !newPIDs.contains(task.pid) {
                apply(.taskCompleted(task.id, nil))
                logger.info("任务完成: \(task.kind.displayName) pid=\(task.pid)")
            }
        }

        // 更新 sessionRef
        if !windows.isEmpty {
            for task in taskState.runningTasks {
                if task.sessionRef == nil || task.sessionRef?.kittyLeafWindowId == 0 {
                    if let ref = findBestSessionRef(for: task, windowsBySocket: windows) {
                        apply(.sessionRefUpdated(task.id, ref))
                    }
                }
            }
            // 也为已发现但无 sessionRef 的非 running 任务更新
            for task in taskState.tasks where task.sessionRef == nil || task.sessionRef?.kittyLeafWindowId == 0 {
                if let ref = findBestSessionRef(for: task, windowsBySocket: windows) {
                    apply(.sessionRefUpdated(task.id, ref))
                }
            }
        }
    }

    private func findBestSessionRef(
        for task: ObservedTask,
        windowsBySocket: [(socket: String, windows: [KittyWindow])]
    ) -> TerminalSessionRef? {
        for (socket, windows) in windowsBySocket {
            if let tty = task.tty, !tty.isEmpty,
               let ref = kittyIntegration.findSessionRef(forTTY: tty, windows: windows, socket: socket) {
                return ref
            }
            if let ref = kittyIntegration.findSessionRef(forPID: task.pid, windows: windows, socket: socket) {
                return ref
            }
        }
        return nil
    }

    public func terminateTask(id: String) {
        guard let task = taskState.task(id: id), task.status.isRunning else { return }
        let pid = task.pid

        // SIGTERM
        kill(pid, SIGTERM)
        logger.info("发送 SIGTERM: pid=\(pid)")

        // 3 秒超时后 SIGKILL
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            // 检查进程是否仍在运行
            if taskState.task(id: id)?.status.isRunning == true {
                kill(pid, SIGKILL)
                logger.warning("SIGTERM 超时，发送 SIGKILL: pid=\(pid)")
                apply(.taskTerminated(id, nil))
            }
        }
    }

    public func jumpTo(sessionRef: TerminalSessionRef) throws {
        try kittyIntegration.jumpTo(sessionRef: sessionRef)
    }

    public func clearCompletedTasks() {
        removeCompletedTasks()
    }

    public func rerun(task: ObservedTask) {
        guard let commandLine = task.commandLine.nilIfEmpty else { return }
        guard let cwd = task.workingDirectory?.nilIfEmpty else { return }

        let preferredSocket = task.sessionRef?.kittySocketAddress

        Task.detached {
            do {
                try self.kittyIntegration.launchCommandInNewTab(
                    commandLine: commandLine,
                    cwd: cwd,
                    preferredSocket: preferredSocket
                )
            } catch {
                await MainActor.run {
                    self.logger.error("reRun 失败: \(String(describing: error))")
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
