import XCTest
@testable import BBCSoundsMenuBar

final class SSDPDiscoveryTests: XCTestCase {

    func testSSDPServiceParsing() {
        let rawResponse = """
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age = 1800\r
        LOCATION: http://192.168.1.100:1400/xml/device_description.xml\r
        SERVER: Linux UPnP/1.0 Sonos/79.1-53290 (ZPS3)\r
        ST: urn:schemas-upnp-org:device:ZonePlayer:1\r
        USN: uuid:RINCON_000E5800000001400::urn:schemas-upnp-org:device:ZonePlayer:1\r
        X-CUSTOM-HEADER: test-value\r
        \r
        """

        let service = SSDPService(host: "192.168.1.100", response: rawResponse)

        XCTAssertEqual(service.host, "192.168.1.100")
        XCTAssertEqual(service.location, "http://192.168.1.100:1400/xml/device_description.xml")
        XCTAssertEqual(service.server, "Linux UPnP/1.0 Sonos/79.1-53290 (ZPS3)")
        XCTAssertEqual(service.searchTarget, "urn:schemas-upnp-org:device:ZonePlayer:1")
        XCTAssertEqual(service.uniqueServiceName, "uuid:RINCON_000E5800000001400::urn:schemas-upnp-org:device:ZonePlayer:1")
        XCTAssertEqual(service.responseHeaders?["X-CUSTOM-HEADER"], "test-value")
    }

    func testSSDPDiscoveryStartAndCleanStop() {
        let discovery = SSDPDiscovery()
        let delegateSpy = MockSSDPDelegate()
        discovery.delegate = delegateSpy

        XCTAssertFalse(discovery.isDiscovering)

        let startExpectation = expectation(description: "SSDP started")
        delegateSpy.onStart = {
            startExpectation.fulfill()
        }

        discovery.discoverService(forDuration: 2, searchTarget: "urn:schemas-upnp-org:device:ZonePlayer:1")
        XCTAssertTrue(discovery.isDiscovering)

        wait(for: [startExpectation], timeout: 2.0)

        // Stopping explicitly should finish cleanly without error
        discovery.stop()
        XCTAssertFalse(discovery.isDiscovering)
        XCTAssertTrue(delegateSpy.didFinishCalled)
        XCTAssertNil(delegateSpy.receivedError, "Clean stop must not emit a socket error or bad file descriptor")
    }

    func testSSDPDiscoveryTimeoutFinishesCleanly() {
        let discovery = SSDPDiscovery()
        let delegateSpy = MockSSDPDelegate()
        discovery.delegate = delegateSpy

        let finishExpectation = expectation(description: "SSDP finished on timeout")
        delegateSpy.onFinish = {
            finishExpectation.fulfill()
        }

        discovery.discoverService(forDuration: 0.2, searchTarget: "urn:schemas-upnp-org:device:ZonePlayer:1")
        XCTAssertTrue(discovery.isDiscovering)

        wait(for: [finishExpectation], timeout: 2.0)
        XCTAssertFalse(discovery.isDiscovering)
        XCTAssertNil(delegateSpy.receivedError, "Timeout completion must not trigger socket error")
    }

    func testSonosTopologyParserWithSOAPEnvelope() throws {
        let soapXML = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetZoneGroupStateResponse xmlns:u="urn:schemas-upnp-org:service:ZoneGroupTopology:1">
              <ZoneGroupState>&lt;ZoneGroups&gt;&lt;ZoneGroup Coordinator=&quot;RINCON_1&quot; ID=&quot;RINCON_1:1&quot;&gt;&lt;ZoneGroupMember UUID=&quot;RINCON_1&quot; Location=&quot;http://192.168.1.50:1400/xml/device_description.xml&quot; ZoneName=&quot;Living Room&quot; ChannelMapSet=&quot;&quot; IsZoneBridge=&quot;0&quot;/&gt;&lt;/ZoneGroup&gt;&lt;/ZoneGroups&gt;</ZoneGroupState>
            </u:GetZoneGroupStateResponse>
          </s:Body>
        </s:Envelope>
        """

        let groups = try SonosTopologyParser.parse(xmlData: Data(soapXML.utf8))
        XCTAssertEqual(groups.count, 1)
        let group = groups[0]
        XCTAssertEqual(group.id, "RINCON_1:1")
        XCTAssertEqual(group.coordinatorUUID, "RINCON_1")
        XCTAssertEqual(group.members.count, 1)
        XCTAssertEqual(group.members[0].zoneName, "Living Room")
    }

    @MainActor
    func testSonosDiscoveryServiceAddKnownHostWithMock() async throws {
        let mock = MockSonosDevice(roomName: "Den", udn: "uuid:RINCON_TEST_MOCK_1", modelName: "Sonos Move")
        let port = try mock.start()
        defer { mock.stop() }

        let service = SonosDiscoveryService()
        guard let location = URL(string: "http://127.0.0.1:\(port)/xml/device_description.xml") else {
            XCTFail("Invalid mock location")
            return
        }
        await service.processDiscoveredLocation(location)
        XCTAssertTrue(service.knownHosts.contains("127.0.0.1"))
        XCTAssertFalse(service.discoveredDevices.isEmpty)
    }
}

private final class MockSSDPDelegate: SSDPDiscoveryDelegate {
    var didStartCalled = false
    var didFinishCalled = false
    var receivedError: Error?
    var discoveredServices: [SSDPService] = []

    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?

    func ssdpDiscoveryDidStart(_ discovery: SSDPDiscovery) {
        didStartCalled = true
        onStart?()
    }

    func ssdpDiscoveryDidFinish(_ discovery: SSDPDiscovery) {
        didFinishCalled = true
        onFinish?()
    }

    func ssdpDiscovery(_ discovery: SSDPDiscovery, didDiscoverService service: SSDPService) {
        discoveredServices.append(service)
    }

    func ssdpDiscovery(_ discovery: SSDPDiscovery, didFinishWithError error: Error) {
        receivedError = error
    }
}
