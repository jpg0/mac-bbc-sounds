import XCTest
@testable import BBCSoundsMenuBar

final class MockSonosDeviceTests: XCTestCase {

    // MARK: - Test Helpers

    @discardableResult
    private func sendSOAP(
        endpoint: URL,
        action: String,
        service: String = "AVTransport:1",
        xmlBody: String
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("\"urn:schemas-upnp-org:service:\(service)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(xmlBody.utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = try XCTUnwrap(resp as? HTTPURLResponse)
        return (data, http)
    }

    // MARK: - Tests

    func testMockSonosDeviceLifecycleAndDescription() async throws {
        let mock = MockSonosDevice(roomName: "Kitchen", udn: "uuid:RINCON_TEST12345", modelName: "Sonos Era 100")
        let port = try mock.start()
        defer { mock.stop() }

        XCTAssertGreaterThan(port, 0)

        // Test both canonical /xml/device_description.xml and shorthand /device_description.xml
        for path in ["/xml/device_description.xml", "/device_description.xml"] {
            guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
                XCTFail("Invalid description URL for path \(path)")
                return
            }

            let (data, response) = try await URLSession.shared.data(from: url)
            let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
            XCTAssertEqual(httpResponse.statusCode, 200)

            let xml = try XCTUnwrap(String(data: data, encoding: .utf8))
            XCTAssertTrue(xml.contains("<roomName>Kitchen</roomName>"))
            XCTAssertTrue(xml.contains("<friendlyName>Kitchen</friendlyName>"))
            XCTAssertTrue(xml.contains("<UDN>uuid:RINCON_TEST12345</UDN>"))
            XCTAssertTrue(xml.contains("<modelName>Sonos Era 100</modelName>"))
        }
    }

    func testMockSonosDeviceTopology() async throws {
        let mock = MockSonosDevice(roomName: "Living Room", udn: "uuid:RINCON_000E5800000001400")
        let port = try mock.start()
        defer { mock.stop() }

        guard let url = URL(string: "http://127.0.0.1:\(port)/status/topology") else {
            XCTFail("Invalid topology URL")
            return
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)

        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(xml.contains("<ZoneGroups>"))
        XCTAssertTrue(xml.contains("Coordinator=\"RINCON_000E5800000001400\""))
        XCTAssertTrue(xml.contains("ZoneName=\"Living Room\""))
    }

    func testMockSonosDeviceStopsCleanlyAndRejectsConnections() async throws {
        let mock = MockSonosDevice(roomName: "Den")
        let port = try mock.start()
        let url = URL(string: "http://127.0.0.1:\(port)/xml/device_description.xml")!

        // Confirm alive
        let (_, resp) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)

        // Stop listener
        mock.stop()

        // Verify that subsequent connection fails or is rejected
        do {
            let sessionConfig = URLSessionConfiguration.ephemeral
            sessionConfig.timeoutIntervalForRequest = 2
            let shortSession = URLSession(configuration: sessionConfig)
            _ = try await shortSession.data(from: url)
            XCTFail("Expected request to fail after mock device stopped")
        } catch {
            // Expected connection failure
            XCTAssertNotNil(error)
        }
    }

    func testMockSonosDeviceAVTransportSOAP() async throws {
        let mock = MockSonosDevice(roomName: "Office")
        let port = try mock.start()
        defer { mock.stop() }

        let endpoint = URL(string: "http://127.0.0.1:\(port)/MediaRenderer/AVTransport/Control")!

        // 1. SetAVTransportURI with XML-escaped ampersand in URI and DIDL metadata
        let setURIBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <CurrentURI>https://example.com/stream.m3u8?token=abc&amp;id=1</CurrentURI>
              <CurrentURIMetaData>&lt;DIDL-Lite&gt;&lt;item&gt;&lt;dc:title&gt;BBC Radio 6 Music&lt;/dc:title&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</CurrentURIMetaData>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """
        let (setURIData, setURIHTTP) = try await sendSOAP(endpoint: endpoint, action: "SetAVTransportURI", xmlBody: setURIBody)
        XCTAssertEqual(setURIHTTP.statusCode, 200)
        XCTAssertEqual(mock.receivedURI, "https://example.com/stream.m3u8?token=abc&id=1")
        XCTAssertEqual(mock.receivedDIDLLite, "<DIDL-Lite><item><dc:title>BBC Radio 6 Music</dc:title></item></DIDL-Lite>")
        XCTAssertTrue(String(decoding: setURIData, as: UTF8.self).contains("SetAVTransportURIResponse"))

        // 2. Play
        let playBody = "<s:Envelope><s:Body><u:Play><InstanceID>0</InstanceID><Speed>1</Speed></u:Play></s:Body></s:Envelope>"
        let (_, playHTTP) = try await sendSOAP(endpoint: endpoint, action: "Play", xmlBody: playBody)
        XCTAssertEqual(playHTTP.statusCode, 200)
        XCTAssertEqual(mock.transportState, "PLAYING")

        // 3. GetTransportInfo
        let getInfoBody = "<s:Envelope><s:Body><u:GetTransportInfo><InstanceID>0</InstanceID></u:GetTransportInfo></s:Body></s:Envelope>"
        let (infoData, infoHTTP) = try await sendSOAP(endpoint: endpoint, action: "GetTransportInfo", xmlBody: getInfoBody)
        XCTAssertEqual(infoHTTP.statusCode, 200)
        XCTAssertTrue(String(decoding: infoData, as: UTF8.self).contains("<CurrentTransportState>PLAYING</CurrentTransportState>"))

        // 4. GetPositionInfo
        let getPosBody = "<s:Envelope><s:Body><u:GetPositionInfo><InstanceID>0</InstanceID></u:GetPositionInfo></s:Body></s:Envelope>"
        let (posData, posHTTP) = try await sendSOAP(endpoint: endpoint, action: "GetPositionInfo", xmlBody: getPosBody)
        XCTAssertEqual(posHTTP.statusCode, 200)
        let posXML = String(decoding: posData, as: UTF8.self)
        XCTAssertTrue(posXML.contains("<TrackDuration>\(mock.trackDuration)</TrackDuration>"))
        XCTAssertTrue(posXML.contains("<RelTime>\(mock.trackRelTime)</RelTime>"))

        // 5. Pause
        let pauseBody = "<s:Envelope><s:Body><u:Pause><InstanceID>0</InstanceID></u:Pause></s:Body></s:Envelope>"
        let (_, pauseHTTP) = try await sendSOAP(endpoint: endpoint, action: "Pause", xmlBody: pauseBody)
        XCTAssertEqual(pauseHTTP.statusCode, 200)
        XCTAssertEqual(mock.transportState, "PAUSED_PLAYBACK")

        // 6. Stop
        let stopBody = "<s:Envelope><s:Body><u:Stop><InstanceID>0</InstanceID></u:Stop></s:Body></s:Envelope>"
        let (_, stopHTTP) = try await sendSOAP(endpoint: endpoint, action: "Stop", xmlBody: stopBody)
        XCTAssertEqual(stopHTTP.statusCode, 200)
        XCTAssertEqual(mock.transportState, "STOPPED")
    }

    func testMockSonosDeviceVolumeSOAP() async throws {
        let mock = MockSonosDevice(roomName: "Bedroom", currentVolume: 15)
        let port = try mock.start()
        defer { mock.stop() }

        let endpoint = URL(string: "http://127.0.0.1:\(port)/MediaRenderer/RenderingControl/Control")!

        // 1. SetVolume to 45
        let setVolBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
              <DesiredVolume>45</DesiredVolume>
            </u:SetVolume>
          </s:Body>
        </s:Envelope>
        """
        let (setVolData, setVolHTTP) = try await sendSOAP(
            endpoint: endpoint,
            action: "SetVolume",
            service: "RenderingControl:1",
            xmlBody: setVolBody
        )
        XCTAssertEqual(setVolHTTP.statusCode, 200)
        XCTAssertEqual(mock.currentVolume, 45)
        XCTAssertTrue(String(decoding: setVolData, as: UTF8.self).contains("SetVolumeResponse"))

        // 2. GetVolume
        let getVolBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
            </u:GetVolume>
          </s:Body>
        </s:Envelope>
        """
        let (getVolData, getVolHTTP) = try await sendSOAP(
            endpoint: endpoint,
            action: "GetVolume",
            service: "RenderingControl:1",
            xmlBody: getVolBody
        )
        XCTAssertEqual(getVolHTTP.statusCode, 200)
        XCTAssertTrue(String(decoding: getVolData, as: UTF8.self).contains("<CurrentVolume>45</CurrentVolume>"))
    }
}
