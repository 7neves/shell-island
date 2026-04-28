import XCTest
@testable import ShellIslandCore

final class ProcessDiscoveryTests: XCTestCase {

    // MARK: - 进程扫描

    func testFetchProcesses() {
        let mockProcesses = [
            ProcProcessInfo(pid: 1, ppid: 0, tty: "??", command: "/sbin/launchd", workingDirectory: nil),
            ProcProcessInfo(pid: 100, ppid: 1, tty: "??", command: "/Applications/kitty.app/Contents/MacOS/kitty", workingDirectory: nil),
            ProcProcessInfo(pid: 200, ppid: 100, tty: "/dev/ttys000", command: "/bin/zsh", workingDirectory: nil),
            ProcProcessInfo(pid: 300, ppid: 200, tty: "/dev/ttys000", command: "brew install ffmpeg", workingDirectory: nil),
        ]

        let discovery = ProcessDiscovery(procInfo: ProcInfo(listAll: { mockProcesses }))
        let processes = discovery.fetchProcesses()

        XCTAssertEqual(processes.count, 4)
        XCTAssertEqual(processes[0].pid, 1)
        XCTAssertEqual(processes[0].ppid, 0)
        XCTAssertEqual(processes[0].tty, "??")
        XCTAssertEqual(processes[0].command, "/sbin/launchd")

        XCTAssertEqual(processes[2].pid, 200)
        XCTAssertEqual(processes[2].ppid, 100)
        XCTAssertEqual(processes[2].tty, "/dev/ttys000")

        XCTAssertEqual(processes[3].pid, 300)
        XCTAssertEqual(processes[3].command, "brew install ffmpeg")
    }

    func testFetchProcessesEmpty() {
        let discovery = ProcessDiscovery(procInfo: ProcInfo(listAll: { [] }))
        let processes = discovery.fetchProcesses()
        XCTAssertTrue(processes.isEmpty)
    }

    // MARK: - kitty 进程树识别

    func testIsInKittyTree() {
        let processes = [
            ProcProcessInfo(pid: 1, ppid: 0, tty: "??", command: "/sbin/launchd", workingDirectory: nil),
            ProcProcessInfo(pid: 100, ppid: 1, tty: "??", command: "/Applications/kitty.app/Contents/MacOS/kitty", workingDirectory: nil),
            ProcProcessInfo(pid: 200, ppid: 100, tty: "/dev/ttys000", command: "/bin/zsh", workingDirectory: nil),
            ProcProcessInfo(pid: 300, ppid: 200, tty: "/dev/ttys000", command: "brew install foo", workingDirectory: nil),
        ]
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })

        let discovery = ProcessDiscovery(procInfo: ProcInfo())

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
            ProcProcessInfo(pid: 1, ppid: 0, tty: "??", command: "/sbin/launchd", workingDirectory: nil),
            ProcProcessInfo(pid: 50, ppid: 1, tty: "??", command: "/Applications/Terminal.app/Contents/MacOS/Terminal", workingDirectory: nil),
            ProcProcessInfo(pid: 200, ppid: 50, tty: "/dev/ttys001", command: "/bin/zsh", workingDirectory: nil),
            ProcProcessInfo(pid: 300, ppid: 200, tty: "/dev/ttys001", command: "brew install foo", workingDirectory: nil),
        ]
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })

        let discovery = ProcessDiscovery(procInfo: ProcInfo())

        // brew 进程在 Terminal.app 下，不在 kitty 进程树
        XCTAssertFalse(discovery.isInKittyTree(pid: 300, byPID: byPID))
    }

    // MARK: - TaskKind 匹配

    func testMatchTaskKind() {
        let discovery = ProcessDiscovery(procInfo: ProcInfo())

        XCTAssertEqual(discovery.matchTaskKind(command: "brew install ffmpeg"), .brew)
        XCTAssertEqual(discovery.matchTaskKind(command: "/opt/homebrew/bin/brew install git"), .brew)
        // brew 实际以 ruby 进程运行（Homebrew 是 Ruby 应用）
        XCTAssertEqual(discovery.matchTaskKind(command: "/opt/homebrew/Library/Homebrew/vendor/portable-ruby/current/bin/ruby -W1 -- /opt/homebrew/Library/Homebrew/brew.rb install mole"), .brew)
        XCTAssertEqual(discovery.matchTaskKind(command: "ruby /usr/local/Homebrew/brew.rb install git"), .brew)
        XCTAssertEqual(discovery.matchTaskKind(command: "claude"), .claudeCode)
        XCTAssertEqual(discovery.matchTaskKind(command: "claude --help"), .claudeCode)
        XCTAssertEqual(discovery.matchTaskKind(command: "/usr/local/bin/claude"), .claudeCode)
        XCTAssertEqual(discovery.matchTaskKind(command: "npm run build"), .npmRun)
        XCTAssertEqual(discovery.matchTaskKind(command: "pnpm run dev"), .pnpmRun)
        XCTAssertEqual(discovery.matchTaskKind(command: "pnpm dev"), .pnpmRun)
        XCTAssertEqual(discovery.matchTaskKind(command: "pnpm start"), .pnpmRun)
        XCTAssertEqual(discovery.matchTaskKind(command: "/opt/homebrew/bin/pnpm run dev"), .pnpmRun)
        XCTAssertEqual(discovery.matchTaskKind(command: "/usr/local/bin/pnpm start"), .pnpmRun)
        // pnpm 以 node wrapper 形式运行（真实场景）
        XCTAssertEqual(discovery.matchTaskKind(command: "node /Users/seven/Library/pnpm/global/5/node_modules/pnpm/bin/pnpm.cjs run dev"), .pnpmRun)
        XCTAssertEqual(discovery.matchTaskKind(command: "node /usr/local/lib/node_modules/pnpm/bin/pnpm.cjs start"), .pnpmRun)
        XCTAssertEqual(discovery.matchTaskKind(command: "yarn run build"), .yarnRun)
        XCTAssertEqual(discovery.matchTaskKind(command: "yarn dev"), .yarnRun)
        XCTAssertEqual(discovery.matchTaskKind(command: "yarn start"), .yarnRun)
        XCTAssertEqual(discovery.matchTaskKind(command: "/opt/homebrew/bin/yarn run dev"), .yarnRun)
        XCTAssertEqual(discovery.matchTaskKind(command: "/usr/local/bin/yarn start"), .yarnRun)
        // yarn 以 node wrapper 形式运行
        XCTAssertEqual(discovery.matchTaskKind(command: "node /usr/local/lib/node_modules/yarn/bin/yarn.js run dev"), .yarnRun)
        XCTAssertNil(discovery.matchTaskKind(command: "npm install"))
        XCTAssertNil(discovery.matchTaskKind(command: "yarn add lodash"))
        XCTAssertNil(discovery.matchTaskKind(command: "pnpm install"))
        XCTAssertNil(discovery.matchTaskKind(command: "git status"))
        XCTAssertNil(discovery.matchTaskKind(command: "/bin/zsh"))
    }

    // MARK: - kitty 进程判断

    func testIsKittyProcess() {
        let discovery = ProcessDiscovery(procInfo: ProcInfo())

        XCTAssertTrue(discovery.isKittyProcess(command: "/Applications/kitty.app/Contents/MacOS/kitty"))
        XCTAssertTrue(discovery.isKittyProcess(command: "/usr/local/bin/kitty"))
        XCTAssertTrue(discovery.isKittyProcess(command: "kitty"))
        XCTAssertFalse(discovery.isKittyProcess(command: "/Applications/Terminal.app/Contents/MacOS/Terminal"))
        XCTAssertFalse(discovery.isKittyProcess(command: "/bin/zsh"))
    }

    // MARK: - 完整发现流程

    func testDiscoverTaskProcesses() {
        let processes = [
            ProcProcessInfo(pid: 1, ppid: 0, tty: "??", command: "/sbin/launchd", workingDirectory: nil),
            ProcProcessInfo(pid: 100, ppid: 1, tty: "??", command: "/Applications/kitty.app/Contents/MacOS/kitty", workingDirectory: nil),
            ProcProcessInfo(pid: 200, ppid: 100, tty: "/dev/ttys000", command: "/bin/zsh", workingDirectory: nil),
            ProcProcessInfo(pid: 300, ppid: 200, tty: "/dev/ttys000", command: "brew install ffmpeg", workingDirectory: "/Users/test/project"),
            ProcProcessInfo(pid: 400, ppid: 200, tty: "/dev/ttys000", command: "npm run dev", workingDirectory: "/Users/test/project"),
            ProcProcessInfo(pid: 500, ppid: 1, tty: "/dev/ttys001", command: "brew install git", workingDirectory: nil),
        ]

        let discovery = ProcessDiscovery(procInfo: ProcInfo(listAll: { processes }))
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
        let processes = [
            ProcProcessInfo(pid: 1, ppid: 0, tty: "??", command: "/sbin/launchd", workingDirectory: nil),
            ProcProcessInfo(pid: 100, ppid: 1, tty: "??", command: "/Applications/kitty.app/Contents/MacOS/kitty", workingDirectory: nil),
            ProcProcessInfo(pid: 200, ppid: 100, tty: "/dev/ttys000", command: "/bin/zsh", workingDirectory: nil),
            ProcProcessInfo(pid: 300, ppid: 200, tty: "/dev/ttys000", command: "claude", workingDirectory: nil),
            ProcProcessInfo(pid: 301, ppid: 300, tty: "/dev/ttys000", command: "claude", workingDirectory: nil),
        ]

        let discovery = ProcessDiscovery(procInfo: ProcInfo(listAll: { processes }))
        let snapshots = discovery.discoverTaskProcesses()

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.pid, 300)
        XCTAssertEqual(snapshots.first?.kind, .claudeCode)
    }

    func testDeduplicatedSnapshotsCollapsesEquivalentCommandOnSameTTY() {
        let discovery = ProcessDiscovery(procInfo: ProcInfo())

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
