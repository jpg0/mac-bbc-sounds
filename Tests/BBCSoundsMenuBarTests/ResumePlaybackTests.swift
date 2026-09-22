import XCTest
@testable import BBCSoundsMenuBar

final class ResumePlaybackTests: XCTestCase {
    
    func testProgrammeExpiredOrNotFoundDescription() {
        let error = BBCSoundsError.programmeExpiredOrNotFound
        XCTAssertEqual(
            error.errorDescription,
            "This programme is no longer available on BBC Sounds (expired or not found)."
        )
    }
    
    func testResolveStreamWithKnownVPIDUsesLiveStationPoolDirectly() async throws {
        let service = BBCSoundsService()
        
        // "bbc_radio_one" is in BBCSoundsService.liveStationPools
        // Passing an arbitrary PID with knownVPID = "bbc_radio_one" should bypass fetchVPID
        let (url, resolvedVPID) = try await service.resolveStream(pid: "some_random_pid", knownVPID: "bbc_radio_one")
        
        XCTAssertEqual(resolvedVPID, "bbc_radio_one")
        XCTAssertTrue(url.absoluteString.contains("bbc_radio_one"))
    }
    
    @MainActor
    func testDismissResumeClearsStateAndUserDefaults() {
        let dummyProgramme = Programme(
            id: "m001v5g3",
            index: 0,
            name: "Test Episode",
            channel: "Radio 4",
            duration: "00:30:00",
            description: "Test description",
            firstBroadcast: nil,
            artworkURL: nil,
            isLive: false,
            resolvedPID: "m001v5g3"
        )
        let session = PlaybackSession(programme: dummyProgramme, time: 120, duration: 1800, date: Date())
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.app.set(data, forKey: "LastPlaybackSession")
        }
        
        let viewModel = AppViewModel()
        viewModel.resumeSession = session
        
        XCTAssertNotNil(viewModel.resumeSession)
        XCTAssertNotNil(UserDefaults.app.data(forKey: "LastPlaybackSession"))
        
        viewModel.dismissResume()
        
        XCTAssertNil(viewModel.resumeSession)
        XCTAssertNil(UserDefaults.app.data(forKey: "LastPlaybackSession"))
    }
    
    func testProgrammeModelPreservesResolvedPID() {
        var programme = Programme(
            id: "b006q2x0",
            index: 0,
            name: "In Our Time",
            channel: "BBC Radio 4",
            duration: "00:45:00",
            description: nil,
            firstBroadcast: nil,
            artworkURL: nil,
            isLive: false
        )
        programme.resolvedPID = "m002q4mr"
        
        let session = PlaybackSession(programme: programme, time: 500, duration: 2700, date: Date())
        XCTAssertEqual(session.programme.id, "b006q2x0")
        XCTAssertEqual(session.programme.resolvedPID, "m002q4mr")
    }
}
