import XCTest
@testable import ShellIslandApp

@MainActor
final class SystemStatsMonitorTests: XCTestCase {
    func testRefreshProducesSaneRanges() {
        let monitor = SystemStatsMonitor()
        monitor.refresh()

        XCTAssertGreaterThanOrEqual(monitor.stats.cpuLoadPercent, 0)
        XCTAssertLessThanOrEqual(monitor.stats.cpuLoadPercent, 100)

        XCTAssertGreaterThanOrEqual(monitor.stats.memoryUsedPercent, 0)
        XCTAssertLessThanOrEqual(monitor.stats.memoryUsedPercent, 100)

        XCTAssertGreaterThanOrEqual(monitor.stats.uptimeHours, 0)
    }
}

