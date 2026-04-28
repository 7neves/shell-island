import Combine
import ApplicationServices
import Foundation

@MainActor
public final class TaskMonitor: ObservableObject {
    @Published public var taskState = TaskState()
    @Published public var preferences = AppPreferences()
    @Published public var setupState = SetupState()
    @Published public var attentionTaskIDs = Set<String>()

    private static let idlePollIntervalSeconds: Double = 2.0
    private static let sigintGraceSeconds: Double = 0.8
    private var pollTimer: Timer?
    private var currentPollIntervalSeconds: Double?
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
        refreshSetupState()
        ensureTimerRunning()
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        currentPollIntervalSeconds = nil
    }

    public func applyPreferences(_ preferences: AppPreferences) {
        self.preferences = preferences

        ensureTimerRunning()
    }

    public func refreshSetupState() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            // Trigger the system prompt if needed (user can still enable manually in Settings).
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
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
        let currentActivePIDs = Set(taskState.tasks.filter { $0.status.isRunning || $0.status.isTerminating }.map { $0.pid })
        let newPIDs = Set(snapshots.map { $0.pid })

        // 发现新任务
        for snapshot in snapshots {
            if !currentActivePIDs.contains(snapshot.pid) {
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

        // 先更新 active 任务的 sessionRef，这样在“任务消失”时也能基于 kitty 输出推断失败。
        if !windows.isEmpty {
            for task in taskState.tasks where task.status.isRunning || task.status.isTerminating {
                if task.sessionRef == nil || task.sessionRef?.kittyLeafWindowId == 0 {
                    if let ref = findBestSessionRef(for: task, windowsBySocket: windows) {
                        apply(.sessionRefUpdated(task.id, ref))
                    }
                }
            }
        }

        // 已消失的 active 任务标记完成/终止
        let activeTasks = taskState.tasks.filter { $0.status.isRunning || $0.status.isTerminating }
        for task in activeTasks {
            if !newPIDs.contains(task.pid) {
                if task.status.isTerminating {
                    apply(.taskTerminated(task.id, nil))
                    logger.info("任务已终止: \(task.kind.displayName) pid=\(task.pid)")
                } else {
                    // Best-effort: detect brew install failures (we're not the parent process,
                    // so exit codes are often unavailable).
                    let inferredExit = inferExitCodeIfPossible(for: task)
                    apply(.taskCompleted(task.id, inferredExit))
                    logger.info("任务完成: \(task.kind.displayName) pid=\(task.pid)")
                }
            }
        }

        ensureTimerRunning()

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

        // Best-effort: detect "waiting for input" prompts in kitty tabs.
        attentionTaskIDs = detectAttentionTasks(windowsBySocket: windows)
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

    private func detectAttentionTasks(windowsBySocket: [(socket: String, windows: [KittyWindow])]) -> Set<String> {
        guard setupState.kittyRemoteControlReady else { return [] }

        var result = Set<String>()
        for task in taskState.runningTasks {
            guard let ref = task.sessionRef else { continue }
            guard ref.kittyLeafWindowId != 0 else { continue }

            guard let text = kittyIntegration.getText(
                leafWindowId: Int(ref.kittyLeafWindowId),
                socket: ref.kittySocketAddress
            ) else { continue }

            if textNeedsUserInput(text) {
                result.insert(task.id)
            }
        }
        return result
    }

    private func textNeedsUserInput(_ text: String) -> Bool {
        let t = text.lowercased()
        // Password / sudo
        if t.contains("[sudo] password") { return true }
        if t.contains("password:") { return true }
        if t.contains("enter passphrase") { return true }
        // Common confirmations
        if t.contains("press enter") { return true }
        if t.contains("(y/n)") || t.contains("[y/n]") { return true }
        if t.contains("are you sure you want to continue") { return true }
        return false
    }

    public func terminateTask(id: String) {
        guard let task = taskState.task(id: id), task.status.isRunning else { return }
        let pid = task.pid

        // UI 立即进入 stopping（避免“点了没反应”）
        apply(.taskStatusChanged(id, .terminating))

        // Prefer SIGINT (Ctrl-C) first for friendlier shutdown (e.g. node dev servers).
        kill(pid, SIGINT)
        logger.info("发送 SIGINT: pid=\(pid)")

        // If still around after short grace, escalate to SIGTERM.
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.sigintGraceSeconds * 1_000_000_000))
            // If user restarted / state changed, don't escalate.
            guard taskState.task(id: id)?.status.isTerminating == true else { return }

            if kill(pid, 0) == 0 {
                kill(pid, SIGTERM)
                logger.info("发送 SIGTERM: pid=\(pid)")
            }

            // 3 秒超时后 SIGKILL
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard taskState.task(id: id)?.status.isTerminating == true else { return }
            if kill(pid, 0) == 0 {
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
        guard task.kind.isNodePackageManager else { return }
        guard let commandLine = task.commandLine.nilIfEmpty else { return }
        guard let cwd = task.workingDirectory?.nilIfEmpty else { return }
        guard setupState.kittyRemoteControlReady else { return }
        guard let ref = task.sessionRef, ref.kittyLeafWindowId != 0 else { return }

        let preferredSocket = ref.kittySocketAddress
        let leafId = Int(ref.kittyLeafWindowId)

        let injected = "cd \(shellEscapeSingleQuoted(cwd)) && \(commandLine)\n"

        Task.detached {
            do {
                try self.kittyIntegration.sendText(
                    leafWindowId: leafId,
                    socket: preferredSocket,
                    text: injected
                )
            } catch {
                await MainActor.run {
                    self.logger.error("reRun 失败: \(String(describing: error))")
                }
            }
        }
    }
}

private func shellEscapeSingleQuoted(_ raw: String) -> String {
    // POSIX-ish single-quote escaping: ' -> '\'' .
    let escaped = raw.replacingOccurrences(of: "'", with: "'\\''")
    return "'\(escaped)'"
}

private extension TaskMonitor {
    func inferExitCodeIfPossible(for task: ObservedTask) -> Int32? {
        guard task.kind == .brew else { return nil }
        guard isBrewInstallCommand(task.commandLine) else { return nil }
        return inferBrewInstallExitCode(task: task)
    }

    func isBrewInstallCommand(_ cmd: String) -> Bool {
        let lower = cmd.lowercased()
        return lower.contains("brew") && lower.contains("install")
    }

    func inferBrewInstallExitCode(task: ObservedTask) -> Int32? {
        // Heuristic: Homebrew writes logs under ~/Library/Logs/Homebrew.
        // If we find a log modified after the task started that contains "Error:",
        // treat it as a failure.
        //
        // Some failures only show up in the terminal output (or the log file isn't discoverable),
        // so we also try to inspect the kitty tab text when available.
        // If we can't prove failure, return nil (keep existing behavior).
        let fm = FileManager.default
        let logsRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("Homebrew")

        let since = task.startedAt.addingTimeInterval(-2)

        guard let enumerator = fm.enumerator(
            at: logsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newestURL: URL?
        var newestDate: Date = since

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]) else { continue }
            guard values.isRegularFile == true else { continue }
            guard let m = values.contentModificationDate else { continue }
            guard m >= since else { continue }
            if m > newestDate {
                newestDate = m
                newestURL = url
            }
        }

        if let logURL = newestURL,
           let data = try? Data(contentsOf: logURL) {
            let text = String(data: data.suffix(48_000), encoding: .utf8) ?? ""
            if text.localizedCaseInsensitiveContains("Error:") || text.localizedCaseInsensitiveContains("ERROR:") {
                logger.warning("推断 brew install 失败（log: \(logURL.lastPathComponent)）")
                return 1
            }
        }

        // Fallback: inspect recent kitty tab output (best-effort).
        return inferBrewFailureFromKittyText(task: task)
    }

    func inferBrewFailureFromKittyText(task: ObservedTask) -> Int32? {
        guard setupState.kittyRemoteControlReady else { return nil }
        guard let ref = task.sessionRef else { return nil }
        guard ref.kittyLeafWindowId != 0 else { return nil }

        guard let raw = kittyIntegration.getTextAll(
            leafWindowId: Int(ref.kittyLeafWindowId),
            socket: ref.kittySocketAddress
        ) else { return nil }

        // Only inspect the tail to avoid scanning huge buffers.
        let tail = String(raw.suffix(48_000))
        let t = tail.lowercased()

        // Homebrew / curl / download failures commonly include these markers.
        let failureMarkers = [
            "error:",
            "failed to download",
            "download failed",
            "requested url returned error",
            "curl:",
            "fatal:",
        ]

        if failureMarkers.contains(where: { t.contains($0) }) {
            logger.warning("推断 brew install 失败（kitty output）")
            return 1
        }

        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension TaskMonitor {
    func desiredPollIntervalSeconds() -> Double {
        if taskState.runningCount > 0 {
            return max(0.2, preferences.pollIntervalSeconds)
        }
        return max(Self.idlePollIntervalSeconds, preferences.pollIntervalSeconds)
    }

    func ensureTimerRunning() {
        let desired = desiredPollIntervalSeconds()
        if pollTimer != nil, currentPollIntervalSeconds == desired {
            return
        }
        startOrRestartTimer(interval: desired)
    }

    func startOrRestartTimer(interval: Double) {
        pollTimer?.invalidate()

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.poll()
            }
        }
        pollTimer = timer
        currentPollIntervalSeconds = interval
        RunLoop.main.add(timer, forMode: .common)
    }
}
