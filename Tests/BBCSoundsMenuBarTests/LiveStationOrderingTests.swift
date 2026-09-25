import XCTest
@testable import BBCSoundsMenuBar

final class LiveStationOrderingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.app.removeObject(forKey: "LiveStationUsageCounts")
        UserDefaults.app.removeObject(forKey: "LiveStationLastPlayed")
    }

    override func tearDown() {
        UserDefaults.app.removeObject(forKey: "LiveStationUsageCounts")
        UserDefaults.app.removeObject(forKey: "LiveStationLastPlayed")
        super.tearDown()
    }

    func testDefaultLiveStationsOrderedByUsageNotAlphabetical() {
        let defaultStations = LiveStation.defaultStations
        let ids = defaultStations.map(\.id)

        // Verifies the default order follows national audience reach / RAJAR popularity
        // 1. Radio 2 (~13.3M listeners)
        // 2. Radio 4 (~9.2M listeners)
        // 3. Radio 1 (~7.3M listeners)
        // 4. 5 Live (~5.2M listeners)
        // 5. 6 Music (~2.5M listeners)
        // 6. World Service (~1.2M listeners)
        // 7. 1Xtra (~0.7M listeners)
        XCTAssertEqual(ids, [
            "bbc_radio_two",
            "bbc_radio_fourfm",
            "bbc_radio_one",
            "bbc_radio_five_live",
            "bbc_6music",
            "bbc_world_service",
            "bbc_1xtra"
        ])

        // Verify it is NOT alphabetical
        let alphabetical = ids.sorted()
        XCTAssertNotEqual(ids, alphabetical, "Live stations should be ordered by usage, not alphabetical")
    }

    @MainActor
    func testSortLiveStationsWithNoUsageRetainsDefaultUsageOrder() {
        let viewModel = AppViewModel()
        let sorted = viewModel.sortLiveStations(LiveStation.defaultStations)

        XCTAssertEqual(sorted.map(\.id), [
            "bbc_radio_two",
            "bbc_radio_fourfm",
            "bbc_radio_one",
            "bbc_radio_five_live",
            "bbc_6music",
            "bbc_world_service",
            "bbc_1xtra"
        ])
    }

    @MainActor
    func testSortLiveStationsPrioritizesMostPlayedStation() {
        let viewModel = AppViewModel()

        // Simulate playing 6 Music 3 times and Radio 4 once
        viewModel.recordStationPlayback(stationID: "bbc_6music")
        viewModel.recordStationPlayback(stationID: "bbc_6music")
        viewModel.recordStationPlayback(stationID: "bbc_6music")
        viewModel.recordStationPlayback(stationID: "bbc_radio_fourfm")

        let sorted = viewModel.sortLiveStations(LiveStation.defaultStations)
        let sortedIDs = sorted.map(\.id)

        // 6 Music should bubble to #1, Radio 4 to #2, followed by unplayed stations in default order
        XCTAssertEqual(sortedIDs[0], "bbc_6music")
        XCTAssertEqual(sortedIDs[1], "bbc_radio_fourfm")
        XCTAssertEqual(sortedIDs[2], "bbc_radio_two")
        XCTAssertEqual(sortedIDs[3], "bbc_radio_one")
        XCTAssertEqual(sortedIDs[4], "bbc_radio_five_live")
        XCTAssertEqual(sortedIDs[5], "bbc_world_service")
        XCTAssertEqual(sortedIDs[6], "bbc_1xtra")
    }

    @MainActor
    func testSortLiveStationsTieBreakByMostRecent() {
        let viewModel = AppViewModel()

        // Both played once, but 1Xtra played more recently
        viewModel.recordStationPlayback(stationID: "bbc_radio_two")
        // Sleep slightly to guarantee different timestamp
        Thread.sleep(forTimeInterval: 0.05)
        viewModel.recordStationPlayback(stationID: "bbc_1xtra")

        let sorted = viewModel.sortLiveStations(LiveStation.defaultStations)
        let sortedIDs = sorted.map(\.id)

        // 1Xtra should come before Radio 2 due to recency tie-break
        XCTAssertEqual(sortedIDs[0], "bbc_1xtra")
        XCTAssertEqual(sortedIDs[1], "bbc_radio_two")
    }

    @MainActor
    func testRecordStationPlaybackPersistsInUserDefaults() {
        let viewModel = AppViewModel()
        viewModel.recordStationPlayback(stationID: "bbc_radio_five_live")

        let savedCounts = UserDefaults.app.dictionary(forKey: "LiveStationUsageCounts") as? [String: Int]
        XCTAssertEqual(savedCounts?["bbc_radio_five_live"], 1)

        let savedTimestamps = UserDefaults.app.dictionary(forKey: "LiveStationLastPlayed") as? [String: Double]
        XCTAssertNotNil(savedTimestamps?["bbc_radio_five_live"])

        // Creating a new viewModel should restore persisted usage
        let newViewModel = AppViewModel()
        XCTAssertEqual(newViewModel.stationUsageCounts["bbc_radio_five_live"], 1)
        XCTAssertNotNil(newViewModel.stationLastPlayed["bbc_radio_five_live"])
    }
}
