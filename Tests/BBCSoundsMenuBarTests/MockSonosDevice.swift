import Foundation
import Network

/// In-process mock Sonos UPnP/DLNA HTTP & SOAP device for unit and integration testing.
/// Runs on 127.0.0.1 on an ephemeral port.
final class MockSonosDevice {

    // MARK: - Properties

    let roomName: String
    let udn: String
    let modelName: String

    private let lock = NSLock()
    private var _transportState: String
    private var _currentVolume: Int
    private var _isMuted: Bool
    private var _trackDuration: String
    private var _trackRelTime: String
    private var _receivedURI: String?
    private var _receivedDIDLLite: String?
    private var _receivedActions: [String] = []
    private var _customTopologyXML: String?
    private var _avTransportError: (statusCode: Int, errorCode: Int)?
    private var _rejectSeekWhenStopped: Bool = false

    var rejectSeekWhenStopped: Bool {
        get { lock.withLock { _rejectSeekWhenStopped } }
        set { lock.withLock { _rejectSeekWhenStopped = newValue } }
    }

    var avTransportError: (statusCode: Int, errorCode: Int)? {
        get { lock.withLock { _avTransportError } }
        set { lock.withLock { _avTransportError = newValue } }
    }

    var customTopologyXML: String? {
        get { lock.withLock { _customTopologyXML } }
        set { lock.withLock { _customTopologyXML = newValue } }
    }

    var transportState: String {
        get { lock.withLock { _transportState } }
        set { lock.withLock { _transportState = newValue } }
    }

    var currentVolume: Int {
        get { lock.withLock { _currentVolume } }
        set { lock.withLock { _currentVolume = newValue } }
    }

    var isMuted: Bool {
        get { lock.withLock { _isMuted } }
        set { lock.withLock { _isMuted = newValue } }
    }

    var trackDuration: String {
        get { lock.withLock { _trackDuration } }
        set { lock.withLock { _trackDuration = newValue } }
    }

    var trackRelTime: String {
        get { lock.withLock { _trackRelTime } }
        set { lock.withLock { _trackRelTime = newValue } }
    }

    var receivedURI: String? {
        get { lock.withLock { _receivedURI } }
        set { lock.withLock { _receivedURI = newValue } }
    }

    var receivedDIDLLite: String? {
        get { lock.withLock { _receivedDIDLLite } }
        set { lock.withLock { _receivedDIDLLite = newValue } }
    }

    var receivedActions: [String] {
        get { lock.withLock { _receivedActions } }
    }

    var receivedActionBodies: [(action: String, body: String)] {
        get { lock.withLock { _receivedActionBodies } }
    }

    private var _receivedActionBodies: [(action: String, body: String)] = []

    // MARK: - Networking

    private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.trillica.MockSonosDevice", qos: .userInitiated)
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]

    var baseURL: URL? {
        guard port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    // MARK: - Init

    init(
        roomName: String = "Living Room",
        udn: String = "uuid:RINCON_000E5800000001400",
        modelName: String = "Sonos One",
        transportState: String = "STOPPED",
        currentVolume: Int = 25,
        isMuted: Bool = false,
        trackDuration: String = "01:00:00",
        trackRelTime: String = "00:05:00"
    ) {
        self.roomName = roomName
        self.udn = udn
        self.modelName = modelName
        self._transportState = transportState
        self._currentVolume = currentVolume
        self._isMuted = isMuted
        self._trackDuration = trackDuration
        self._trackRelTime = trackRelTime
    }

    // MARK: - Lifecycle

    @discardableResult
    func start() throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback

        let listenerInstance = try NWListener(using: params, on: .any)
        self.listener = listenerInstance

        let readyGroup = DispatchGroup()
        readyGroup.enter()

        listenerInstance.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.port = listenerInstance.port?.rawValue ?? 0
                readyGroup.leave()
            case .failed(let err):
                print("⚠️ [MockSonosDevice] Listener failed: \(err)")
                readyGroup.leave()
            default:
                break
            }
        }

        listenerInstance.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }

        listenerInstance.start(queue: queue)
        readyGroup.wait()

        guard port > 0 else {
            throw NSError(domain: "MockSonosDevice", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to bind MockSonosDevice listener"])
        }

        return port
    }

    func stop() {
        listener?.cancel()
        listener = nil

        lock.withLock {
            for conn in activeConnections.values {
                conn.cancel()
            }
            activeConnections.removeAll()
        }
    }

    // MARK: - Connection Handling

    private func handleConnection(_ conn: NWConnection) {
        let connId = ObjectIdentifier(conn)
        lock.withLock {
            activeConnections[connId] = conn
        }

        conn.stateUpdateHandler = { [weak self, weak conn] state in
            switch state {
            case .cancelled, .failed:
                if let conn {
                    let id = ObjectIdentifier(conn)
                    self?.lock.withLock {
                        _ = self?.activeConnections.removeValue(forKey: id)
                    }
                }
            default:
                break
            }
        }

        conn.start(queue: queue)
        receiveData(on: conn, accumulated: Data())
    }

    private func receiveData(on conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, err in
            guard let self else { return }
            guard err == nil, let data else {
                conn.cancel()
                return
            }

            var fullData = accumulated
            fullData.append(data)

            // Check if we received full HTTP request headers
            if let separatorRange = fullData.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = fullData.subdata(in: 0..<separatorRange.lowerBound)
                let bodyData = fullData.subdata(in: separatorRange.upperBound..<fullData.count)

                if let headerText = String(data: headerData, encoding: .utf8) {
                    let contentLength = self.parseContentLength(headerText)
                    if bodyData.count >= contentLength {
                        self.processRequest(headerText: headerText, bodyData: bodyData, conn: conn)
                        return
                    }
                }
            }

            if isComplete {
                if let headerText = String(data: fullData, encoding: .utf8) {
                    self.processRequest(headerText: headerText, bodyData: Data(), conn: conn)
                } else {
                    conn.cancel()
                }
            } else {
                self.receiveData(on: conn, accumulated: fullData)
            }
        }
    }

    private func parseContentLength(_ headerText: String) -> Int {
        for line in headerText.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2, let len = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                    return len
                }
            }
        }
        return 0
    }

    private func processRequest(headerText: String, bodyData: Data, conn: NWConnection) {
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            send(conn: conn, code: 400, body: Data("Bad Request".utf8))
            return
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            send(conn: conn, code: 400, body: Data("Bad Request".utf8))
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let headerParts = line.split(separator: ":", maxSplits: 1)
            if headerParts.count == 2 {
                headers[headerParts[0].trimmingCharacters(in: .whitespaces).lowercased()] = headerParts[1].trimmingCharacters(in: .whitespaces)
            }
        }

        let bodyText = String(data: bodyData, encoding: .utf8) ?? ""

        // Route by path
        if method == "GET" && (path == "/xml/device_description.xml" || path == "/device_description.xml") {
            let xml = makeDeviceDescriptionXML()
            send(conn: conn, code: 200, contentType: "text/xml; charset=\"utf-8\"", body: Data(xml.utf8))
            return
        }

        if method == "GET" && path == "/status/topology" {
            let xml = makeTopologyXML()
            send(conn: conn, code: 200, contentType: "text/xml; charset=\"utf-8\"", body: Data(xml.utf8))
            return
        }

        if method == "POST" && path == "/MediaRenderer/AVTransport/Control" {
            let action = resolveSOAPAction(headers: headers, bodyText: bodyText)
            recordAction(action, body: bodyText)
            if let fault = avTransportError {
                let faultXML = """
                <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
                  <s:Body>
                    <s:Fault>
                      <faultcode>s:Client</faultcode>
                      <faultstring>UPnPError</faultstring>
                      <detail>
                        <UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
                          <errorCode>\(fault.errorCode)</errorCode>
                        </UPnPError>
                      </detail>
                    </s:Fault>
                  </s:Body>
                </s:Envelope>
                """
                send(conn: conn, code: fault.statusCode, contentType: "text/xml; charset=\"utf-8\"", body: Data(faultXML.utf8))
                return
            }
            if action == "Seek" && rejectSeekWhenStopped && transportState == "STOPPED" {
                let fault701XML = """
                <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
                  <s:Body>
                    <s:Fault>
                      <faultcode>s:Client</faultcode>
                      <faultstring>UPnPError</faultstring>
                      <detail>
                        <UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
                          <errorCode>701</errorCode>
                        </UPnPError>
                      </detail>
                    </s:Fault>
                  </s:Body>
                </s:Envelope>
                """
                send(conn: conn, code: 500, contentType: "text/xml; charset=\"utf-8\"", body: Data(fault701XML.utf8))
                return
            }
            let responseXML = handleAVTransportAction(action: action, bodyText: bodyText)
            send(conn: conn, code: 200, contentType: "text/xml; charset=\"utf-8\"", body: Data(responseXML.utf8))
            return
        }

        if method == "POST" && path == "/MediaRenderer/RenderingControl/Control" {
            let action = resolveSOAPAction(headers: headers, bodyText: bodyText)
            recordAction(action, body: bodyText)
            let responseXML = handleRenderingControlAction(action: action, bodyText: bodyText)
            send(conn: conn, code: 200, contentType: "text/xml; charset=\"utf-8\"", body: Data(responseXML.utf8))
            return
        }

        send(conn: conn, code: 404, body: Data("Not Found".utf8))
    }

    private func recordAction(_ action: String, body: String = "") {
        lock.withLock {
            _receivedActions.append(action)
            _receivedActionBodies.append((action: action, body: body))
        }
    }

    private func resolveSOAPAction(headers: [String: String], bodyText: String) -> String {
        if let soapHeader = headers["soapaction"] {
            let trimmed = soapHeader.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if let hashIdx = trimmed.lastIndex(of: "#") {
                return String(trimmed[trimmed.index(after: hashIdx)...])
            }
            return trimmed
        }

        // Fallback: search for tag <u:ActionName
        if let match = bodyText.range(of: "<u:[A-Za-z0-9]+", options: .regularExpression) {
            let tag = bodyText[match]
            return String(tag.dropFirst(3))
        }
        return "Unknown"
    }

    // MARK: - SOAP Handlers

    private func soapEnvelope(body: String) -> String {
        return """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            \(body)
          </s:Body>
        </s:Envelope>
        """
    }

    private func unescapeXMLEntities(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private func handleAVTransportAction(action: String, bodyText: String) -> String {
        switch action {
        case "SetAVTransportURI":
            let rawURI = extractTag(name: "CurrentURI", from: bodyText)
            let uri = rawURI.map { unescapeXMLEntities($0) }
            let rawMeta = extractTag(name: "CurrentURIMetaData", from: bodyText)
            let unescapedMeta = rawMeta.map { unescapeXMLEntities($0) }

            lock.withLock {
                _receivedURI = uri
                _receivedDIDLLite = unescapedMeta
            }

            return soapEnvelope(body: "<u:SetAVTransportURIResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\" />")

        case "Play":
            lock.withLock { _transportState = "PLAYING" }
            return soapEnvelope(body: "<u:PlayResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\" />")

        case "Pause":
            lock.withLock { _transportState = "PAUSED_PLAYBACK" }
            return soapEnvelope(body: "<u:PauseResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\" />")

        case "Stop":
            lock.withLock { _transportState = "STOPPED" }
            return soapEnvelope(body: "<u:StopResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\" />")

        case "Seek":
            if let target = extractTag(name: "Target", from: bodyText) {
                lock.withLock { _trackRelTime = target }
            }
            return soapEnvelope(body: "<u:SeekResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\" />")

        case "GetTransportInfo":
            let state = transportState
            return soapEnvelope(body: """
            <u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <CurrentTransportState>\(state)</CurrentTransportState>
              <CurrentTransportStatus>OK</CurrentTransportStatus>
              <CurrentSpeed>1</CurrentSpeed>
            </u:GetTransportInfoResponse>
            """)

        case "GetPositionInfo":
            let dur = trackDuration
            let rel = trackRelTime
            let curURI = receivedURI ?? ""
            return soapEnvelope(body: """
            <u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <Track>1</Track>
              <TrackDuration>\(dur)</TrackDuration>
              <TrackMetaData></TrackMetaData>
              <TrackURI>\(curURI)</TrackURI>
              <RelTime>\(rel)</RelTime>
              <AbsTime>\(rel)</AbsTime>
              <RelCount>2147483647</RelCount>
              <AbsCount>2147483647</AbsCount>
            </u:GetPositionInfoResponse>
            """)

        default:
            return soapEnvelope(body: "<u:\(action)Response xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\" />")
        }
    }

    private func handleRenderingControlAction(action: String, bodyText: String) -> String {
        switch action {
        case "SetVolume":
            if let volStr = extractTag(name: "DesiredVolume", from: bodyText), let vol = Int(volStr) {
                currentVolume = vol
            }
            return soapEnvelope(body: "<u:SetVolumeResponse xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\" />")

        case "GetVolume":
            let vol = currentVolume
            return soapEnvelope(body: """
            <u:GetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <CurrentVolume>\(vol)</CurrentVolume>
            </u:GetVolumeResponse>
            """)

        case "SetMute":
            if let muteStr = extractTag(name: "DesiredMute", from: bodyText), let mute = Int(muteStr) {
                isMuted = (mute != 0)
            }
            return soapEnvelope(body: "<u:SetMuteResponse xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\" />")

        case "GetMute":
            let muteVal = isMuted ? 1 : 0
            return soapEnvelope(body: """
            <u:GetMuteResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <CurrentMute>\(muteVal)</CurrentMute>
            </u:GetMuteResponse>
            """)

        default:
            return soapEnvelope(body: "<u:\(action)Response xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\" />")
        }
    }

    private func extractTag(name: String, from xml: String) -> String? {
        let pattern = "<(?:[a-zA-Z0-9_-]+:)?\(name)(?:\\s+[^>]*)?>(.*?)</(?:[a-zA-Z0-9_-]+:)?\(name)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: xml, options: [], range: NSRange(location: 0, length: xml.utf16.count)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[range])
    }

    // MARK: - XML Generators

    private func makeDeviceDescriptionXML() -> String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <specVersion>
            <major>1</major>
            <minor>0</minor>
          </specVersion>
          <device>
            <deviceType>urn:schemas-upnp-org:device:ZonePlayer:1</deviceType>
            <friendlyName>\(roomName)</friendlyName>
            <roomName>\(roomName)</roomName>
            <displayName>\(roomName)</displayName>
            <UDN>\(udn)</UDN>
            <modelName>\(modelName)</modelName>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
                <controlURL>/MediaRenderer/AVTransport/Control</controlURL>
                <eventSubURL>/MediaRenderer/AVTransport/Event</eventSubURL>
              </service>
              <service>
                <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
                <controlURL>/MediaRenderer/RenderingControl/Control</controlURL>
                <eventSubURL>/MediaRenderer/RenderingControl/Event</eventSubURL>
              </service>
            </serviceList>
          </device>
        </root>
        """
    }

    private func makeTopologyXML() -> String {
        if let custom = customTopologyXML {
            return custom
        }
        let rawUUID = udn.replacingOccurrences(of: "uuid:", with: "")
        return """
        <ZoneGroups>
          <ZoneGroup Coordinator="\(rawUUID)" ID="\(rawUUID):1">
            <ZoneGroupMember UUID="\(rawUUID)" Location="http://127.0.0.1:\(port)/xml/device_description.xml" ZoneName="\(roomName)" ChannelMapSet="" IsZoneBridge="0"/>
          </ZoneGroup>
        </ZoneGroups>
        """
    }

    // MARK: - HTTP Response

    private func send(conn: NWConnection, code: Int, contentType: String = "text/plain", body: Data) {
        let phrase: String
        switch code {
        case 200: phrase = "OK"
        case 400: phrase = "Bad Request"
        case 404: phrase = "Not Found"
        case 405: phrase = "Method Not Allowed"
        case 500: phrase = "Internal Server Error"
        default: phrase = "Unknown"
        }

        var header = "HTTP/1.1 \(code) \(phrase)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"

        var packet = Data(header.utf8)
        packet.append(body)

        conn.send(content: packet, completion: .contentProcessed { [weak self, weak conn] _ in
            conn?.cancel()
            if let conn {
                let id = ObjectIdentifier(conn)
                self?.lock.withLock {
                    _ = self?.activeConnections.removeValue(forKey: id)
                }
            }
        })
    }
}
