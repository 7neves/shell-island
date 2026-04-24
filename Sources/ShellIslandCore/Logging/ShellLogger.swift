@preconcurrency import os
import Foundation

public struct ShellLogger: Sendable {
    private let logger: Logger
    private let fileHandle: FileHandle?

    public init(subsystem: String = "com.shellisland", category: String = "general") {
        self.logger = Logger(subsystem: subsystem, category: category)

        let logsDir = Self.logsDirectory()
        let fm = FileManager.default
        if !fm.fileExists(atPath: logsDir.path) {
            try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }

        let logFile = logsDir.appendingPathComponent("shellisland.log")
        if !fm.fileExists(atPath: logFile.path) {
            fm.createFile(atPath: logFile.path, contents: nil)
        }
        self.fileHandle = try? FileHandle(forWritingTo: logFile)
        fileHandle?.seekToEndOfFile()
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        writeFile("INFO", message)
    }

    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        writeFile("DEBUG", message)
    }

    public func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        writeFile("WARN", message)
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        writeFile("ERROR", message)
    }

    private func writeFile(_ level: String, _ message: String) {
        let timestamp = Self.dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        fileHandle?.write(data)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static func logsDirectory() -> URL {
        let bundlePath = Bundle.main.bundleURL.deletingLastPathComponent().path
        if bundlePath.contains(".app") {
            return Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("logs")
        }
        return URL(fileURLWithPath: "logs")
    }
}
