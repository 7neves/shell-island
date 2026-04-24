import XCTest
@testable import ShellIslandCore

final class AppModelSmokeTests: XCTestCase {

    func testAppPreferencesDefaults() {
        let prefs = AppPreferences()
        XCTAssertFalse(prefs.launchAtLogin)
        XCTAssertEqual(prefs.pollIntervalSeconds, 1.0)
        XCTAssertTrue(prefs.keepCompletedUntilManualClear)
    }

    func testTerminalSessionRefUnknown() {
        let ref = TerminalSessionRef.unknown(forTTY: "ttys001")
        XCTAssertEqual(ref.terminalApp, "kitty")
        XCTAssertEqual(ref.tty, "ttys001")
        XCTAssertEqual(ref.kittyWindowId, 0)
    }
}
