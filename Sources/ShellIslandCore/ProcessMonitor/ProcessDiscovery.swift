import Foundation

/// 一次进程扫描的快照
public struct ProcessSnapshot: Sendable, Equatable {
    public let pid: Int32
    public let ppid: Int32
    public let tty: String
    public let command: String
    public let workingDirectory: String?
    public let kind: TaskKind

    public init(
        pid: Int32, ppid: Int32, tty: String,
        command: String, workingDirectory: String?, kind: TaskKind
    ) {
        self.pid = pid
        self.ppid = ppid
        self.tty = tty
        self.command = command
        self.workingDirectory = workingDirectory
        self.kind = kind
    }
}

/// ps 输出解析后的中间结构
struct RunningProcess: Sendable, Equatable {
    let pid: Int32
    let ppid: Int32
    let tty: String
    let elapsed: String
    let command: String
}

/// 进程发现器：扫描 kitty 进程树中运行的 brew/codex/npm run 任务
public struct ProcessDiscovery: Sendable {
    let commandRunner: ShellCommandRunner
    let lsofRunner: ShellCommandRunner

    public init(
        commandRunner: ShellCommandRunner = ShellCommandRunner(timeout: ShellCommandRunner.psTimeout),
        lsofRunner: ShellCommandRunner = ShellCommandRunner(timeout: ShellCommandRunner.lsofTimeout)
    ) {
        self.commandRunner = commandRunner
        self.lsofRunner = lsofRunner
    }

    /// 发现 kitty 进程树中的任务进程
    public func discoverTaskProcesses() -> [ProcessSnapshot] {
        let processes = runningProcesses()
        guard !processes.isEmpty else { return [] }

        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        let candidates = processes.compactMap { proc -> ProcessSnapshot? in
            guard !proc.tty.isEmpty, !proc.command.isEmpty else { return nil }

            guard let kind = matchTaskKind(command: proc.command) else { return nil }
            guard isInKittyTree(pid: proc.pid, byPID: byPID) else { return nil }
            guard !hasMatchingAncestor(
                pid: proc.pid,
                kind: kind,
                tty: normalizedTTY(proc.tty),
                byPID: byPID
            ) else {
                return nil
            }

            let cwd = lsofWorkingDirectory(pid: proc.pid)
            return ProcessSnapshot(
                pid: proc.pid, ppid: proc.ppid,
                tty: normalizedTTY(proc.tty),
                command: proc.command,
                workingDirectory: cwd,
                kind: kind
            )
        }

        return deduplicatedSnapshots(candidates)
    }

    // MARK: - 内部方法

    /// 执行 ps 并解析进程列表
    func runningProcesses() -> [RunningProcess] {
        guard let output = commandRunner.run("/bin/ps", ["-Ao", "pid=,ppid=,tty=,etime=,command="]) else {
            return []
        }
        return output.split(separator: "\n").compactMap { line -> RunningProcess? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 5 else { return nil }

            guard let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else { return nil }

            let tty = String(parts[2])
            let elapsed = String(parts[3])
            let command = parts[4...].map(String.init).joined(separator: " ")

            return RunningProcess(
                pid: pid, ppid: ppid,
                tty: tty, elapsed: elapsed, command: command
            )
        }
    }

    /// 判断命令是否匹配已知任务类型
    func matchTaskKind(command: String) -> TaskKind? {
        for kind in [TaskKind.brew, .codex, .npmRun] {
            if kind.matches(command: command) { return kind }
        }
        return nil
    }

    /// 判断进程是否属于 kitty 进程树
    func isInKittyTree(pid: Int32, byPID: [Int32: RunningProcess]) -> Bool {
        var currentPID = pid
        var visited = Set<Int32>()

        while let proc = byPID[currentPID] {
            if visited.contains(currentPID) { break }
            visited.insert(currentPID)

            if isKittyProcess(command: proc.command) { return true }
            if proc.ppid <= 1 { break }
            currentPID = proc.ppid
        }
        return false
    }

    /// 判断进程是否是 kitty 本身
    func isKittyProcess(command: String) -> Bool {
        command.contains("/kitty.app/") || command.hasSuffix("/kitty") || command == "kitty"
    }

    /// 如果某个匹配任务的祖先进程本身也是相同 kind，则当前进程视为包装/重复层，不单独展示。
    func hasMatchingAncestor(
        pid: Int32,
        kind: TaskKind,
        tty: String,
        byPID: [Int32: RunningProcess]
    ) -> Bool {
        var currentPID = pid
        var visited = Set<Int32>()

        while let proc = byPID[currentPID] {
            if visited.contains(currentPID) { break }
            visited.insert(currentPID)

            let parentPID = proc.ppid
            guard parentPID > 1, let parent = byPID[parentPID] else { break }

            if normalizedTTY(parent.tty) == tty,
               matchTaskKind(command: parent.command) == kind {
                return true
            }

            currentPID = parentPID
        }

        return false
    }

    func deduplicatedSnapshots(_ snapshots: [ProcessSnapshot]) -> [ProcessSnapshot] {
        let grouped = Dictionary(grouping: snapshots) {
            SnapshotDedupKey(kind: $0.kind, tty: $0.tty, command: canonicalCommand($0.command))
        }

        return grouped.values.compactMap { group in
            group.min {
                if $0.pid == $1.pid {
                    return $0.command.count < $1.command.count
                }
                return $0.pid < $1.pid
            }
        }
        .sorted { lhs, rhs in
            if lhs.kind == rhs.kind {
                return lhs.pid < rhs.pid
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }

    func canonicalCommand(_ command: String) -> String {
        command
            .replacingOccurrences(of: "/usr/bin/env ", with: "")
            .replacingOccurrences(of: "/opt/homebrew/bin/", with: "")
            .replacingOccurrences(of: "/usr/local/bin/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 通过 lsof 获取进程工作目录
    func lsofWorkingDirectory(pid: Int32) -> String? {
        guard let output = lsofRunner.run("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-Fn"]) else {
            return nil
        }
        for line in output.split(separator: "\n") {
            if line.hasPrefix("n") {
                return String(line.dropFirst())
            }
        }
        return nil
    }

    /// TTY 归一化：确保有 /dev/ 前缀
    func normalizedTTY(_ tty: String) -> String {
        if tty.hasPrefix("/dev/") { return tty }
        if tty.hasPrefix("tty") { return "/dev/\(tty)" }
        return tty
    }
}

struct SnapshotDedupKey: Hashable {
    let kind: TaskKind
    let tty: String
    let command: String
}
