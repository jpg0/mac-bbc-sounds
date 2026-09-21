import XCTest
@testable import BBCSoundsMenuBar

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
            albumArtURI: "https://ichef.bbci.co.uk/images/ic/400x400/p0123.jpg"
        )

        try await controller.setAVTransportURI(url: streamURL, metadata: metadata)

        XCTAssertEqual(mock.receivedURI, streamURL.absoluteString)
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

        XCTAssertEqual(mock.receivedURI, streamURL.absoluteString)
        let receivedDIDL = try XCTUnwrap(mock.receivedDIDLLite)
        XCTAssertTrue(receivedDIDL.contains("<dc:title>Late Junction</dc:title>"))
        XCTAssertTrue(receivedDIDL.contains("<dc:creator>BBC Radio 3</dc:creator>"))
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
