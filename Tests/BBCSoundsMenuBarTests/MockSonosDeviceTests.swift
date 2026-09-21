import XCTest
@testable import BBCSoundsMenuBar

final class MockSonosDeviceTests: XCTestCase {

    func testMockSonosDeviceLifecycleAndDescription() async throws {
        let mock = MockSonosDevice(roomName: "Kitchen", udn: "uuid:RINCON_TEST12345", modelName: "Sonos Era 100")
        let port = try mock.start()
        defer { mock.stop() }

        XCTAssertGreaterThan(port, 0)
        guard let url = URL(string: "http://127.0.0.1:\(port)/xml/device_description.xml") else {
            XCTFail("Invalid description URL")
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

    func testMockSonosDeviceAVTransportSOAP() async throws {
        let mock = MockSonosDevice(roomName: "Office")
        let port = try mock.start()
        defer { mock.stop() }

        let endpoint = URL(string: "http://127.0.0.1:\(port)/MediaRenderer/AVTransport/Control")!

        // 1. SetAVTransportURI
        let setURIBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <CurrentURI>https://example.com/stream.m3u8</CurrentURI>
              <CurrentURIMetaData>&lt;DIDL-Lite&gt;&lt;item&gt;&lt;dc:title&gt;BBC Radio 6 Music&lt;/dc:title&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</CurrentURIMetaData>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """

        var setURIReq = URLRequest(url: endpoint)
        setURIReq.httpMethod = "POST"
        setURIReq.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"", forHTTPHeaderField: "SOAPACTION")
        setURIReq.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        setURIReq.httpBody = Data(setURIBody.utf8)

        let (setURIData, setURIResp) = try await URLSession.shared.data(for: setURIReq)
        let setURIHTTP = try XCTUnwrap(setURIResp as? HTTPURLResponse)
        XCTAssertEqual(setURIHTTP.statusCode, 200)
        XCTAssertEqual(mock.receivedURI, "https://example.com/stream.m3u8")
        XCTAssertEqual(mock.receivedDIDLLite, "<DIDL-Lite><item><dc:title>BBC Radio 6 Music</dc:title></item></DIDL-Lite>")
        let setURIRespXML = try XCTUnwrap(String(data: setURIData, encoding: .utf8))
        XCTAssertTrue(setURIRespXML.contains("SetAVTransportURIResponse"))

        // 2. Play
        let playBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <Speed>1</Speed>
            </u:Play>
          </s:Body>
        </s:Envelope>
        """
        var playReq = URLRequest(url: endpoint)
        playReq.httpMethod = "POST"
        playReq.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#Play\"", forHTTPHeaderField: "SOAPACTION")
        playReq.httpBody = Data(playBody.utf8)

        let (_, playResp) = try await URLSession.shared.data(for: playReq)
        XCTAssertEqual((playResp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(mock.transportState, "PLAYING")

        // 3. GetTransportInfo
        let getInfoBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:GetTransportInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:GetTransportInfo>
          </s:Body>
        </s:Envelope>
        """
        var getInfoReq = URLRequest(url: endpoint)
        getInfoReq.httpMethod = "POST"
        getInfoReq.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#GetTransportInfo\"", forHTTPHeaderField: "SOAPACTION")
        getInfoReq.httpBody = Data(getInfoBody.utf8)

        let (infoData, infoResp) = try await URLSession.shared.data(for: getInfoReq)
        XCTAssertEqual((infoResp as? HTTPURLResponse)?.statusCode, 200)
        let infoXML = try XCTUnwrap(String(data: infoData, encoding: .utf8))
        XCTAssertTrue(infoXML.contains("<CurrentTransportState>PLAYING</CurrentTransportState>"))

        // 4. GetPositionInfo
        let getPosBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:GetPositionInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:GetPositionInfo>
          </s:Body>
        </s:Envelope>
        """
        var getPosReq = URLRequest(url: endpoint)
        getPosReq.httpMethod = "POST"
        getPosReq.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#GetPositionInfo\"", forHTTPHeaderField: "SOAPACTION")
        getPosReq.httpBody = Data(getPosBody.utf8)

        let (posData, posResp) = try await URLSession.shared.data(for: getPosReq)
        XCTAssertEqual((posResp as? HTTPURLResponse)?.statusCode, 200)
        let posXML = try XCTUnwrap(String(data: posData, encoding: .utf8))
        XCTAssertTrue(posXML.contains("<TrackDuration>\(mock.trackDuration)</TrackDuration>"))
        XCTAssertTrue(posXML.contains("<RelTime>\(mock.trackRelTime)</RelTime>"))

        // 5. Pause
        let pauseBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:Pause>
          </s:Body>
        </s:Envelope>
        """
        var pauseReq = URLRequest(url: endpoint)
        pauseReq.httpMethod = "POST"
        pauseReq.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#Pause\"", forHTTPHeaderField: "SOAPACTION")
        pauseReq.httpBody = Data(pauseBody.utf8)

        let (_, pauseResp) = try await URLSession.shared.data(for: pauseReq)
        XCTAssertEqual((pauseResp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(mock.transportState, "PAUSED_PLAYBACK")

        // 6. Stop
        let stopBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:Stop>
          </s:Body>
        </s:Envelope>
        """
        var stopReq = URLRequest(url: endpoint)
        stopReq.httpMethod = "POST"
        stopReq.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#Stop\"", forHTTPHeaderField: "SOAPACTION")
        stopReq.httpBody = Data(stopBody.utf8)

        let (_, stopResp) = try await URLSession.shared.data(for: stopReq)
        XCTAssertEqual((stopResp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(mock.transportState, "STOPPED")
    }

    func testMockSonosDeviceVolumeSOAP() async throws {
        let mock = MockSonosDevice(roomName: "Bedroom", currentVolume: 15)
        let port = try mock.start()
        defer { mock.stop() }

        let endpoint = URL(string: "http://127.0.0.1:\(port)/MediaRenderer/RenderingControl/Control")!

        // 1. SetVolume to 45
        let setVolBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
              <DesiredVolume>45</DesiredVolume>
            </u:SetVolume>
          </s:Body>
        </s:Envelope>
        """
        var setVolReq = URLRequest(url: endpoint)
        setVolReq.httpMethod = "POST"
        setVolReq.setValue("\"urn:schemas-upnp-org:service:RenderingControl:1#SetVolume\"", forHTTPHeaderField: "SOAPACTION")
        setVolReq.httpBody = Data(setVolBody.utf8)

        let (setVolData, setVolResp) = try await URLSession.shared.data(for: setVolReq)
        XCTAssertEqual((setVolResp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(mock.currentVolume, 45)
        let setVolXML = try XCTUnwrap(String(data: setVolData, encoding: .utf8))
        XCTAssertTrue(setVolXML.contains("SetVolumeResponse"))

        // 2. GetVolume
        let getVolBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:GetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
            </u:GetVolume>
          </s:Body>
        </s:Envelope>
        """
        var getVolReq = URLRequest(url: endpoint)
        getVolReq.httpMethod = "POST"
        getVolReq.setValue("\"urn:schemas-upnp-org:service:RenderingControl:1#GetVolume\"", forHTTPHeaderField: "SOAPACTION")
        getVolReq.httpBody = Data(getVolBody.utf8)

        let (getVolData, getVolResp) = try await URLSession.shared.data(for: getVolReq)
        XCTAssertEqual((getVolResp as? HTTPURLResponse)?.statusCode, 200)
        let getVolXML = try XCTUnwrap(String(data: getVolData, encoding: .utf8))
        XCTAssertTrue(getVolXML.contains("<CurrentVolume>45</CurrentVolume>"))
    }
}
