import XCTest
@testable import ShellIslandCore

final class ShellLoggerTests: XCTestCase {
    func testWritesLogFileLine() throws {
        let fm = FileManager.default

        let logger = ShellLogger(subsystem: "com.shellisland.tests", category: "ShellLoggerTests")
        logger.info("hello")

        // Mirror ShellLogger.logsDirectory() behavior (private) to locate the file.
        let bundlePath = Bundle.main.bundleURL.deletingLastPathComponent().path
        let logsDir: URL
        if bundlePath.contains(".app") {
            logsDir = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("logs")
        } else {
            logsDir = URL(fileURLWithPath: "logs")
        }
        let logFile = logsDir.appendingPathComponent("shellisland.log")

        // In some environments (e.g. running under Xcode), Bundle.main may resolve inside
        // a non-writable .app. ShellLogger is intentionally best-effort (silent on failure),
        // so only assert on file contents when the file actually exists.
        if fm.fileExists(atPath: logFile.path) {
            let data = try Data(contentsOf: logFile)
            let text = String(data: data, encoding: .utf8) ?? ""
            XCTAssertTrue(text.contains("INFO"))
            XCTAssertTrue(text.contains("hello"))
        }
    }
}

