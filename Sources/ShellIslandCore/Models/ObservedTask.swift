import Foundation

public struct ObservedTask: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let kind: TaskKind
    public let pid: Int32
    public let startTime: Date
    public var status: TaskStatus
    public let commandLine: String
    public let workingDirectory: String?
    public let tty: String?
    public var sessionRef: TerminalSessionRef?
    public let startedAt: Date
    public var endedAt: Date?
    public var exitCode: Int32?

    public init(
        id: String,
        kind: TaskKind,
        pid: Int32,
        startTime: Date,
        status: TaskStatus,
        commandLine: String,
        workingDirectory: String?,
        tty: String?,
        sessionRef: TerminalSessionRef?,
        startedAt: Date,
        endedAt: Date?,
        exitCode: Int32?
    ) {
        self.id = id
        self.kind = kind
        self.pid = pid
        self.startTime = startTime
        self.status = status
        self.commandLine = commandLine
        self.workingDirectory = workingDirectory
        self.tty = tty
        self.sessionRef = sessionRef
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exitCode = exitCode
    }

    public var duration: String {
        let end = endedAt ?? Date()
        let interval = end.timeIntervalSince(startedAt)
        return Self.formatDuration(interval)
    }

    public var projectName: String? {
        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        let url = URL(fileURLWithPath: workingDirectory)
        let name = url.lastPathComponent
        return name.isEmpty ? nil : name
    }

    public static func generateID(pid: Int32, startTime: Date) -> String {
        "\(pid)-\(Int(startTime.timeIntervalSince1970))"
    }

    /// Stable task identifier signature used to dedupe and reuse history entries.
    /// Designed for the product requirement: "same working directory + same command" maps to the same task row.
    public static func signature(kind: TaskKind, commandLine: String, workingDirectory: String?) -> String {
        let canonical = canonicalCommand(commandLine)
        let cwd = normalizedWorkingDirectory(workingDirectory)
        return "\(kind.rawValue)|\(cwd)|\(canonical)"
    }

    private static func canonicalCommand(_ command: String) -> String {
        command
            .replacingOccurrences(of: "/usr/bin/env ", with: "")
            .replacingOccurrences(of: "/opt/homebrew/bin/", with: "")
            .replacingOccurrences(of: "/usr/local/bin/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedWorkingDirectory(_ workingDirectory: String?) -> String {
        guard let workingDirectory, !workingDirectory.isEmpty else { return "" }
        let url = URL(fileURLWithPath: workingDirectory)
        return url.standardizedFileURL.path
    }

    public static func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}
