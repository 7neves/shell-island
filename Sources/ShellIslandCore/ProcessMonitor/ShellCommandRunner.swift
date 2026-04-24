import Foundation

public typealias CommandRunner = @Sendable (_ path: String, _ args: [String]) -> String?

public struct CommandOutput: Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let timedOut: Bool

    public init(stdout: String, stderr: String, exitCode: Int32, timedOut: Bool) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.timedOut = timedOut
    }
}

public typealias DetailedCommandRunner = @Sendable (_ path: String, _ args: [String], _ timeout: TimeInterval) -> CommandOutput?

public struct ShellCommandRunner: Sendable {
    let runner: CommandRunner
    let detailedRunner: DetailedCommandRunner
    let timeout: TimeInterval

    public init(runner: @escaping CommandRunner = Self.defaultRunner, timeout: TimeInterval = 0.5) {
        self.runner = runner
        self.detailedRunner = Self.makeDetailedRunner(from: runner)
        self.timeout = timeout
    }

    public init(detailedRunner: @escaping DetailedCommandRunner, timeout: TimeInterval = 0.5) {
        self.detailedRunner = detailedRunner
        self.timeout = timeout
        self.runner = { path, args in
            guard let result = detailedRunner(path, args, timeout) else { return nil }
            return result.timedOut ? nil : result.stdout
        }
    }

    public func run(_ path: String, _ args: [String]) -> String? {
        runner(path, args)
    }

    public func runDetailed(_ path: String, _ args: [String]) -> CommandOutput? {
        detailedRunner(path, args, timeout)
    }

    /// 预设超时配置
    public static let psTimeout: TimeInterval = 0.5
    public static let lsofTimeout: TimeInterval = 0.2
    public static let kittyTimeout: TimeInterval = 1.0

    /// 默认实现：Process + Pipe + 超时保护
    public static let defaultRunner: CommandRunner = { path, args in
        guard let result = defaultDetailedRunner(path, args, 0.5) else { return nil }
        return result.timedOut ? nil : result.stdout
    }

    public static let defaultDetailedRunner: DetailedCommandRunner = { path, args, timeout in
        final class Buffer: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var data = Data()

            func append(_ chunk: Data) {
                lock.lock()
                data.append(chunk)
                lock.unlock()
            }

            func take() -> Data {
                lock.lock()
                let value = data
                lock.unlock()
                return value
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        let stdoutBuffer = Buffer()
        let stderrBuffer = Buffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stdoutBuffer.append(chunk)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stderrBuffer.append(chunk)
        }

        process.terminationHandler = { _ in
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        let timedOut = (waitResult == .timedOut)

        if timedOut && process.isRunning {
            process.terminate()
            // Give it a brief moment to flush/exit.
            _ = semaphore.wait(timeout: .now() + 0.05)
        }

        // Stop handlers before final reads.
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // 读取剩余数据（process is likely done)
        stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        let stdoutData = stdoutBuffer.take()
        let stderrData = stderrBuffer.take()

        let stdout = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return CommandOutput(
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus,
            timedOut: timedOut
        )
    }

    static func makeDetailedRunner(from runner: @escaping CommandRunner) -> DetailedCommandRunner {
        { path, args, _ in
            guard let stdout = runner(path, args) else { return nil }
            return CommandOutput(stdout: stdout, stderr: "", exitCode: 0, timedOut: false)
        }
    }
}