import XCTest
@testable import BBCSoundsMenuBar

@MainActor
final class SonosControllerTests: XCTestCase {

    // MARK: - Seam 1: SonosMetadata & DIDL-Lite Generation

    func testDIDLLiteMetadataXMLGeneration() {
        let metadata = SonosMetadata(
            title: "Craig Charles House Party & Soul",
            creator: "BBC Radio 6 Music",
            albumArtURI: "https://ichef.bbci.co.uk/images/ic/400x400/p0123456.jpg"
        )

        let xml = metadata.didlLiteXML()

        XCTAssertTrue(xml.contains("<DIDL-Lite"))
        XCTAssertTrue(xml.contains("xmlns:dc=\"http://purl.org/dc/elements/1.1/\""))
        XCTAssertTrue(xml.contains("xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\""))
        XCTAssertTrue(xml.contains("<dc:title>Craig Charles House Party &amp; Soul</dc:title>"))
        XCTAssertTrue(xml.contains("<dc:creator>BBC Radio 6 Music</dc:creator>"))
        XCTAssertTrue(xml.contains("<upnp:albumArtURI>https://ichef.bbci.co.uk/images/ic/400x400/p0123456.jpg</upnp:albumArtURI>"))
        XCTAssertTrue(xml.contains("<upnp:class>object.item.audioItem.musicTrack</upnp:class>"))
    }

    func testDIDLLiteMetadataSpecialCharactersEscaping() {
        let metadata = SonosMetadata(
            title: "Rock & Roll <Live> \"Summer '26\"",
            creator: "BBC & Partners",
            albumArtURI: "https://example.com/art?size=large&format=png"
        )

        let xml = metadata.didlLiteXML()

        XCTAssertTrue(xml.contains("<dc:title>Rock &amp; Roll &lt;Live&gt; &quot;Summer &apos;26&quot;</dc:title>"))
        XCTAssertTrue(xml.contains("<dc:creator>BBC &amp; Partners</dc:creator>"))
        XCTAssertTrue(xml.contains("<upnp:albumArtURI>https://example.com/art?size=large&amp;format=png</upnp:albumArtURI>"))
    }

    func testDIDLLiteMetadataFromProgramme() {
        let prog = Programme(
            id: "m001v5g3",
            index: 0,
            name: "Desert Island Discs",
            channel: "BBC Radio 4",
            duration: "00:45:00",
            description: "A conversation with music",
            firstBroadcast: "2026-09-20",
            artworkURL: "https://ichef.bbci.co.uk/images/ic/{recipe}/p0abcdef.jpg",
            isLive: false
        )

        let metadata = SonosMetadata(programme: prog)

        XCTAssertEqual(metadata.title, "Desert Island Discs")
        XCTAssertEqual(metadata.creator, "BBC Radio 4")
        XCTAssertEqual(metadata.albumArtURI, "https://ichef.bbci.co.uk/images/ic/400x400/p0abcdef.jpg")

        let xml = metadata.didlLiteXML()
        XCTAssertTrue(xml.contains("<dc:title>Desert Island Discs</dc:title>"))
        XCTAssertTrue(xml.contains("<dc:creator>BBC Radio 4</dc:creator>"))
        XCTAssertTrue(xml.contains("<upnp:albumArtURI>https://ichef.bbci.co.uk/images/ic/400x400/p0abcdef.jpg</upnp:albumArtURI>"))
    }

    func testDIDLLiteMetadataOptionalOmission() {
        let metadata = SonosMetadata(title: "Simple Show")
        let xml = metadata.didlLiteXML()

        XCTAssertTrue(xml.contains("<dc:title>Simple Show</dc:title>"))
        XCTAssertFalse(xml.contains("<dc:creator>"))
        XCTAssertFalse(xml.contains("<upnp:albumArtURI>"))
    }

    // MARK: - Seam 2: SonosController Transport Control on MockSonosDevice

    func testSetAVTransportURIWithMetadataOnMockDevice() async throws {
        let mock = MockSonosDevice(roomName: "Living Room")
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_000E5800000001400",
            name: "Living Room",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let controller = SonosController(device: device)
        let streamURL = URL(string: "https://as-hls-uk-live.akamaized.net/live/uk/bbc_radio_one/bbc_radio_one.isml/master.m3u8?token=test1234&param=value")!
        let metadata = SonosMetadata(
            title: "Breakfast Show",
            creator: "BBC Radio 1",
            albumArtURI: "https://ichef.bbci.co.uk/images/ic/400x400/p0123.jpg",
            isLive: true
        )

        try await controller.setAVTransportURI(url: streamURL, metadata: metadata)

        let expectedTransportURI = SonosController.sonosTransportURI(for: streamURL, isLive: true).absoluteString
        XCTAssertEqual(mock.receivedURI, expectedTransportURI)
        let receivedDIDL = try XCTUnwrap(mock.receivedDIDLLite)
        XCTAssertTrue(receivedDIDL.contains("<dc:title>Breakfast Show</dc:title>"))
        XCTAssertTrue(receivedDIDL.contains("<dc:creator>BBC Radio 1</dc:creator>"))
        XCTAssertEqual(mock.receivedActions, ["SetAVTransportURI"])

        let bodies = mock.receivedActionBodies
        XCTAssertEqual(bodies.count, 1)
        XCTAssertEqual(bodies[0].action, "SetAVTransportURI")
        XCTAssertTrue(bodies[0].body.contains("<u:SetAVTransportURI xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"))
        XCTAssertTrue(bodies[0].body.contains("<InstanceID>0</InstanceID>"))
        XCTAssertTrue(bodies[0].body.contains("<CurrentURI>"))
        XCTAssertTrue(bodies[0].body.contains("<CurrentURIMetaData>"))
    }

    func testSetAVTransportURIWithProgrammeConvenience() async throws {
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

        let controller = SonosController(device: device)
        let streamURL = URL(string: "http://127.0.0.1:8080/stream.m3u8")!
        let prog = Programme(
            id: "m002test",
            index: 1,
            name: "Late Junction",
            channel: "BBC Radio 3",
            duration: "02:00:00",
            description: nil,
            firstBroadcast: nil,
            artworkURL: "https://example.com/art.jpg",
            isLive: true
        )

        try await controller.setAVTransportURI(url: streamURL, programme: prog)

        let expectedTransportURI = SonosController.sonosTransportURI(for: streamURL).absoluteString
        XCTAssertEqual(mock.receivedURI, expectedTransportURI)
        let receivedDIDL = try XCTUnwrap(mock.receivedDIDLLite)
        XCTAssertTrue(receivedDIDL.contains("<dc:title>Late Junction</dc:title>"))
        XCTAssertTrue(receivedDIDL.contains("<dc:creator>BBC Radio 3</dc:creator>"))
        XCTAssertTrue(receivedDIDL.contains("<upnp:class>object.item.audioItem.audioBroadcast</upnp:class>"))
    }

    func testSetAVTransportURIForOnDemandProgrammeRetainsHTTPAndIncludesProtocolInfo() async throws {
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

        let controller = SonosController(device: device)
        let streamURL = URL(string: "http://127.0.0.1:52800/playlist?url=https://aod.bbci.co.uk/show.m3u8")!
        let prog = Programme(
            id: "m001ondemand",
            index: 0,
            name: "Archive on 4",
            channel: "BBC Radio 4",
            duration: "01:00:00",
            description: "Documentary",
            firstBroadcast: nil,
            artworkURL: nil,
            isLive: false
        )

        try await controller.setAVTransportURI(url: streamURL, programme: prog)

        XCTAssertEqual(mock.receivedURI, streamURL.absoluteString, "On-demand URI should be standard HTTP, not x-rincon-mp3radio")
        let receivedDIDL = try XCTUnwrap(mock.receivedDIDLLite)
        XCTAssertTrue(receivedDIDL.contains("protocolInfo=\"http-get:*:application/vnd.apple.mpegurl:*\""))
        XCTAssertTrue(receivedDIDL.contains("<upnp:class>object.item.audioItem.musicTrack</upnp:class>"))
    }

    func testPlaybackCommandsPlayPauseStopOnMockDevice() async throws {
        let mock = MockSonosDevice(roomName: "Office")
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_OFFICE",
            name: "Office",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let controller = SonosController(device: device)

        // Initial state
        XCTAssertEqual(mock.transportState, "STOPPED")

        // 1. Play
        try await controller.play()
        XCTAssertEqual(mock.transportState, "PLAYING")

        // 2. Pause
        try await controller.pause()
        XCTAssertEqual(mock.transportState, "PAUSED_PLAYBACK")

        // 3. Stop
        try await controller.stop()
        XCTAssertEqual(mock.transportState, "STOPPED")

        XCTAssertEqual(mock.receivedActions, ["Play", "Pause", "Stop"])

        // Validate SOAP envelope bodies delivered to MockSonosDevice
        let bodies = mock.receivedActionBodies
        XCTAssertEqual(bodies.count, 3)

        // Play envelope verification
        XCTAssertEqual(bodies[0].action, "Play")
        XCTAssertTrue(bodies[0].body.contains("<u:Play xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"))
        XCTAssertTrue(bodies[0].body.contains("<InstanceID>0</InstanceID>"))
        XCTAssertTrue(bodies[0].body.contains("<Speed>1</Speed>"))

        // Pause envelope verification
        XCTAssertEqual(bodies[1].action, "Pause")
        XCTAssertTrue(bodies[1].body.contains("<u:Pause xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"))
        XCTAssertTrue(bodies[1].body.contains("<InstanceID>0</InstanceID>"))

        // Stop envelope verification
        XCTAssertEqual(bodies[2].action, "Stop")
        XCTAssertTrue(bodies[2].body.contains("<u:Stop xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"))
        XCTAssertTrue(bodies[2].body.contains("<InstanceID>0</InstanceID>"))
    }

    func testSonosControllerUsesCoordinatorEndpointWhenDeviceIsMember() async throws {
        // Coordinator running on portCoord
        let coordMock = MockSonosDevice(roomName: "Living Room", udn: "RINCON_COORD")
        let coordPort = try coordMock.start()
        defer { coordMock.stop() }

        // Member device model pointing to coordMock's IP/port
        let memberDevice = SonosDevice(
            id: "RINCON_MEMBER",
            name: "Living Room 2",
            ipAddress: "192.168.1.99",
            port: 1400,
            isCoordinator: false,
            groupId: "RINCON_COORD:1",
            groupName: "Living Room",
            coordinatorUUID: "RINCON_COORD",
            coordinatorIP: "127.0.0.1",
            coordinatorPort: coordPort
        )

        let controller = SonosController(device: memberDevice)
        try await controller.play()

        // Command should have landed on the coordinator!
        XCTAssertEqual(coordMock.transportState, "PLAYING")
        XCTAssertEqual(coordMock.receivedActions, ["Play"])
    }

    func testSonosControllerErrorOnUnreachableHost() async throws {
        // Choose a port that is guaranteed not listening (e.g. 1 on localhost)
        let unreachableDevice = SonosDevice(
            id: "RINCON_DEAD",
            name: "Dead Speaker",
            ipAddress: "127.0.0.1",
            port: 1,
            isCoordinator: true
        )

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 1
        let shortSession = URLSession(configuration: sessionConfig)

        let controller = SonosController(device: unreachableDevice, session: shortSession)

        do {
            try await controller.play()
            XCTFail("Expected controller.play() to throw an error on unreachable host")
        } catch {
            // Expected
            XCTAssertNotNil(error)
        }
    }

    func testSonosControllerSOAPFaultHandling() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockFaultURLProtocol.self]
        let session = URLSession(configuration: config)

        let device = SonosDevice(
            id: "RINCON_FAULT",
            name: "Faulty Speaker",
            ipAddress: "127.0.0.1",
            port: 1400,
            isCoordinator: true
        )

        let controller = SonosController(device: device, session: session)

        do {
            try await controller.play()
            XCTFail("Expected SOAP fault to throw SonosError.soapFault")
        } catch let SonosError.soapFault(code, detail) {
            XCTAssertEqual(code, 500)
            XCTAssertTrue(detail.contains("UPnPError"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSonosTransportURIConversion() {
        let httpURL = URL(string: "http://192.168.1.50:52800/playlist?url=https%3A%2F%2Fexample.com%2Fstream.m3u8")!
        let sonosHTTP = SonosController.sonosTransportURI(for: httpURL)
        XCTAssertEqual(sonosHTTP.absoluteString, "x-rincon-mp3radio://192.168.1.50:52800/playlist?url=https%3A%2F%2Fexample.com%2Fstream.m3u8")

        let httpsURL = URL(string: "https://as-hls-ww-live.akamaized.net/live/bbc_6music.m3u8")!
        let sonosHTTPS = SonosController.sonosTransportURI(for: httpsURL)
        XCTAssertEqual(sonosHTTPS.absoluteString, "x-rincon-mp3radio://as-hls-ww-live.akamaized.net/live/bbc_6music.m3u8")

        let alreadyPrefixed = URL(string: "x-rincon-mp3radio://some.host/stream.mp3")!
        XCTAssertEqual(SonosController.sonosTransportURI(for: alreadyPrefixed), alreadyPrefixed)

        let hlsPrefixed = URL(string: "hls-radio://some.host/stream.m3u8")!
        XCTAssertEqual(SonosController.sonosTransportURI(for: hlsPrefixed), hlsPrefixed)

        // On-demand streams must not be converted to x-rincon-mp3radio
        let onDemandHTTP = SonosController.sonosTransportURI(for: httpURL, isLive: false)
        XCTAssertEqual(onDemandHTTP, httpURL)

        let onDemandHTTPS = SonosController.sonosTransportURI(for: httpsURL, isLive: false)
        XCTAssertEqual(onDemandHTTPS, httpsURL)

        let onDemandStripped = SonosController.sonosTransportURI(for: URL(string: "x-rincon-mp3radio://192.168.1.50/show.m3u8")!, isLive: false)
        XCTAssertEqual(onDemandStripped.absoluteString, "http://192.168.1.50/show.m3u8")
    }

    func testSonosError714Description() {
        let fault714 = SonosError.soapFault(statusCode: 500, detail: "<UPnPError><errorCode>714</errorCode></UPnPError>")
        XCTAssertTrue(fault714.errorDescription?.contains("illegal MIME-type") == true)
    }

    // MARK: - Seam 3: XML Parsers for RenderingControl & AVTransport

    func testSonosVolumeParserSuccess() throws {
        let xml = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <CurrentVolume>35</CurrentVolume>
            </u:GetVolumeResponse>
          </s:Body>
        </s:Envelope>
        """
        let volume = try SonosVolumeParser.parse(xmlData: Data(xml.utf8))
        XCTAssertEqual(volume, 35)
    }

    func testSonosTransportInfoParserStates() throws {
        let xmlPlaying = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <CurrentTransportState>PLAYING</CurrentTransportState>
              <CurrentTransportStatus>OK</CurrentTransportStatus>
              <CurrentSpeed>1</CurrentSpeed>
            </u:GetTransportInfoResponse>
          </s:Body>
        </s:Envelope>
        """
        let playingInfo = try SonosTransportInfoParser.parse(xmlData: Data(xmlPlaying.utf8))
        XCTAssertEqual(playingInfo.state, .playing)
        XCTAssertEqual(playingInfo.status, "OK")
        XCTAssertEqual(playingInfo.speed, "1")

        let xmlPaused = """
        <s:Envelope><s:Body><u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <CurrentTransportState>PAUSED_PLAYBACK</CurrentTransportState>
        </u:GetTransportInfoResponse></s:Body></s:Envelope>
        """
        let pausedInfo = try SonosTransportInfoParser.parse(xmlData: Data(xmlPaused.utf8))
        XCTAssertEqual(pausedInfo.state, .paused)

        let xmlStopped = """
        <s:Envelope><s:Body><u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <CurrentTransportState>STOPPED</CurrentTransportState>
        </u:GetTransportInfoResponse></s:Body></s:Envelope>
        """
        let stoppedInfo = try SonosTransportInfoParser.parse(xmlData: Data(xmlStopped.utf8))
        XCTAssertEqual(stoppedInfo.state, .stopped)
    }

    func testSonosPositionInfoParserValuesAndTimeIntervalCalculation() throws {
        let xml = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <Track>1</Track>
              <TrackDuration>01:30:15</TrackDuration>
              <TrackMetaData></TrackMetaData>
              <TrackURI>http://example.com/audio.m3u8</TrackURI>
              <RelTime>00:15:30</RelTime>
              <AbsTime>00:15:30</AbsTime>
              <RelCount>2147483647</RelCount>
              <AbsCount>2147483647</AbsCount>
            </u:GetPositionInfoResponse>
          </s:Body>
        </s:Envelope>
        """
        let position = try SonosPositionInfoParser.parse(xmlData: Data(xml.utf8))
        XCTAssertEqual(position.rawTrackDuration, "01:30:15")
        XCTAssertEqual(position.rawRelTime, "00:15:30")
        XCTAssertEqual(position.trackURI, "http://example.com/audio.m3u8")
        XCTAssertEqual(position.trackDuration, 5415.0) // 1h 30m 15s
        XCTAssertEqual(position.trackRelTime, 930.0) // 15m 30s
    }

    func testSonosPositionInfoTimeIntervalFormattingAndParsingEdgeCases() {
        XCTAssertEqual(SonosPositionInfo.parseTimeInterval("00:00:00"), 0)
        XCTAssertEqual(SonosPositionInfo.parseTimeInterval("NOT_IMPLEMENTED"), 0)
        XCTAssertEqual(SonosPositionInfo.parseTimeInterval(""), 0)
        XCTAssertEqual(SonosPositionInfo.parseTimeInterval("00:01:30.500"), 90.5)

        XCTAssertEqual(SonosPositionInfo.formatTimeInterval(0), "00:00:00")
        XCTAssertEqual(SonosPositionInfo.formatTimeInterval(90), "00:01:30")
        XCTAssertEqual(SonosPositionInfo.formatTimeInterval(3665), "01:01:05")
    }

    // MARK: - Seam 4: Volume & Position Controls against MockSonosDevice

    @MainActor
    func testSonosControllerVolumeControlOnMockDevice() async throws {
        let mock = MockSonosDevice(roomName: "Dining Room", currentVolume: 20)
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_DINING",
            name: "Dining Room",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let controller = SonosController(device: device)

        // 1. Initial getVolume
        let initialVol = try await controller.getVolume()
        XCTAssertEqual(initialVol, 20)
        XCTAssertEqual(controller.volume, 20)

        // 2. setVolume to 65
        try await controller.setVolume(65)
        XCTAssertEqual(mock.currentVolume, 65)
        XCTAssertEqual(controller.volume, 65)

        // 3. Confirm getVolume returns updated value
        let fetchedVol = try await controller.getVolume()
        XCTAssertEqual(fetchedVol, 65)
        XCTAssertTrue(mock.receivedActions.contains("SetVolume"))
        XCTAssertTrue(mock.receivedActions.contains("GetVolume"))
    }

    @MainActor
    func testSonosControllerVolumeClamping() async throws {
        let mock = MockSonosDevice(roomName: "Den", currentVolume: 10)
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_DEN",
            name: "Den",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let controller = SonosController(device: device)

        // Clamp negative volume to 0
        try await controller.setVolume(-15)
        XCTAssertEqual(mock.currentVolume, 0)
        XCTAssertEqual(controller.volume, 0)

        // Clamp over 100 to 100
        try await controller.setVolume(150)
        XCTAssertEqual(mock.currentVolume, 100)
        XCTAssertEqual(controller.volume, 100)
    }

    @MainActor
    func testSonosControllerTransportInfoAndPositionOnMockDevice() async throws {
        let mock = MockSonosDevice(
            roomName: "Living Room",
            transportState: "PAUSED_PLAYBACK",
            trackDuration: "00:45:00",
            trackRelTime: "00:10:00"
        )
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_LIVING",
            name: "Living Room",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let controller = SonosController(device: device)

        // Transport Info
        let transport = try await controller.getTransportInfo()
        XCTAssertEqual(transport.state, .paused)
        XCTAssertEqual(controller.transportState, .paused)
        XCTAssertFalse(controller.isPlaying)

        // Position Info
        let position = try await controller.getPositionInfo()
        XCTAssertEqual(position.rawTrackDuration, "00:45:00")
        XCTAssertEqual(position.rawRelTime, "00:10:00")
        XCTAssertEqual(position.trackDuration, 2700.0)
        XCTAssertEqual(position.trackRelTime, 600.0)
        XCTAssertEqual(controller.duration, 2700.0)
        XCTAssertEqual(controller.currentTime, 600.0)
    }

    @MainActor
    func testSonosControllerSeekOnMockDevice() async throws {
        let mock = MockSonosDevice(
            roomName: "Kitchen",
            trackDuration: "01:00:00",
            trackRelTime: "00:00:00"
        )
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_KITCHEN",
            name: "Kitchen",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let controller = SonosController(device: device)

        // Seek to 12 minutes (720 seconds)
        try await controller.seek(to: 720)
        XCTAssertEqual(controller.currentTime, 720)
        XCTAssertEqual(mock.trackRelTime, "00:12:00")

        let seekBodies = mock.receivedActionBodies.filter { $0.action == "Seek" }
        XCTAssertEqual(seekBodies.count, 1)
        XCTAssertTrue(seekBodies[0].body.contains("<Unit>REL_TIME</Unit>"))
        XCTAssertTrue(seekBodies[0].body.contains("<Target>00:12:00</Target>"))
    }

    @MainActor
    func testSonosControllerBackgroundPollingPublishesUpdates() async throws {
        let mock = MockSonosDevice(
            roomName: "Balcony",
            transportState: "STOPPED",
            currentVolume: 10,
            trackDuration: "00:30:00",
            trackRelTime: "00:01:00"
        )
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_BALCONY",
            name: "Balcony",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let controller = SonosController(device: device)
        XCTAssertFalse(controller.isPolling)

        // Start fast polling interval for test
        controller.startPolling(interval: 0.05)
        XCTAssertTrue(controller.isPolling)

        // Allow initial poll cycle to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        XCTAssertEqual(controller.volume, 10)
        XCTAssertEqual(controller.transportState, .stopped)
        XCTAssertEqual(controller.currentTime, 60.0)

        // Simulate changes from another controller / physical speaker buttons
        mock.currentVolume = 50
        mock.transportState = "PLAYING"
        mock.trackRelTime = "00:05:00"

        // Wait for next polling cycle
        try await Task.sleep(nanoseconds: 120_000_000) // 120ms
        XCTAssertEqual(controller.volume, 50)
        XCTAssertEqual(controller.transportState, .playing)
        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(controller.currentTime, 300.0)

        // Stop polling
        controller.stopPolling()
        XCTAssertFalse(controller.isPolling)
    }
}

// MARK: - Mock Fault URLProtocol

private final class MockFaultURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        let faultXML = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <s:Fault>
              <faultcode>s:Client</faultcode>
              <faultstring>UPnPError</faultstring>
              <detail>
                <UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
                  <errorCode>701</errorCode>
                  <errorDescription>Transition not available</errorDescription>
                </UPnPError>
              </detail>
            </s:Fault>
          </s:Body>
        </s:Envelope>
        """
        let response = HTTPURLResponse(
            url: url,
            statusCode: 500,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/xml; charset=\"utf-8\""]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(faultXML.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
