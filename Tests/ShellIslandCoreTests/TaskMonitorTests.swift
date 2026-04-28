import XCTest
@testable import ShellIslandCore

@MainActor
final class TaskMonitorTests: XCTestCase {

    // MARK: - 新任务发现

    func testApplySnapshotDiscoverNewTasks() {
        let discovery = ProcessDiscovery(procInfo: ProcInfo())
        let kitty = KittyIntegration(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
        let monitor = TaskMonitor(processDiscovery: discovery, kittyIntegration: kitty)

        let snapshots = [
            ProcessSnapshot(pid: 300, ppid: 200, tty: "/dev/ttys000",
                            command: "brew install ffmpeg", workingDirectory: nil, kind: .brew),
        ]

        monitor.applySnapshot(snapshots, windows: [])

        XCTAssertEqual(monitor.taskState.runningCount, 1)
        XCTAssertEqual(monitor.taskState.runningTasks.first?.kind, .brew)
        XCTAssertEqual(monitor.taskState.runningTasks.first?.pid, 300)
    }

    // MARK: - 已消失任务标记完成

    func testApplySnapshotMarkDisappearedTaskCompleted() {
        let discovery = ProcessDiscovery(procInfo: ProcInfo())
        let kitty = KittyIntegration(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
        let monitor = TaskMonitor(processDiscovery: discovery, kittyIntegration: kitty)

        // 第一次：发现 brew 任务
        let snapshots1 = [
            ProcessSnapshot(pid: 300, ppid: 200, tty: "/dev/ttys000",
                            command: "brew install ffmpeg", workingDirectory: nil, kind: .brew),
        ]
        monitor.applySnapshot(snapshots1, windows: [])
        XCTAssertEqual(monitor.taskState.runningCount, 1)

        // 第二次：brew 进程消失
        monitor.applySnapshot([], windows: [])

        let completed = monitor.taskState.tasks.filter { $0.status.isCompleted }
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.kind, .brew)
    }

    func testBrewInstallFailureInKittyOutputMarksTaskFailed() {
        let discovery = ProcessDiscovery(procInfo: ProcInfo())

        let failingText = """
        ==> Fetching downloads for: mole
        Error: Failed to download resource "mole (1.36.1)"
        Download failed: https://github.com/tw93/Mole/archive/refs/tags/V1.36.1.tar.gz
        curl: (56) The requested URL returned error: 404
        """

        let detailedRunner: DetailedCommandRunner = { _, args, _ in
            if args.contains("get-text") {
                return CommandOutput(stdout: failingText, stderr: "", exitCode: 0, timedOut: false)
            }
            return CommandOutput(stdout: "", stderr: "", exitCode: 0, timedOut: false)
        }

        let kitty = KittyIntegration(commandRunner: ShellCommandRunner(detailedRunner: detailedRunner, timeout: 0.2))
        let monitor = TaskMonitor(processDiscovery: discovery, kittyIntegration: kitty)
        monitor.setupState.kittyRemoteControlReady = true

        let snapshots = [
            ProcessSnapshot(pid: 300, ppid: 200, tty: "/dev/ttys000",
                            command: "brew install mole", workingDirectory: nil, kind: .brew),
        ]

        let windows = [
            KittyWindow(id: 1, tabs: [
                KittyTab(id: 10, title: "Work", windows: [
                    KittyTabWindow(id: 100, title: "zsh", pid: 200, cwd: nil,
                                   env: ["KITTY_WINDOW_TTY": "/dev/ttys000"]),
                ]),
            ]),
        ]

        // Discover task + attach sessionRef
        monitor.applySnapshot(snapshots, windows: [("unix:/tmp/test-kitty", windows)])
        XCTAssertEqual(monitor.taskState.runningCount, 1)

        // Process disappears -> infer failure from kitty output
        monitor.applySnapshot([], windows: [("unix:/tmp/test-kitty", windows)])

        let task = monitor.taskState.tasks.first(where: { $0.kind == .brew })
        XCTAssertEqual(task?.status, .failed)
        XCTAssertEqual(task?.exitCode, 1)
    }

    // MARK: - sessionRef 关联

    func testApplySnapshotUpdatesSessionRef() {
        let discovery = ProcessDiscovery(procInfo: ProcInfo())
        let kitty = KittyIntegration(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
        let monitor = TaskMonitor(processDiscovery: discovery, kittyIntegration: kitty)

        let snapshots = [
            ProcessSnapshot(pid: 300, ppid: 200, tty: "/dev/ttys000",
                            command: "brew install ffmpeg", workingDirectory: nil, kind: .brew),
        ]

        let windows = [
            KittyWindow(id: 1, tabs: [
                KittyTab(id: 10, title: "Work", windows: [
                    KittyTabWindow(id: 100, title: "zsh", pid: 200, cwd: nil,
                                   env: ["KITTY_WINDOW_TTY": "/dev/ttys000"]),
                ]),
            ]),
        ]

        monitor.applySnapshot(snapshots, windows: [("unix:/tmp/test-kitty", windows)])

        let task = monitor.taskState.runningTasks.first
        XCTAssertNotNil(task?.sessionRef)
        XCTAssertEqual(task?.sessionRef?.kittyWindowId, 1)
        XCTAssertEqual(task?.sessionRef?.kittyTabId, 10)
        XCTAssertEqual(task?.sessionRef?.kittyLeafWindowId, 100)
        XCTAssertEqual(task?.sessionRef?.tty, "/dev/ttys000")
    }

    // MARK: - 多任务场景

    func testApplySnapshotMultipleTasks() {
        let discovery = ProcessDiscovery(procInfo: ProcInfo())
        let kitty = KittyIntegration(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
        let monitor = TaskMonitor(processDiscovery: discovery, kittyIntegration: kitty)

        let snapshots = [
            ProcessSnapshot(pid: 300, ppid: 200, tty: "/dev/ttys000",
                            command: "brew install ffmpeg", workingDirectory: nil, kind: .brew),
            ProcessSnapshot(pid: 400, ppid: 200, tty: "/dev/ttys000",
                            command: "npm run dev", workingDirectory: nil, kind: .npmRun),
            ProcessSnapshot(pid: 500, ppid: 200, tty: "/dev/ttys001",
                            command: "claude", workingDirectory: nil, kind: .claudeCode),
        ]

        monitor.applySnapshot(snapshots, windows: [])

        XCTAssertEqual(monitor.taskState.runningCount, 3)
        XCTAssertEqual(monitor.taskState.tasks.filter { $0.kind == .brew }.count, 1)
        XCTAssertEqual(monitor.taskState.tasks.filter { $0.kind == .npmRun }.count, 1)
        XCTAssertEqual(monitor.taskState.tasks.filter { $0.kind == .claudeCode }.count, 1)
    }

    // MARK: - 部分任务消失

    func testApplySnapshotPartialDisappearance() {
        let discovery = ProcessDiscovery(procInfo: ProcInfo())
        let kitty = KittyIntegration(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
        let monitor = TaskMonitor(processDiscovery: discovery, kittyIntegration: kitty)

        // 发现两个任务
        let snapshots1 = [
            ProcessSnapshot(pid: 300, ppid: 200, tty: "/dev/ttys000",
                            command: "brew install ffmpeg", workingDirectory: nil, kind: .brew),
            ProcessSnapshot(pid: 400, ppid: 200, tty: "/dev/ttys000",
                            command: "npm run dev", workingDirectory: nil, kind: .npmRun),
        ]
        monitor.applySnapshot(snapshots1, windows: [])

        // brew 完成，npm 还在
        let snapshots2 = [
            ProcessSnapshot(pid: 400, ppid: 200, tty: "/dev/ttys000",
                            command: "npm run dev", workingDirectory: nil, kind: .npmRun),
        ]
        monitor.applySnapshot(snapshots2, windows: [])

        XCTAssertEqual(monitor.taskState.runningCount, 1)
        XCTAssertEqual(monitor.taskState.runningTasks.first?.kind, .npmRun)
        XCTAssertEqual(monitor.taskState.tasks.filter { $0.status.isCompleted }.count, 1)
    }

    // MARK: - clearCompletedTasks

    func testClearCompletedTasks() {
        let discovery = ProcessDiscovery(procInfo: ProcInfo())
        let kitty = KittyIntegration(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
        let monitor = TaskMonitor(processDiscovery: discovery, kittyIntegration: kitty)

        let snapshots1 = [
            ProcessSnapshot(pid: 300, ppid: 200, tty: "/dev/ttys000",
                            command: "brew install ffmpeg", workingDirectory: nil, kind: .brew),
        ]
        monitor.applySnapshot(snapshots1, windows: [])

        // 任务消失 → 标记完成
        monitor.applySnapshot([], windows: [])
        XCTAssertEqual(monitor.taskState.tasks.filter { $0.status.isCompleted }.count, 1)

        monitor.clearCompletedTasks()
        XCTAssertEqual(monitor.taskState.tasks.count, 0)
    }

    func testRerunNodeTaskSendsTextToOriginalKittyTab() async {
        let discovery = ProcessDiscovery(procInfo: ProcInfo())

        final class Recorder: @unchecked Sendable {
            let lock = NSLock()
            var args: [String] = []
            func set(_ v: [String]) { lock.lock(); args = v; lock.unlock() }
            func get() -> [String] { lock.lock(); defer { lock.unlock() }; return args }
        }

        let recorder = Recorder()

        let detailedRunner: DetailedCommandRunner = { _, args, _ in
            recorder.set(args)
            return CommandOutput(stdout: "", stderr: "", exitCode: 0, timedOut: false)
        }

        let kitty = KittyIntegration(commandRunner: ShellCommandRunner(detailedRunner: detailedRunner, timeout: 0.2))
        let monitor = TaskMonitor(processDiscovery: discovery, kittyIntegration: kitty)
        monitor.setupState.kittyRemoteControlReady = true

        let windows = [
            KittyWindow(id: 1, tabs: [
                KittyTab(id: 10, title: "Work", windows: [
                    KittyTabWindow(id: 100, title: "zsh", pid: 200, cwd: nil,
                                   env: ["KITTY_WINDOW_TTY": "/dev/ttys000"]),
                ]),
            ]),
        ]

        let snapshots = [
            ProcessSnapshot(pid: 400, ppid: 200, tty: "/dev/ttys000",
                            command: "pnpm dev", workingDirectory: "/Users/seven/Projects/demo", kind: .pnpmRun),
        ]

        // Discover + attach sessionRef
        monitor.applySnapshot(snapshots, windows: [("unix:/tmp/test-kitty", windows)])
        monitor.applySnapshot([], windows: [("unix:/tmp/test-kitty", windows)])

        guard let task = monitor.taskState.tasks.first(where: { $0.kind == .pnpmRun }) else {
            XCTFail("Expected pnpm task")
            return
        }

        monitor.rerun(task: task)
        try? await Task.sleep(nanoseconds: 80_000_000) // give detached task a moment

        let calledArgs = recorder.get().joined(separator: " ")
        XCTAssertTrue(calledArgs.contains("send-text"))
        XCTAssertTrue(calledArgs.contains("id:100"))
        XCTAssertTrue(calledArgs.contains("cd"))
        XCTAssertTrue(calledArgs.contains("pnpm dev"))
    }

    // MARK: - 重复发现不创建重复任务

    func testApplySnapshotNoDuplicateDiscovery() {
        let discovery = ProcessDiscovery(procInfo: ProcInfo())
        let kitty = KittyIntegration(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
        let monitor = TaskMonitor(processDiscovery: discovery, kittyIntegration: kitty)

        let snapshots = [
            ProcessSnapshot(pid: 300, ppid: 200, tty: "/dev/ttys000",
                            command: "brew install ffmpeg", workingDirectory: nil, kind: .brew),
        ]

        // 连续两次 apply 相同快照
        monitor.applySnapshot(snapshots, windows: [])
        monitor.applySnapshot(snapshots, windows: [])

        XCTAssertEqual(monitor.taskState.runningCount, 1)
        XCTAssertEqual(monitor.taskState.tasks.count, 1)
    }

    // MARK: - 同目录同命令复用同一条记录

    func testApplySnapshotReusesSameSignatureAfterRestart() {
        let discovery = ProcessDiscovery(procInfo: ProcInfo())
        let kitty = KittyIntegration(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
        let monitor = TaskMonitor(processDiscovery: discovery, kittyIntegration: kitty)

        let cwd = "/Users/seven/Projects/demo"
        let snapshots1 = [
            ProcessSnapshot(pid: 300, ppid: 200, tty: "/dev/ttys000",
                            command: "npm run start", workingDirectory: cwd, kind: .npmRun),
        ]
        monitor.applySnapshot(snapshots1, windows: [])
        XCTAssertEqual(monitor.taskState.tasks.count, 1)
        XCTAssertEqual(monitor.taskState.runningCount, 1)

        // 进程消失 → 标记为 completed（History）
        monitor.applySnapshot([], windows: [])
        XCTAssertEqual(monitor.taskState.runningCount, 0)
        XCTAssertEqual(monitor.taskState.tasks.count, 1)
        XCTAssertEqual(monitor.taskState.tasks.first?.status.isCompleted, true)

        // 同目录同命令再次启动，但 pid 不同 → 应复用同一条记录（不新增）
        let snapshots2 = [
            ProcessSnapshot(pid: 333, ppid: 200, tty: "/dev/ttys000",
                            command: "npm run start", workingDirectory: cwd, kind: .npmRun),
        ]
        monitor.applySnapshot(snapshots2, windows: [])

        XCTAssertEqual(monitor.taskState.tasks.count, 1)
        XCTAssertEqual(monitor.taskState.runningCount, 1)
        XCTAssertEqual(monitor.taskState.runningTasks.first?.pid, 333)
        XCTAssertEqual(monitor.taskState.runningTasks.first?.status, .running)
    }
}