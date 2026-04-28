import Foundation

/// kitty 终端集成：通过 kitty @ 远程控制协议交互
public struct KittyIntegration: Sendable {
    let commandRunner: ShellCommandRunner
    let socketAddress: String?
    let procInfo: ProcInfo

    public enum KittyIntegrationError: Error, CustomStringConvertible {
        case commandFailed(command: String, stdout: String, stderr: String, exitCode: Int32, timedOut: Bool)

        public var description: String {
            switch self {
            case let .commandFailed(command, stdout, stderr, exitCode, timedOut):
                var parts = ["command=\(command)"]
                parts.append("exitCode=\(exitCode)")
                if timedOut { parts.append("timedOut=true") }
                if !stdout.isEmpty { parts.append("stdout=\(stdout)") }
                if !stderr.isEmpty { parts.append("stderr=\(stderr)") }
                return "KittyIntegrationError.commandFailed(\(parts.joined(separator: ", ")))"
            }
        }
    }

    public init(
        commandRunner: ShellCommandRunner = ShellCommandRunner(timeout: ShellCommandRunner.kittyTimeout),
        socketAddress: String? = ProcessInfo.processInfo.environment["KITTY_LISTEN_ON"],
        procInfo: ProcInfo = .live
    ) {
        self.commandRunner = commandRunner
        self.socketAddress = socketAddress
        self.procInfo = procInfo
    }

    /// 检查 kitty 是否开启了 allow_remote_control
    public func checkRemoteControlReady() -> Bool {
        listWindows() != nil
    }

    /// 获取 kitty 的所有窗口和标签页
    public func listWindows() -> [KittyWindow]? {
        guard let result = commandRunner.runDetailed(kittyExecutable, kittyArgs(["@", "ls"], overrideSocket: nil)),
              !result.timedOut,
              result.exitCode == 0 else {
            return nil
        }
        do {
            let data = Data(result.stdout.utf8)
            let decoded = try JSONDecoder().decode([KittyWindow].self, from: data)
            return decoded
        } catch {
            return nil
        }
    }

    /// 获取所有可用 kitty socket 的窗口列表（用于自动选择主 kitty / quick-access）
    public func listWindowsBySocket() -> [(socket: String, windows: [KittyWindow])] {
        let sockets = resolvedSocketCandidates()
        var results: [(socket: String, windows: [KittyWindow])] = []

        for socket in sockets {
            guard let output = listWindows(usingSocket: socket) else { continue }
            results.append((socket: socket, windows: output))
        }
        return results
    }

    private func listWindows(usingSocket socket: String) -> [KittyWindow]? {
        guard let result = commandRunner.runDetailed(kittyExecutable, kittyArgs(["@", "ls"], overrideSocket: socket)),
              !result.timedOut,
              result.exitCode == 0 else {
            return nil
        }
        do {
            let data = Data(result.stdout.utf8)
            return try JSONDecoder().decode([KittyWindow].self, from: data)
        } catch {
            return nil
        }
    }

    /// 在 kitty 窗口树中按 TTY/PID 查找 sessionRef
    public func findSessionRef(
        forTTY tty: String,
        windows: [KittyWindow],
        socket: String? = nil
    ) -> TerminalSessionRef? {
        let normalized = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"

        for window in windows {
            for tab in window.tabs {
                for win in tab.windows {
                    // 按 TTY 环境变量匹配
                    if let winTTY = win.ttyFromEnv, winTTY == normalized {
                        return TerminalSessionRef(
                            terminalApp: "kitty",
                            kittySocketAddress: socket,
                            kittyWindowId: window.id,
                            kittyTabId: tab.id,
                            kittyLeafWindowId: win.id,
                            tty: normalized
                        )
                    }
                }
            }
        }
        return nil
    }

    /// 按 PID 查找 sessionRef（TTY 匹配的 fallback）
    public func findSessionRef(
        forPID pid: Int32,
        windows: [KittyWindow],
        socket: String? = nil
    ) -> TerminalSessionRef? {
        // 1) 直接匹配 leaf window pid
        if let direct = findLeafWindowSessionRef(forPID: pid, windows: windows, socket: socket) {
            return direct
        }

        // 2) 对于 npm/claude/brew 等子进程，kitty @ ls 里的 pid 往往是所在 shell 的 pid。
        //    这里沿父进程链向上查找，直到命中某个 leaf window pid。
        var current: Int32? = pid
        var visited = Set<Int32>()
        for _ in 0..<25 {
            guard let cur = current, cur > 1 else { break }
            if visited.contains(cur) { break }
            visited.insert(cur)

            if let hit = findLeafWindowSessionRef(forPID: cur, windows: windows, socket: socket) {
                return hit
            }
            current = parentPID(of: cur)
        }

        return nil
    }

    private func findLeafWindowSessionRef(forPID pid: Int32, windows: [KittyWindow], socket: String?) -> TerminalSessionRef? {
        for window in windows {
            for tab in window.tabs {
                for win in tab.windows {
                    if win.pid == pid {
                        let tty = win.ttyFromEnv ?? ""
                        return TerminalSessionRef(
                            terminalApp: "kitty",
                            kittySocketAddress: socket,
                            kittyWindowId: window.id,
                            kittyTabId: tab.id,
                            kittyLeafWindowId: win.id,
                            tty: tty
                        )
                    }
                }
            }
        }
        return nil
    }

    private func parentPID(of pid: Int32) -> Int32? {
        procInfo.parentPID(pid)
    }

    /// 跳转到指定 kitty 窗口/标签页
    public func jumpTo(sessionRef: TerminalSessionRef) throws {
        guard sessionRef.kittyLeafWindowId != 0 else {
            throw KittyIntegrationError.commandFailed(
                command: "kitty @ focus-window --match id:<missing>",
                stdout: "",
                stderr: "kittyLeafWindowId is 0 (no session match). If this persists, ensure kitty remote control is available via socket (listen_on + KITTY_LISTEN_ON).",
                exitCode: -1,
                timedOut: false
            )
        }
        // 先聚焦标签页
        try runKittyCommandOrThrow(kittyArgs(["@", "focus-tab", "--match", "id:\(sessionRef.kittyTabId)"], overrideSocket: sessionRef.kittySocketAddress))
        // 再聚焦 leaf window
        try runKittyCommandOrThrow(kittyArgs(["@", "focus-window", "--match", "id:\(sessionRef.kittyLeafWindowId)"], overrideSocket: sessionRef.kittySocketAddress))
    }

    public func launchCommandInNewTab(
        commandLine: String,
        cwd: String,
        preferredSocket: String?
    ) throws {
        let sockets = resolvedSocketCandidates()
        var orderedSockets: [String] = []
        if let preferredSocket, !preferredSocket.isEmpty {
            orderedSockets.append(preferredSocket)
        }
        orderedSockets.append(contentsOf: sockets.filter { $0 != preferredSocket })

        let argsBase = ["@", "launch", "--type=tab", "--cwd", cwd, "zsh", "-lc", commandLine]

        var lastError: Error?
        for socket in orderedSockets {
            do {
                try runKittyCommandOrThrow(kittyArgs(argsBase, overrideSocket: socket))
                return
            } catch {
                lastError = error
                continue
            }
        }

        // If we couldn't find a socket (or all failed), try without --to (will work only when a TTY is available).
        do {
            try runKittyCommandOrThrow(argsBase)
            return
        } catch {
            lastError = lastError ?? error
        }

        throw lastError ?? KittyIntegrationError.commandFailed(
            command: argsBase.joined(separator: " "),
            stdout: "",
            stderr: "Unable to launch command via kitty remote control",
            exitCode: -1,
            timedOut: false
        )
    }

    /// Send text to an existing kitty leaf window (best-effort).
    /// Note: The caller is responsible for including a trailing newline when they want to press Enter.
    public func sendText(leafWindowId: Int, socket: String?, text: String) throws {
        guard leafWindowId != 0 else {
            throw KittyIntegrationError.commandFailed(
                command: "kitty @ send-text --match id:<missing>",
                stdout: "",
                stderr: "leafWindowId is 0 (no session match).",
                exitCode: -1,
                timedOut: false
            )
        }
        let args = kittyArgs(
            ["@", "send-text", "--match", "id:\(leafWindowId)", text],
            overrideSocket: socket
        )
        try runKittyCommandOrThrow(args)
    }

    /// Capture recent text from a kitty leaf window (best-effort).
    public func getText(leafWindowId: Int, socket: String?) -> String? {
        guard leafWindowId != 0 else { return nil }
        let args = kittyArgs(
            ["@", "get-text", "--match", "id:\(leafWindowId)", "--extent", "screen", "--ansi", "false"],
            overrideSocket: socket
        )
        guard let result = commandRunner.runDetailed(kittyExecutable, args),
              !result.timedOut,
              result.exitCode == 0 else {
            return nil
        }
        return result.stdout
    }

    /// Capture full scrollback text from a kitty leaf window (best-effort).
    /// This is heavier than `getText` but necessary for detecting errors that have scrolled off-screen.
    public func getTextAll(leafWindowId: Int, socket: String?) -> String? {
        guard leafWindowId != 0 else { return nil }
        let args = kittyArgs(
            ["@", "get-text", "--match", "id:\(leafWindowId)", "--extent", "all", "--ansi", "false"],
            overrideSocket: socket
        )
        guard let result = commandRunner.runDetailed(kittyExecutable, args),
              !result.timedOut,
              result.exitCode == 0 else {
            return nil
        }
        return result.stdout
    }

    private func runKittyCommandOrThrow(_ args: [String]) throws {
        guard let result = commandRunner.runDetailed(kittyExecutable, args) else {
            throw KittyIntegrationError.commandFailed(
                command: args.joined(separator: " "),
                stdout: "",
                stderr: "",
                exitCode: -1,
                timedOut: false
            )
        }

        guard !result.timedOut, result.exitCode == 0 else {
            let extraHint: String
            if result.stderr.contains("/dev/tty") {
                extraHint = "\nHint: kitty remote control from background/agent processes requires a socket. Configure kitty.conf with `listen_on unix:/tmp/kitty` and set `KITTY_LISTEN_ON=unix:/tmp/kitty` (or pass --to)."
            } else {
                extraHint = ""
            }
            throw KittyIntegrationError.commandFailed(
                command: args.joined(separator: " "),
                stdout: result.stdout,
                stderr: result.stderr + extraHint,
                exitCode: result.exitCode,
                timedOut: result.timedOut
            )
        }
    }

    private var kittyExecutable: String {
        let fm = FileManager.default
        let candidates = [
            "/Applications/kitty.app/Contents/MacOS/kitty",
            "/opt/homebrew/bin/kitty",
            "/usr/local/bin/kitty",
            "/usr/bin/kitty",
            "kitty"
        ]
        for path in candidates {
            if path == "kitty" { return path }
            if fm.isExecutableFile(atPath: path) { return path }
        }
        return "kitty"
    }

    private func kittyArgs(_ base: [String]) -> [String] {
        kittyArgs(base, overrideSocket: nil)
    }

    private func kittyArgs(_ base: [String], overrideSocket: String?) -> [String] {
        let address = overrideSocket ?? resolvedSocketAddress
        guard let address, !address.isEmpty else { return base }
        // base begins with "@"
        return ["@", "--to", address] + base.dropFirst()
    }

    /// Prefer KITTY_LISTEN_ON when available; otherwise probe common /tmp sockets.
    private var resolvedSocketAddress: String? {
        if let socketAddress, !socketAddress.isEmpty { return socketAddress }

        // Keep tests deterministic: do not probe the host machine for sockets under XCTest.
        if NSClassFromString("XCTestCase") != nil {
            return nil
        }

        let candidates = [
            "/tmp/mykitty",
            "/tmp/kitty-quick-access",
            "/tmp/kitty"
        ]

        for basePath in candidates {
            if let exact = existingSocketPath(forBasePath: basePath) {
                return "unix:\(exact)"
            }
        }

        return nil
    }

    private func resolvedSocketCandidates() -> [String] {
        // 1) Explicit env socket first
        if let socketAddress, !socketAddress.isEmpty {
            return [socketAddress]
        }
        // 2) Probe common /tmp sockets (including pid suffix)
        if NSClassFromString("XCTestCase") != nil {
            return []
        }

        let basePaths = [
            "/tmp/mykitty",
            "/tmp/kitty-quick-access",
            "/tmp/kitty"
        ]

        var candidates: [String] = []
        for base in basePaths {
            candidates.append(contentsOf: existingSocketPaths(forBasePath: base).map { "unix:\($0)" })
        }

        // Ensure uniqueness while keeping order.
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private func existingSocketPath(forBasePath basePath: String) -> String? {
        existingSocketPaths(forBasePath: basePath).first
    }

    private func existingSocketPaths(forBasePath basePath: String) -> [String] {
        let fm = FileManager.default

        let dir = URL(fileURLWithPath: basePath).deletingLastPathComponent()
        let baseName = URL(fileURLWithPath: basePath).lastPathComponent

        var matches: [String] = []
        if fm.fileExists(atPath: basePath) {
            matches.append(basePath)
        }

        if let entries = try? fm.contentsOfDirectory(atPath: dir.path) {
            matches.append(contentsOf: entries
                .filter { $0.hasPrefix("\(baseName)-") }
                .map { dir.appendingPathComponent($0).path }
                .filter { fm.fileExists(atPath: $0) })
        }

        // Sort by preference score (desc), then modification date (desc)
        return matches.sorted { lhs, rhs in
            let lScore = socketPreferenceScore(path: lhs)
            let rScore = socketPreferenceScore(path: rhs)
            if lScore != rScore { return lScore > rScore }

            let lDate = (try? fm.attributesOfItem(atPath: lhs)[.modificationDate] as? Date) ?? .distantPast
            let rDate = (try? fm.attributesOfItem(atPath: rhs)[.modificationDate] as? Date) ?? .distantPast
            return lDate > rDate
        }
    }

    private func socketPreferenceScore(path: String) -> Int {
        // Higher is better.
        // If the path ends with "-<pid>" and that pid is the main kitty binary, prefer it.
        guard let pid = Int32(path.split(separator: "-").last ?? ""),
              let cmd = procInfo.processCommand(pid) else { return 0 }
        if cmd.contains("/Applications/kitty.app/Contents/MacOS/kitty") {
            return 10
        }
        if cmd.contains("kitty-quick-access") {
            return 1
        }
        return 0
    }
}