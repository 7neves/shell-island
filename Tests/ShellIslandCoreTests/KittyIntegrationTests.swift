import XCTest
@testable import ShellIslandCore

final class KittyIntegrationTests: XCTestCase {
    private final class CallRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [[String]] = []

        func append(_ args: [String]) {
            lock.lock()
            _calls.append(args)
            lock.unlock()
        }

        func snapshot() -> [[String]] {
            lock.lock()
            let value = _calls
            lock.unlock()
            return value
        }
    }

    // MARK: - checkRemoteControlReady

    func testCheckRemoteControlReadySuccess() {
        let json = """
            [{"id": 1, "tabs": [{"id": 1, "title": "tab1", "windows": []}]}]
            """
        let runner = ShellCommandRunner(runner: { _, _ in json })
        let integration = KittyIntegration(commandRunner: runner)

        XCTAssertTrue(integration.checkRemoteControlReady())
    }

    func testCheckRemoteControlReadyFailure() {
        let runner = ShellCommandRunner(runner: { _, _ in nil })
        let integration = KittyIntegration(commandRunner: runner)

        XCTAssertFalse(integration.checkRemoteControlReady())
    }

    // MARK: - listWindows JSON 解析

    func testListWindowsParsing() {
        let json = """
            [{
                "id": 1,
                "tabs": [{
                    "id": 10,
                    "title": "Work",
                    "windows": [{
                        "id": 100,
                        "title": "zsh",
                        "pid": 12345,
                        "cwd": "/Users/test/project",
                        "env": {"KITTY_WINDOW_TTY": "/dev/ttys000"}
                    }]
                }]
            }]
            """
        let runner = ShellCommandRunner(runner: { _, _ in json })
        let integration = KittyIntegration(commandRunner: runner)

        let windows = integration.listWindows()
        XCTAssertNotNil(windows)
        XCTAssertEqual(windows?.count, 1)
        XCTAssertEqual(windows?.first?.id, 1)
        XCTAssertEqual(windows?.first?.tabs.first?.id, 10)
        XCTAssertEqual(windows?.first?.tabs.first?.windows.first?.pid, 12345)
        XCTAssertEqual(windows?.first?.tabs.first?.windows.first?.ttyFromEnv, "/dev/ttys000")
    }

    func testListWindowsInvalidJSON() {
        let runner = ShellCommandRunner(runner: { _, _ in "not json" })
        let integration = KittyIntegration(commandRunner: runner)

        XCTAssertNil(integration.listWindows())
    }

    func testListWindowsEmpty() {
        let runner = ShellCommandRunner(runner: { _, _ in "[]" })
        let integration = KittyIntegration(commandRunner: runner)

        let windows = integration.listWindows()
        XCTAssertEqual(windows?.count, 0)
    }

    // MARK: - findSessionRef TTY 匹配

    func testFindSessionRefByTTY() {
        let windows = [
            KittyWindow(id: 1, tabs: [
                KittyTab(id: 10, title: "Work", windows: [
                    KittyTabWindow(id: 100, title: "zsh", pid: 12345, cwd: nil,
                                   env: ["KITTY_WINDOW_TTY": "/dev/ttys000"]),
                ]),
            ]),
        ]

        let runner = ShellCommandRunner(runner: { _, _ in "" })
        let integration = KittyIntegration(commandRunner: runner)

        let ref = integration.findSessionRef(forTTY: "/dev/ttys000", windows: windows)
        XCTAssertNotNil(ref)
        XCTAssertEqual(ref?.kittyWindowId, 1)
        XCTAssertEqual(ref?.kittyTabId, 10)
        XCTAssertEqual(ref?.kittyLeafWindowId, 100)
        XCTAssertEqual(ref?.tty, "/dev/ttys000")
    }

    func testFindSessionRefByTTYNotFound() {
        let windows = [
            KittyWindow(id: 1, tabs: [
                KittyTab(id: 10, title: "Work", windows: [
                    KittyTabWindow(id: 100, title: "zsh", pid: 12345, cwd: nil,
                                   env: ["KITTY_WINDOW_TTY": "/dev/ttys000"]),
                ]),
            ]),
        ]

        let runner = ShellCommandRunner(runner: { _, _ in "" })
        let integration = KittyIntegration(commandRunner: runner)

        XCTAssertNil(integration.findSessionRef(forTTY: "/dev/ttys999", windows: windows))
    }

    func testFindSessionRefByPID() {
        let windows = [
            KittyWindow(id: 1, tabs: [
                KittyTab(id: 10, title: "Work", windows: [
                    KittyTabWindow(id: 100, title: "zsh", pid: 12345, cwd: nil,
                                   env: ["KITTY_WINDOW_TTY": "/dev/ttys000"]),
                ]),
            ]),
        ]

        let runner = ShellCommandRunner(runner: { _, _ in "" })
        let integration = KittyIntegration(commandRunner: runner)

        let ref = integration.findSessionRef(forPID: 12345, windows: windows)
        XCTAssertNotNil(ref)
        XCTAssertEqual(ref?.kittyWindowId, 1)
        XCTAssertEqual(ref?.kittyTabId, 10)
        XCTAssertEqual(ref?.kittyLeafWindowId, 100)
    }

    func testFindSessionRefByPIDNotFound() {
        let windows = [
            KittyWindow(id: 1, tabs: [
                KittyTab(id: 10, title: "Work", windows: [
                    KittyTabWindow(id: 100, title: "zsh", pid: 12345, cwd: nil, env: nil),
                ]),
            ]),
        ]

        let runner = ShellCommandRunner(runner: { _, _ in "" })
        let integration = KittyIntegration(commandRunner: runner)

        XCTAssertNil(integration.findSessionRef(forPID: 99999, windows: windows))
    }

    // MARK: - TTY 归一化匹配

    func testFindSessionRefWithNonNormalizedTTY() {
        let windows = [
            KittyWindow(id: 1, tabs: [
                KittyTab(id: 10, title: "Work", windows: [
                    KittyTabWindow(id: 100, title: "zsh", pid: 12345, cwd: nil,
                                   env: ["KITTY_WINDOW_TTY": "/dev/ttys000"]),
                ]),
            ]),
        ]

        let runner = ShellCommandRunner(runner: { _, _ in "" })
        let integration = KittyIntegration(commandRunner: runner)

        // 传入不带 /dev/ 前缀的 TTY，应自动归一化
        let ref = integration.findSessionRef(forTTY: "ttys000", windows: windows)
        XCTAssertNotNil(ref)
        XCTAssertEqual(ref?.tty, "/dev/ttys000")
    }

    // MARK: - jumpTo

    func testJumpToUsesLeafWindowId() throws {
        let recorder = CallRecorder()
        let runner = ShellCommandRunner(
            detailedRunner: { _, args, _ in
                recorder.append(args)
                return CommandOutput(stdout: "", stderr: "", exitCode: 0, timedOut: false)
            },
            timeout: 1.0
        )
        let integration = KittyIntegration(commandRunner: runner)

        let ref = TerminalSessionRef(
            terminalApp: "kitty",
            kittySocketAddress: nil,
            kittyWindowId: 1,
            kittyTabId: 10,
            kittyLeafWindowId: 100,
            tty: "/dev/ttys000"
        )

        try integration.jumpTo(sessionRef: ref)
        let calls = recorder.snapshot()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0], ["@", "focus-tab", "--match", "id:10"])
        XCTAssertEqual(calls[1], ["@", "focus-window", "--match", "id:100"])
    }

    func testJumpToThrowsWhenKittyCommandFails() {
        let runner = ShellCommandRunner(
            detailedRunner: { _, _, _ in
                CommandOutput(stdout: "", stderr: "no match", exitCode: 1, timedOut: false)
            },
            timeout: 1.0
        )
        let integration = KittyIntegration(commandRunner: runner)

        let ref = TerminalSessionRef(
            terminalApp: "kitty",
            kittySocketAddress: nil,
            kittyWindowId: 1,
            kittyTabId: 10,
            kittyLeafWindowId: 100,
            tty: "/dev/ttys000"
        )

        XCTAssertThrowsError(try integration.jumpTo(sessionRef: ref))
    }
}