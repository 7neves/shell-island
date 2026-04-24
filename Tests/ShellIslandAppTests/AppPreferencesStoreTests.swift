import XCTest
@testable import ShellIslandApp
@testable import ShellIslandCore

final class AppPreferencesStoreTests: XCTestCase {
    func testLoadReturnsDefaultsWhenEmpty() {
        let defaults = UserDefaults(suiteName: "AppPreferencesStoreTests.empty")!
        defaults.removePersistentDomain(forName: "AppPreferencesStoreTests.empty")

        let store = AppPreferencesStore(defaults: defaults)
        let prefs = store.load()

        XCTAssertFalse(prefs.launchAtLogin)
        XCTAssertEqual(prefs.pollIntervalSeconds, 1.0)
        XCTAssertTrue(prefs.keepCompletedUntilManualClear)
    }

    func testSaveThenLoadRoundTrips() {
        let defaults = UserDefaults(suiteName: "AppPreferencesStoreTests.roundtrip")!
        defaults.removePersistentDomain(forName: "AppPreferencesStoreTests.roundtrip")

        let store = AppPreferencesStore(defaults: defaults)
        var prefs = AppPreferences()
        prefs.launchAtLogin = true
        prefs.pollIntervalSeconds = 2.5

        store.save(prefs)
        let loaded = store.load()
        XCTAssertEqual(loaded.launchAtLogin, prefs.launchAtLogin)
        XCTAssertEqual(loaded.pollIntervalSeconds, prefs.pollIntervalSeconds)
        XCTAssertEqual(loaded.keepCompletedUntilManualClear, prefs.keepCompletedUntilManualClear)
    }

    func testLoadFallsBackWhenCorruptedData() {
        let suite = "AppPreferencesStoreTests.corrupt"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        defaults.set(Data([0x00, 0x01, 0x02]), forKey: "shellisland.app-preferences")

        let store = AppPreferencesStore(defaults: defaults)
        let prefs = store.load()
        XCTAssertFalse(prefs.launchAtLogin)
        XCTAssertEqual(prefs.pollIntervalSeconds, 1.0)
        XCTAssertTrue(prefs.keepCompletedUntilManualClear)
    }
}

