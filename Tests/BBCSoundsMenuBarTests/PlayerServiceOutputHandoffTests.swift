import XCTest
@testable import BBCSoundsMenuBar

@MainActor
final class PlayerServiceOutputHandoffTests: XCTestCase {

    func testDefaultOutputTargetIsThisMac() {
        let player = PlayerService()
        XCTAssertEqual(player.outputTarget, .thisMac)
        XCTAssertNil(player.sonosController)
    }

    func testSwitchingOutputTargetWhenIdleSyncsVolume() async throws {
        let mock = MockSonosDevice(roomName: "Lounge", currentVolume: 40)
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_LOUNGE",
            name: "Lounge",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let player = PlayerService()
        try await player.setOutputTarget(.sonos(device))

        XCTAssertEqual(player.outputTarget, .sonos(device))
        XCTAssertNotNil(player.sonosController)
        XCTAssertEqual(player.sonosController?.device.id, device.id)
        XCTAssertEqual(player.volume, 0.4, accuracy: 0.01)
        XCTAssertFalse(player.isPlaying)
    }

    func testDirectPlayToSonosTargetRoutesToSonos() async throws {
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

        let streamURL = URL(string: "https://open.live.bbc.co.uk/radio6.m3u8")!
        let prog = Programme(
            id: "m001live",
            index: 0,
            name: "Gilles Peterson",
            channel: "BBC Radio 6 Music",
            duration: nil,
            description: "Fresh cuts",
            firstBroadcast: nil,
            artworkURL: "https://example.com/art.jpg",
            isLive: true
        )

        player.play(url: streamURL, programme: prog)

        // Allow async Sonos calls to complete
        try await Task.sleep(nanoseconds: 300_000_000)

        let expectedTransportURI = SonosController.sonosTransportURI(for: streamURL).absoluteString
        XCTAssertEqual(mock.receivedURI, expectedTransportURI)
        XCTAssertEqual(mock.transportState, "PLAYING")
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.currentProgramme?.id, "m001live")
        XCTAssertEqual(player.currentStreamURL, streamURL)
    }

    func testHandoffFromMacToSonosPreservesPosition() async throws {
        let mock = MockSonosDevice(roomName: "Bedroom")
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_BEDROOM",
            name: "Bedroom",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let player = PlayerService()
        let streamURL = URL(string: "https://open.live.bbc.co.uk/ondemand.m3u8")!
        let prog = Programme(
            id: "m002vod",
            index: 1,
            name: "Desert Island Discs",
            channel: "BBC Radio 4",
            duration: "00:45:00",
            description: "Castaway talks",
            firstBroadcast: "2026-09-20",
            artworkURL: nil,
            isLive: false
        )

        // 1. Start on Mac
        player.play(url: streamURL, programme: prog)
        // Manually simulate playback progress on Mac
        player.currentTime = 42.0
        XCTAssertTrue(player.isPlaying)

        // 2. Switch to Sonos target
        try await player.setOutputTarget(.sonos(device))

        // Allow handoff async tasks to settle
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(player.outputTarget, .sonos(device))
        let expectedTransportURI = SonosController.sonosTransportURI(for: streamURL, isLive: prog.isLive).absoluteString
        XCTAssertEqual(mock.receivedURI, expectedTransportURI)
        XCTAssertTrue(mock.receivedActions.contains("SetAVTransportURI"))
        XCTAssertTrue(mock.receivedActions.contains("Seek"))
        XCTAssertTrue(mock.receivedActions.contains("Play"))
        XCTAssertEqual(mock.transportState, "PLAYING")
        XCTAssertEqual(player.currentTime, 42.0, accuracy: 0.1)
    }

    func testHandoffFromSonosToMacPreservesPosition() async throws {
        let mock = MockSonosDevice(roomName: "Study", trackRelTime: "00:01:25")
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_STUDY",
            name: "Study",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let player = PlayerService()
        try await player.setOutputTarget(.sonos(device))

        let streamURL = URL(string: "https://open.live.bbc.co.uk/study.m3u8")!
        let prog = Programme(
            id: "m003study",
            index: 0,
            name: "In Our Time",
            channel: "BBC Radio 4",
            duration: "00:45:00",
            description: "History of Science",
            firstBroadcast: nil,
            artworkURL: nil,
            isLive: false
        )

        player.play(url: streamURL, programme: prog)
        try await Task.sleep(nanoseconds: 300_000_000)
        player.currentTime = 85.0

        // 2. Switch back to This Mac
        try await player.setOutputTarget(.thisMac)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(player.outputTarget, .thisMac)
        XCTAssertTrue(mock.receivedActions.contains("Pause") || mock.receivedActions.contains("Stop"))
        XCTAssertEqual(player.currentTime, 85.0, accuracy: 0.5)
        XCTAssertTrue(player.isPlaying)
    }

    func testTransportControlsRouteToSonos() async throws {
        let mock = MockSonosDevice(roomName: "Garden")
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_GARDEN",
            name: "Garden",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let player = PlayerService()
        try await player.setOutputTarget(.sonos(device))

        let streamURL = URL(string: "https://open.live.bbc.co.uk/garden.m3u8")!
        let prog = Programme(
            id: "m004garden",
            index: 0,
            name: "Gardeners Question Time",
            channel: "BBC Radio 4",
            duration: "00:45:00",
            description: "Plants",
            firstBroadcast: nil,
            artworkURL: nil,
            isLive: false
        )

        player.play(url: streamURL, programme: prog)
        try await Task.sleep(nanoseconds: 300_000_000)

        // 1. Pause
        player.pause()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(mock.transportState, "PAUSED_PLAYBACK")
        XCTAssertFalse(player.isPlaying)

        // 2. Resume
        player.resume()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(mock.transportState, "PLAYING")
        XCTAssertTrue(player.isPlaying)

        // 3. Seek
        player.seek(to: 120)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(mock.receivedActions.contains("Seek"))

        // 4. Set Volume
        player.setVolume(0.65)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(mock.currentVolume, 65)

        // 5. Stop
        player.stop()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(mock.transportState, "STOPPED")
        XCTAssertFalse(player.isPlaying)
    }

    func testPlayToSonosWithProxyUsesLANRelayURL() async throws {
        let mock = MockSonosDevice(roomName: "Den")
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_DEN",
            name: "Den",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let player = PlayerService()
        player.deliveryService = SonosStreamDeliveryService(getLANIP: { "192.168.1.150" })
        player.proxyConfig = ProxyConfiguration(host: "proxy.test", port: 8080, user: "", pass: "", skipVerify: false)
        try await player.setOutputTarget(.sonos(device))

        let streamURL = URL(string: "https://open.live.bbc.co.uk/den.m3u8")!
        let prog = Programme(
            id: "m005den",
            index: 0,
            name: "World Service",
            channel: "BBC World Service",
            duration: nil,
            description: "News",
            firstBroadcast: nil,
            artworkURL: nil,
            isLive: true
        )

        player.play(url: streamURL, programme: prog)
        for _ in 0..<20 {
            if mock.receivedURI != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let receivedURI = try XCTUnwrap(mock.receivedURI)
        XCTAssertTrue(receivedURI.hasPrefix("x-rincon-mp3radio://192.168.1.150:"), "Should route via LAN IP relay URL with Sonos stream prefix")
        XCTAssertTrue(receivedURI.contains("/playlist?url=https://open.live.bbc.co.uk/den.m3u8"))
        XCTAssertEqual(mock.transportState, "PLAYING")
    }

    func testHandoffBetweenTwoSonosDevices() async throws {
        let mock1 = MockSonosDevice(roomName: "Room1")
        let port1 = try mock1.start()
        defer { mock1.stop() }

        let mock2 = MockSonosDevice(roomName: "Room2")
        let port2 = try mock2.start()
        defer { mock2.stop() }

        let dev1 = SonosDevice(id: "RINCON_ROOM1", name: "Room 1", ipAddress: "127.0.0.1", port: port1, isCoordinator: true)
        let dev2 = SonosDevice(id: "RINCON_ROOM2", name: "Room 2", ipAddress: "127.0.0.1", port: port2, isCoordinator: true)

        let player = PlayerService()
        try await player.setOutputTarget(.sonos(dev1))

        let streamURL = URL(string: "https://open.live.bbc.co.uk/multiroom.m3u8")!
        let prog = Programme(
            id: "m006multi",
            index: 0,
            name: "Proms",
            channel: "BBC Radio 3",
            duration: "01:30:00",
            description: "Live Classical",
            firstBroadcast: nil,
            artworkURL: nil,
            isLive: false
        )

        player.play(url: streamURL, programme: prog)
        try await Task.sleep(nanoseconds: 300_000_000)
        player.currentTime = 150.0

        // Switch to Room 2
        try await player.setOutputTarget(.sonos(dev2))
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(player.outputTarget, .sonos(dev2))
        XCTAssertEqual(player.sonosController?.device.id, dev2.id)
        XCTAssertTrue(mock1.receivedActions.contains("Pause") || mock1.receivedActions.contains("Stop"))
        let expectedTransportURI = SonosController.sonosTransportURI(for: streamURL, isLive: prog.isLive).absoluteString
        XCTAssertEqual(mock2.receivedURI, expectedTransportURI)
        XCTAssertTrue(mock2.receivedActions.contains("Seek"))
        XCTAssertEqual(mock2.transportState, "PLAYING")
    }

    func testPropertyAssignmentOutputTargetTriggersHandoff() async throws {
        let (mock, device) = try makeMockDevice(roomName: "Balcony")
        defer { mock.stop() }

        let player = PlayerService()
        let streamURL = URL(string: "https://open.live.bbc.co.uk/balcony.m3u8")!
        let prog = Programme(
            id: "m007balcony",
            index: 0,
            name: "Morning Edition",
            channel: "BBC Radio 4",
            duration: "00:30:00",
            description: "News",
            firstBroadcast: nil,
            artworkURL: nil,
            isLive: false
        )

        player.play(url: streamURL, programme: prog)
        player.currentTime = 25.0

        // Assign directly to @Published outputTarget property
        player.outputTarget = .sonos(device)
        try await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(player.outputTarget, .sonos(device))
        let expectedTransportURI2 = SonosController.sonosTransportURI(for: streamURL, isLive: prog.isLive).absoluteString
        XCTAssertEqual(mock.receivedURI, expectedTransportURI2)
        XCTAssertTrue(mock.receivedActions.contains("Seek"))
        XCTAssertEqual(mock.transportState, "PLAYING")
    }

    func testHandoffToFailingSonosResetsLoadingAndSetsPlayerError() async throws {
        let (mock, device) = try makeMockDevice(roomName: "Faulty Room")
        defer { mock.stop() }
        mock.avTransportError = (statusCode: 500, errorCode: 800)

        let player = PlayerService()
        let streamURL = URL(string: "https://open.live.bbc.co.uk/faulty.m3u8")!
        let prog = Programme(
            id: "m008faulty",
            index: 0,
            name: "Faulty Show",
            channel: "BBC Radio 1",
            duration: "00:30:00",
            description: "Faulty stream test",
            firstBroadcast: nil,
            artworkURL: nil,
            isLive: true
        )

        player.play(url: streamURL, programme: prog)

        do {
            try await player.setOutputTarget(.sonos(device))
        } catch {
            // Expected to throw
        }

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertFalse(player.isLoading, "player.isLoading should be false after Sonos failure")
        XCTAssertFalse(player.isPlaying, "player.isPlaying should be false after Sonos failure")
        XCTAssertNotNil(player.playerError, "player.playerError should be set when Sonos rejects the stream")
    }

    func testHandoffToSonosResumesWhenSpeakerRejectsSeekWhileStopped() async throws {
        let (mock, device) = try makeMockDevice(roomName: "Living Room")
        defer { mock.stop() }
        mock.rejectSeekWhenStopped = true

        let player = PlayerService()
        let streamURL = URL(string: "https://open.live.bbc.co.uk/musicmix.m3u8")!
        let prog = Programme(
            id: "m009music",
            index: 0,
            name: "Essential Mix",
            channel: "BBC Radio 1",
            duration: "02:00:00",
            description: "Music mix",
            firstBroadcast: nil,
            artworkURL: nil,
            isLive: false
        )

        player.play(url: streamURL, programme: prog)
        player.currentTime = 55.0
        XCTAssertTrue(player.isPlaying)

        try await player.setOutputTarget(.sonos(device))
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(player.outputTarget, .sonos(device))
        XCTAssertEqual(mock.transportState, "PLAYING")
        XCTAssertEqual(player.currentTime, 55.0, accuracy: 0.1)
        XCTAssertEqual(mock.trackRelTime, "00:00:55")

        let playIndex = mock.receivedActions.firstIndex(of: "Play")
        let seekIndex = mock.receivedActions.firstIndex(of: "Seek")
        XCTAssertNotNil(playIndex)
        XCTAssertNotNil(seekIndex)
        XCTAssertLessThan(playIndex!, seekIndex!, "Sonos Play must be initiated before Seek")
    }

    private func makeMockDevice(
        roomName: String,
        currentVolume: Int = 25,
        trackRelTime: String = "00:00:00"
    ) throws -> (MockSonosDevice, SonosDevice) {
        let mock = MockSonosDevice(roomName: roomName, currentVolume: currentVolume, trackRelTime: trackRelTime)
        let port = try mock.start()
        let id = "RINCON_\(roomName.uppercased().replacingOccurrences(of: " ", with: "_"))"
        let device = SonosDevice(id: id, name: roomName, ipAddress: "127.0.0.1", port: port, isCoordinator: true)
        return (mock, device)
    }
}
