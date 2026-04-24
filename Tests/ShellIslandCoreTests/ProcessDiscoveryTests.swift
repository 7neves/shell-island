import XCTest
@testable import ShellIslandCore

final class ProcessDiscoveryTests: XCTestCase {

    // MARK: - ps 输出解析

    func testParsePSOutput() {
        let psOutput = """
            1     0 ??      01:23:45 /sbin/launchd
            100   1 ??       00:00:01 /Applications/kitty.app/Contents/MacOS/kitty
            200 100 ttys000  00:00:10 /bin/zsh
            300 200 ttys000  00:01:00 brew install ffmpeg
            """
        let runner = ShellCommandRunner(runner: { path, args in
            XCTAssertEqual(path, "/bin/ps")
            return psOutput
        })

        let discovery = ProcessDiscovery(commandRunner: runner)
        let processes = discovery.runningProcesses()

        XCTAssertEqual(processes.count, 4)
        XCTAssertEqual(processes[0].pid, 1)
        XCTAssertEqual(processes[0].ppid, 0)
        XCTAssertEqual(processes[0].tty, "??")
        XCTAssertEqual(processes[0].command, "/sbin/launchd")

        XCTAssertEqual(processes[2].pid, 200)
        XCTAssertEqual(processes[2].ppid, 100)
        XCTAssertEqual(processes[2].tty, "ttys000")

        XCTAssertEqual(processes[3].pid, 300)
        XCTAssertEqual(processes[3].command, "brew install ffmpeg")
    }

    func testParseEmptyOutput() {
        let runner = ShellCommandRunner(runner: { _, _ in nil })
        let discovery = ProcessDiscovery(commandRunner: runner)
        let processes = discovery.runningProcesses()
        XCTAssertTrue(processes.isEmpty)
    }

    // MARK: - kitty 进程树识别

    func testIsInKittyTree() {
        let processes = [
            RunningProcess(pid: 1, ppid: 0, tty: "??", elapsed: "01:00:00", command: "/sbin/launchd"),
            RunningProcess(pid: 100, ppid: 1, tty: "??", elapsed: "00:10:00", command: "/Applications/kitty.app/Contents/MacOS/kitty"),
            RunningProcess(pid: 200, ppid: 100, tty: "ttys000", elapsed: "00:05:00", command: "/bin/zsh"),
            RunningProcess(pid: 300, ppid: 200, tty: "ttys000", elapsed: "00:01:00", command: "brew install foo"),
        ]
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })

        let runner = ShellCommandRunner(runner: { _, _ in "" })
        let discovery = ProcessDiscovery(commandRunner: runner)

        // brew 进程 (300) → zsh (200) → kitty (100) ✓
        XCTAssertTrue(discovery.isInKittyTree(pid: 300, byPID: byPID))
        // zsh (200) → kitty (100) ✓
        XCTAssertTrue(discovery.isInKittyTree(pid: 200, byPID: byPID))
        // kitty 本身 (100) ✓
        XCTAssertTrue(discovery.isInKittyTree(pid: 100, byPID: byPID))
        // launchd (1) ✗
        XCTAssertFalse(discovery.isInKittyTree(pid: 1, byPID: byPID))
    }

    func testIsNotInKittyTree() {
        let processes = [
            RunningProcess(pid: 1, ppid: 0, tty: "??", elapsed: "01:00:00", command: "/sbin/launchd"),
            RunningProcess(pid: 50, ppid: 1, tty: "??", elapsed: "00:10:00", command: "/Applications/Terminal.app/Contents/MacOS/Terminal"),
            RunningProcess(pid: 200, ppid: 50, tty: "ttys001", elapsed: "00:05:00", command: "/bin/zsh"),
            RunningProcess(pid: 300, ppid: 200, tty: "ttys001", elapsed: "00:01:00", command: "brew install foo"),
        ]
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })

        let runner = ShellCommandRunner(runner: { _, _ in "" })
        let discovery = ProcessDiscovery(commandRunner: runner)

        // brew 进程在 Terminal.app 下，不在 kitty 进程树
        XCTAssertFalse(discovery.isInKittyTree(pid: 300, byPID: byPID))
    }

    // MARK: - TaskKind 匹配

    func testMatchTaskKind() {
        let runner = ShellCommandRunner(runner: { _, _ in "" })
        let discovery = ProcessDiscovery(commandRunner: runner)

        XCTAssertEqual(discovery.matchTaskKind(command: "brew install ffmpeg"), .brew)
        XCTAssertEqual(discovery.matchTaskKind(command: "/opt/homebrew/bin/brew install git"), .brew)
        XCTAssertEqual(discovery.matchTaskKind(command: "codex fix bug"), .codex)
        XCTAssertEqual(discovery.matchTaskKind(command: "npm run build"), .npmRun)
        XCTAssertNil(discovery.matchTaskKind(command: "npm install"))
        XCTAssertNil(discovery.matchTaskKind(command: "git status"))
        XCTAssertNil(discovery.matchTaskKind(command: "/bin/zsh"))
    }

    // MARK: - kitty 进程判断

    func testIsKittyProcess() {
        let runner = ShellCommandRunner(runner: { _, _ in "" })
        let discovery = ProcessDiscovery(commandRunner: runner)

        XCTAssertTrue(discovery.isKittyProcess(command: "/Applications/kitty.app/Contents/MacOS/kitty"))
        XCTAssertTrue(discovery.isKittyProcess(command: "/usr/local/bin/kitty"))
        XCTAssertTrue(discovery.isKittyProcess(command: "kitty"))
        XCTAssertFalse(discovery.isKittyProcess(command: "/Applications/Terminal.app/Contents/MacOS/Terminal"))
        XCTAssertFalse(discovery.isKittyProcess(command: "/bin/zsh"))
    }

    // MARK: - TTY 归一化

    func testNormalizedTTY() {
        let runner = ShellCommandRunner(runner: { _, _ in "" })
        let discovery = ProcessDiscovery(commandRunner: runner)

        XCTAssertEqual(discovery.normalizedTTY("ttys000"), "/dev/ttys000")
        XCTAssertEqual(discovery.normalizedTTY("/dev/ttys001"), "/dev/ttys001")
        XCTAssertEqual(discovery.normalizedTTY("??"), "??")
    }

    // MARK: - 完整发现流程

    func testDiscoverTaskProcesses() {
        let psOutput = """
            1     0 ??      01:00:00 /sbin/launchd
            100   1 ??       00:10:00 /Applications/kitty.app/Contents/MacOS/kitty
            200 100 ttys000  00:05:00 /bin/zsh
            300 200 ttys000  00:01:00 brew install ffmpeg
            400 200 ttys000  00:00:30 npm run dev
            500   1 ttys001  00:02:00 brew install git
            """
        let runner = ShellCommandRunner(runner: { path, args in
            if path == "/bin/ps" { return psOutput }
            return nil
        })
        let lsofRunner = ShellCommandRunner(runner: { path, args in
            if path == "/usr/sbin/lsof" { return "n/Users/test/project" }
            return nil
        })

        let discovery = ProcessDiscovery(commandRunner: runner, lsofRunner: lsofRunner)
        let snapshots = discovery.discoverTaskProcesses()

        // 进程 300 和 400 在 kitty 树下且有 TTY，应被识别
        // 进程 500 不在 kitty 树下，应被排除
        let pids = snapshots.map { $0.pid }
        XCTAssertTrue(pids.contains(300))
        XCTAssertTrue(pids.contains(400))
        XCTAssertFalse(pids.contains(500))

        let brewTask = snapshots.first { $0.pid == 300 }
        XCTAssertEqual(brewTask?.kind, .brew)
        XCTAssertEqual(brewTask?.tty, "/dev/ttys000")
        XCTAssertEqual(brewTask?.workingDirectory, "/Users/test/project")

        let npmTask = snapshots.first { $0.pid == 400 }
        XCTAssertEqual(npmTask?.kind, .npmRun)
    }

    func testDiscoverTaskProcessesCollapsesMatchingAncestorAndChild() {
        let psOutput = """
            1     0 ??      01:00:00 /sbin/launchd
            100   1 ??       00:10:00 /Applications/kitty.app/Contents/MacOS/kitty
            200 100 ttys000  00:05:00 /bin/zsh
            300 200 ttys000  00:01:00 codex --dangerously-skip-permissions
            301 300 ttys000  00:00:58 codex --dangerously-skip-permissions
            """
        let runner = ShellCommandRunner(runner: { path, _ in
            if path == "/bin/ps" { return psOutput }
            return nil
        })
        let discovery = ProcessDiscovery(commandRunner: runner)

        let snapshots = discovery.discoverTaskProcesses()

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.pid, 300)
        XCTAssertEqual(snapshots.first?.kind, .codex)
    }

    func testDeduplicatedSnapshotsCollapsesEquivalentCommandOnSameTTY() {
        let runner = ShellCommandRunner(runner: { _, _ in "" })
        let discovery = ProcessDiscovery(commandRunner: runner)

        let snapshots = [
            ProcessSnapshot(
                pid: 300,
                ppid: 200,
                tty: "/dev/ttys000",
                command: "brew install ffmpeg",
                workingDirectory: nil,
                kind: .brew
            ),
            ProcessSnapshot(
                pid: 301,
                ppid: 200,
                tty: "/dev/ttys000",
                command: "/opt/homebrew/bin/brew install ffmpeg",
                workingDirectory: nil,
                kind: .brew
            ),
            ProcessSnapshot(
                pid: 500,
                ppid: 200,
                tty: "/dev/ttys001",
                command: "brew install ffmpeg",
                workingDirectory: nil,
                kind: .brew
            ),
        ]

        let deduped = discovery.deduplicatedSnapshots(snapshots)

        XCTAssertEqual(deduped.count, 2)
        XCTAssertTrue(deduped.contains(where: { $0.pid == 300 }))
        XCTAssertTrue(deduped.contains(where: { $0.pid == 500 }))
    }
}
