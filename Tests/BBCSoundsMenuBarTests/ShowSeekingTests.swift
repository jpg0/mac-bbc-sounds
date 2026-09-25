import XCTest
import AVFoundation
@testable import BBCSoundsMenuBar

@MainActor
final class ShowSeekingTests: XCTestCase {

    func testEffectiveDurationCalculation() {
        let prog1 = Programme(
            id: "p1", index: 0, name: "Show 1", channel: "Radio 4",
            duration: nil, description: nil, firstBroadcast: nil,
            artworkURL: nil, isLive: false, durationInSeconds: 3600
        )
        XCTAssertEqual(prog1.effectiveDurationInSeconds, 3600)

        // Parse HH:MM:SS
        let prog2 = Programme(
            id: "p2", index: 0, name: "Show 2", channel: "Radio 4",
            duration: "01:30:00", description: nil, firstBroadcast: nil,
            artworkURL: nil, isLive: false, durationInSeconds: 0
        )
        XCTAssertEqual(prog2.effectiveDurationInSeconds, 5400)

        // Parse MM:SS
        let prog3 = Programme(
            id: "p3", index: 0, name: "Show 3", channel: "Radio 4",
            duration: "45:00", description: nil, firstBroadcast: nil,
            artworkURL: nil, isLive: false, durationInSeconds: 0
        )
        XCTAssertEqual(prog3.effectiveDurationInSeconds, 2700)

        // Parse "X mins"
        let prog4 = Programme(
            id: "p4", index: 0, name: "Show 4", channel: "Radio 4",
            duration: "57 mins", description: nil, firstBroadcast: nil,
            artworkURL: nil, isLive: false, durationInSeconds: 0
        )
        XCTAssertEqual(prog4.effectiveDurationInSeconds, 3420)

        // Live programme has 0 effective duration
        let progLive = Programme(
            id: "live1", index: 0, name: "Live Show", channel: "Radio 1",
            duration: "01:00:00", description: nil, firstBroadcast: nil,
            artworkURL: nil, isLive: true, durationInSeconds: 3600
        )
        XCTAssertEqual(progLive.effectiveDurationInSeconds, 0)
    }

    func testSeekToUpdatesCurrentTimeImmediatelyOnThisMac() {
        let player = PlayerService()
        player.duration = 3600
        player.currentTime = 10.0

        player.seek(to: 150.0)

        XCTAssertEqual(player.currentTime, 150.0, accuracy: 0.01, "currentTime must update immediately on seek(to:)")
    }

    func testSeekByClampsCorrectlyAndAccumulatesRapidSkips() {
        let player = PlayerService()
        player.duration = 3600
        player.currentTime = 5.0

        // Clamps backwards to 0, avoiding negative CMTime
        player.seek(by: -15.0)
        XCTAssertEqual(player.currentTime, 0.0, accuracy: 0.01)

        // Rapid forward skips accumulate from updated currentTime
        player.seek(by: 15.0)
        XCTAssertEqual(player.currentTime, 15.0, accuracy: 0.01)

        player.seek(by: 15.0)
        XCTAssertEqual(player.currentTime, 30.0, accuracy: 0.01)

        // Clamps forward to duration
        player.currentTime = 3590.0
        player.seek(by: 20.0)
        XCTAssertEqual(player.currentTime, 3600.0, accuracy: 0.01)
    }

    func testPlayInitializesDurationFromProgramme() {
        let player = PlayerService()
        let prog = Programme(
            id: "m00show", index: 0, name: "Desert Island Discs", channel: "Radio 4",
            duration: "00:45:00", description: nil, firstBroadcast: nil,
            artworkURL: nil, isLive: false, durationInSeconds: 2700
        )
        let streamURL = URL(string: "https://open.live.bbc.co.uk/sample.m3u8")!

        player.play(url: streamURL, programme: prog)

        XCTAssertEqual(player.duration, 2700.0, accuracy: 0.01, "Player duration must be populated from programme metadata")
        player.stop()
    }

    func testPlayWithInitialSeekToSetsCurrentTimeAndQueuesSeek() {
        let player = PlayerService()
        let prog = Programme(
            id: "m00show", index: 0, name: "Desert Island Discs", channel: "Radio 4",
            duration: "00:45:00", description: nil, firstBroadcast: nil,
            artworkURL: nil, isLive: false, durationInSeconds: 2700
        )
        let streamURL = URL(string: "https://open.live.bbc.co.uk/sample.m3u8")!

        player.play(url: streamURL, programme: prog, seekTo: 120.0)

        XCTAssertEqual(player.currentTime, 120.0, accuracy: 0.01, "Initial seekTo should set currentTime immediately")
        player.stop()
    }

    func testSonosPlaybackInitializesDurationAndCurrentTimeForOnDemand() async throws {
        let mock = MockSonosDevice(roomName: "Living Room", trackDuration: "00:00:00")
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_LIVING_ROOM",
            name: "Living Room",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let player = PlayerService()
        try await player.setOutputTarget(.sonos(device))

        let prog = Programme(
            id: "m00vod", index: 0, name: "Composer of the Week", channel: "Radio 3",
            duration: "01:00:00", description: nil, firstBroadcast: nil,
            artworkURL: nil, isLive: false, durationInSeconds: 3600
        )
        let streamURL = URL(string: "http://127.0.0.1:52800/playlist?url=https://aod.bbci.co.uk/stream.m3u8")!

        player.play(url: streamURL, programme: prog, seekTo: 300.0)

        // Wait for async Sonos start to complete
        for _ in 0..<30 {
            if player.duration > 0 && mock.receivedActions.contains("Play") { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(player.duration, 3600.0, accuracy: 0.01, "Sonos on-demand playback must retain programme duration even if Sonos returns 0:00:00")
        XCTAssertEqual(player.currentTime, 300.0, accuracy: 1.0)
        XCTAssertEqual(mock.receivedURI, streamURL.absoluteString, "On-demand streams should use HTTP without x-rincon-mp3radio prefix")
        XCTAssertTrue(mock.receivedActions.contains("Seek"))
        player.stop()
    }

    func testSonosSeekingSendsAVTransportSeekAndUpdatesCurrentTime() async throws {
        let mock = MockSonosDevice(roomName: "Kitchen")
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_KITCHEN",
            name: "Kitchen",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let player = PlayerService()
        try await player.setOutputTarget(.sonos(device))

        let prog = Programme(
            id: "m00show", index: 0, name: "Book at Bedtime", channel: "Radio 4",
            duration: "00:15:00", description: nil, firstBroadcast: nil,
            artworkURL: nil, isLive: false, durationInSeconds: 900
        )
        let streamURL = URL(string: "http://127.0.0.1:52800/playlist?url=https://aod.bbci.co.uk/bedtime.m3u8")!

        player.play(url: streamURL, programme: prog)

        for _ in 0..<30 {
            if mock.transportState == "PLAYING" { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        // Seek to 180s (3 minutes)
        player.seek(to: 180.0)
        XCTAssertEqual(player.currentTime, 180.0, accuracy: 0.01, "currentTime must update immediately on seek")

        for _ in 0..<30 {
            if mock.receivedActions.contains("Seek") { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(mock.receivedActions.contains("Seek"), "AVTransport Seek action should be dispatched to Sonos")
        let seekBody = mock.receivedActionBodies.first(where: { $0.action == "Seek" })?.body ?? ""
        XCTAssertTrue(seekBody.contains("<Target>00:03:00</Target>"), "Seek target should be formatted as HH:MM:SS")
        player.stop()
    }
}
