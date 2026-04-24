import XCTest
import Foundation
@testable import ShellIslandCore

final class TaskStateTests: XCTestCase {

    func testInitialState() {
        let state = TaskState()
        XCTAssertTrue(state.tasks.isEmpty)
        XCTAssertEqual(state.runningCount, 0)
    }

    func testTaskDiscovered() {
        var state = TaskState()
        let task = makeTask(id: "t1", kind: .brew, status: .running)

        state.apply(.taskDiscovered(task))

        XCTAssertEqual(state.tasks.count, 1)
        XCTAssertEqual(state.runningCount, 1)
        XCTAssertEqual(state.task(id: "t1")?.kind, .brew)
    }

    func testTaskStatusChanged() {
        var state = TaskState()
        let task = makeTask(id: "t1", status: .running)
        state.apply(.taskDiscovered(task))

        state.apply(.taskStatusChanged("t1", .succeeded))

        XCTAssertEqual(state.task(id: "t1")?.status, .succeeded)
        XCTAssertEqual(state.runningCount, 0)
    }

    func testTaskCompleted() {
        var state = TaskState()
        state.apply(.taskDiscovered(makeTask(id: "t1", status: .running)))
        state.apply(.taskDiscovered(makeTask(id: "t2", status: .running)))

        state.apply(.taskCompleted("t1", 0))
        state.apply(.taskCompleted("t2", 1))

        XCTAssertEqual(state.task(id: "t1")?.status, .succeeded)
        XCTAssertEqual(state.task(id: "t2")?.status, .failed)
    }

    func testTaskTerminated() {
        var state = TaskState()
        state.apply(.taskDiscovered(makeTask(id: "t1", status: .running)))

        state.apply(.taskTerminated("t1", 9))

        XCTAssertEqual(state.task(id: "t1")?.status, .terminated)
        XCTAssertEqual(state.task(id: "t1")?.exitCode, 9)
    }

    func testSessionRefUpdated() {
        var state = TaskState()
        state.apply(.taskDiscovered(makeTask(id: "t1", status: .running)))

        let ref = TerminalSessionRef(terminalApp: "kitty", kittyWindowId: 1, kittyTabId: 2, tty: "ttys001")
        state.apply(.sessionRefUpdated("t1", ref))

        XCTAssertEqual(state.task(id: "t1")?.sessionRef, ref)
    }

    func testRemoveCompletedTasks() {
        var state = TaskState()
        state.apply(.taskDiscovered(makeTask(id: "t1", status: .running)))
        state.apply(.taskDiscovered(makeTask(id: "t2", status: .running)))
        state.apply(.taskCompleted("t2", 0))

        state.removeCompletedTasks()

        XCTAssertEqual(state.tasks.count, 1)
        XCTAssertNotNil(state.task(id: "t1"))
        XCTAssertNil(state.task(id: "t2"))
    }

    func testRunningTasks() {
        var state = TaskState()
        state.apply(.taskDiscovered(makeTask(id: "t1", status: .running)))
        state.apply(.taskDiscovered(makeTask(id: "t2", status: .running)))
        state.apply(.taskCompleted("t2", 0))

        XCTAssertEqual(state.runningTasks.count, 1)
        XCTAssertEqual(state.runningTasks.first?.id, "t1")
    }
}

// MARK: - TaskKind Tests

final class TaskKindTests: XCTestCase {

    func testMatchesBrew() {
        let kind = TaskKind.brew
        XCTAssertTrue(kind.matches(command: "brew install foo"))
        XCTAssertTrue(kind.matches(command: "/opt/homebrew/brew/bin/install"))
        XCTAssertFalse(kind.matches(command: "npm run build"))
    }

    func testMatchesCodex() {
        let kind = TaskKind.codex
        XCTAssertTrue(kind.matches(command: "codex fix bug"))
        XCTAssertTrue(kind.matches(command: "/usr/local/codex/bin/run"))
        XCTAssertFalse(kind.matches(command: "brew install codex"))
    }

    func testMatchesNpmRun() {
        XCTAssertTrue(TaskKind.npmRun.matches(command: "npm run build"))
        XCTAssertTrue(TaskKind.npmRun.matches(command: "npm run dev"))
        XCTAssertTrue(TaskKind.npmRun.matches(command: "npm start"))
        XCTAssertFalse(TaskKind.npmRun.matches(command: "npm install"))
        XCTAssertFalse(TaskKind.npmRun.matches(command: "npm"))
    }

    func testDisplayName() {
        XCTAssertEqual(TaskKind.brew.displayName, "brew")
        XCTAssertEqual(TaskKind.codex.displayName, "codex")
        XCTAssertEqual(TaskKind.npmRun.displayName, "npm run")
    }
}

// MARK: - TaskStatus Tests

final class TaskStatusTests: XCTestCase {

    func testIsRunning() {
        XCTAssertTrue(TaskStatus.running.isRunning)
        XCTAssertFalse(TaskStatus.succeeded.isRunning)
        XCTAssertFalse(TaskStatus.failed.isRunning)
        XCTAssertFalse(TaskStatus.terminated.isRunning)
    }

    func testIsCompleted() {
        XCTAssertFalse(TaskStatus.running.isCompleted)
        XCTAssertTrue(TaskStatus.succeeded.isCompleted)
        XCTAssertTrue(TaskStatus.failed.isCompleted)
        XCTAssertTrue(TaskStatus.terminated.isCompleted)
    }
}

// MARK: - SetupState Tests

final class SetupStateTests: XCTestCase {

    func testIsReady() {
        var state = SetupState()
        XCTAssertFalse(state.isReady)

        state.accessibilityGranted = true
        XCTAssertFalse(state.isReady)

        state.kittyRemoteControlReady = true
        XCTAssertTrue(state.isReady)
    }
}

// MARK: - ObservedTask Tests

final class ObservedTaskTests: XCTestCase {

    func testGenerateID() {
        let id = ObservedTask.generateID(pid: 1234, startTime: Date(timeIntervalSince1970: 1700000000))
        XCTAssertTrue(id.hasPrefix("1234-"))
    }

    func testFormatDuration() {
        XCTAssertEqual(ObservedTask.formatDuration(30), "30s")
        XCTAssertEqual(ObservedTask.formatDuration(90), "1m 30s")
        XCTAssertEqual(ObservedTask.formatDuration(3661), "1h 1m")
    }
}

// MARK: - Test Helpers

private func makeTask(
    id: String,
    kind: TaskKind = .brew,
    status: TaskStatus = .running
) -> ObservedTask {
    ObservedTask(
        id: id,
        kind: kind,
        pid: 1234,
        startTime: Date(),
        status: status,
        commandLine: "brew install foo",
        workingDirectory: "/Users/test/project",
        tty: "ttys001",
        sessionRef: nil,
        startedAt: Date(),
        endedAt: nil,
        exitCode: nil
    )
}
