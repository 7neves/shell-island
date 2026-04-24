import XCTest
@testable import ShellIslandCore

@MainActor
final class TaskMonitorTests: XCTestCase {

    // MARK: - 新任务发现

    func testApplySnapshotDiscoverNewTasks() {
        let discovery = ProcessDiscovery(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
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
        let discovery = ProcessDiscovery(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
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

    // MARK: - sessionRef 关联

    func testApplySnapshotUpdatesSessionRef() {
        let discovery = ProcessDiscovery(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
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
        let discovery = ProcessDiscovery(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
        let kitty = KittyIntegration(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
        let monitor = TaskMonitor(processDiscovery: discovery, kittyIntegration: kitty)

        let snapshots = [
            ProcessSnapshot(pid: 300, ppid: 200, tty: "/dev/ttys000",
                            command: "brew install ffmpeg", workingDirectory: nil, kind: .brew),
            ProcessSnapshot(pid: 400, ppid: 200, tty: "/dev/ttys000",
                            command: "npm run dev", workingDirectory: nil, kind: .npmRun),
            ProcessSnapshot(pid: 500, ppid: 200, tty: "/dev/ttys001",
                            command: "codex fix bug", workingDirectory: nil, kind: .codex),
        ]

        monitor.applySnapshot(snapshots, windows: [])

        XCTAssertEqual(monitor.taskState.runningCount, 3)
        XCTAssertEqual(monitor.taskState.tasks.filter { $0.kind == .brew }.count, 1)
        XCTAssertEqual(monitor.taskState.tasks.filter { $0.kind == .npmRun }.count, 1)
        XCTAssertEqual(monitor.taskState.tasks.filter { $0.kind == .codex }.count, 1)
    }

    // MARK: - 部分任务消失

    func testApplySnapshotPartialDisappearance() {
        let discovery = ProcessDiscovery(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
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
        let discovery = ProcessDiscovery(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
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

    // MARK: - 重复发现不创建重复任务

    func testApplySnapshotNoDuplicateDiscovery() {
        let discovery = ProcessDiscovery(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
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
        let discovery = ProcessDiscovery(commandRunner: ShellCommandRunner(runner: { _, _ in "" }))
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