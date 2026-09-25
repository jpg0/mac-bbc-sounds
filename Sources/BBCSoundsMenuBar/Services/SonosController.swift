import Foundation

/// Errors that can occur during Sonos UPnP SOAP operations.
public enum SonosError: LocalizedError, Equatable {
    case invalidEndpoint
    case invalidResponse(statusCode: Int)
    case soapFault(statusCode: Int, detail: String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid Sonos coordinator endpoint URL."
        case .invalidResponse(let statusCode):
            return "Sonos returned an invalid HTTP response (status \(statusCode))."
        case .soapFault(let statusCode, let detail):
            if detail.contains("<errorCode>800</errorCode>") {
                return "Sonos cannot access this stream (stream unreachable or geo-blocked)."
            }
            if detail.contains("<errorCode>701</errorCode>") {
                return "Sonos playback failed (transition unavailable)."
            }
            if detail.contains("<errorCode>714</errorCode>") {
                return "Sonos cannot play this stream format (illegal MIME-type). The stream URI requires a compatible Sonos stream protocol."
            }
            return "Sonos SOAP fault (status \(statusCode)): \(detail)"
        case .networkError(let message):
            return "Network error communicating with Sonos: \(message)"
        }
    }
}

/// Controller responsible for sending UPnP AVTransport and RenderingControl commands
/// to a Sonos device or group, and synchronizing volume and playback position.
@MainActor
public final class SonosController: ObservableObject {

    // MARK: - Properties

    /// Target Sonos device (or coordinator)
    public let device: SonosDevice

    /// URLSession used for SOAP HTTP requests
    public let session: URLSession

    // MARK: - Published State

    /// Current speaker volume (scale 0-100)
    @Published public private(set) var volume: Int = 0

    /// Current speaker mute state
    @Published public private(set) var isMuted: Bool = false

    /// Transport info representing state, status, and speed
    @Published public private(set) var transportInfo: SonosTransportInfo = SonosTransportInfo()

    /// Current transport state (PLAYING, PAUSED_PLAYBACK, STOPPED, etc.)
    @Published public private(set) var transportState: SonosTransportState = .stopped

    /// Convenience flag whether playback is currently playing
    @Published public private(set) var isPlaying: Bool = false

    /// Playback position information (track duration, elapsed time, track URI)
    @Published public private(set) var positionInfo: SonosPositionInfo = .zero

    /// Current playback elapsed time in seconds
    @Published public internal(set) var currentTime: TimeInterval = 0

    /// Total track duration in seconds
    @Published public internal(set) var duration: TimeInterval = 0

    /// Whether the background state polling task is active
    @Published public private(set) var isPolling: Bool = false

    // MARK: - Private Polling State

    private var pollingTask: Task<Void, Never>?

    // MARK: - Init & Deinit

    nonisolated public static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 12.0
        return URLSession(configuration: config)
    }()

    public init(device: SonosDevice, session: URLSession = defaultSession) {
        self.device = device
        self.session = session
    }

    deinit {
        pollingTask?.cancel()
    }

    // MARK: - Endpoints

    /// AVTransport control endpoint URL on the group coordinator.
    public var avTransportEndpoint: URL? {
        device.avTransportControlURL
    }

    /// RenderingControl control endpoint URL on this speaker.
    public var renderingControlEndpoint: URL? {
        device.renderingControlURL
    }

    // MARK: - RenderingControl Actions

    /// Retrieves current speaker volume (scale 0-100) via RenderingControl SOAP action.
    @discardableResult
    public func getVolume() async throws -> Int {
        guard let endpoint = renderingControlEndpoint else {
            throw SonosError.invalidEndpoint
        }

        let actionBody = """
          <InstanceID>0</InstanceID>
          <Channel>Master</Channel>
        """

        let soapBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:GetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              \(actionBody)
            </u:GetVolume>
          </s:Body>
        </s:Envelope>
        """

        let data = try await sendSOAP(
            endpoint: endpoint,
            service: "RenderingControl:1",
            action: "GetVolume",
            body: soapBody
        )

        let vol = try SonosVolumeParser.parse(xmlData: data)
        self.volume = vol
        return vol
    }

    /// Sets speaker volume (scale 0-100) via RenderingControl SOAP action.
    public func setVolume(_ newVolume: Int) async throws {
        guard let endpoint = renderingControlEndpoint else {
            throw SonosError.invalidEndpoint
        }

        let clamped = max(0, min(100, newVolume))
        let actionBody = """
          <InstanceID>0</InstanceID>
          <Channel>Master</Channel>
          <DesiredVolume>\(clamped)</DesiredVolume>
        """

        let soapBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              \(actionBody)
            </u:SetVolume>
          </s:Body>
        </s:Envelope>
        """

        _ = try await sendSOAP(
            endpoint: endpoint,
            service: "RenderingControl:1",
            action: "SetVolume",
            body: soapBody
        )

        self.volume = clamped
    }

    /// Retrieves current speaker mute state via RenderingControl SOAP action.
    @discardableResult
    public func getMute() async throws -> Bool {
        guard let endpoint = renderingControlEndpoint else {
            throw SonosError.invalidEndpoint
        }

        let actionBody = """
          <InstanceID>0</InstanceID>
          <Channel>Master</Channel>
        """

        let soapBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:GetMute xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              \(actionBody)
            </u:GetMute>
          </s:Body>
        </s:Envelope>
        """

        let data = try await sendSOAP(
            endpoint: endpoint,
            service: "RenderingControl:1",
            action: "GetMute",
            body: soapBody
        )

        let muted = try SonosMuteParser.parse(xmlData: data)
        self.isMuted = muted
        return muted
    }

    /// Sets speaker mute state via RenderingControl SOAP action.
    public func setMute(_ muted: Bool) async throws {
        guard let endpoint = renderingControlEndpoint else {
            throw SonosError.invalidEndpoint
        }

        let actionBody = """
          <InstanceID>0</InstanceID>
          <Channel>Master</Channel>
          <DesiredMute>\(muted ? "1" : "0")</DesiredMute>
        """

        let soapBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetMute xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              \(actionBody)
            </u:SetMute>
          </s:Body>
        </s:Envelope>
        """

        _ = try await sendSOAP(
            endpoint: endpoint,
            service: "RenderingControl:1",
            action: "SetMute",
            body: soapBody
        )

        self.isMuted = muted
    }

    // MARK: - AVTransport Actions

    /// Converts an HTTP/HTTPS stream URL into a Sonos-compatible transport URI.
    /// Live streams require x-rincon-mp3radio:// so Sonos treats them as live radio broadcasts.
    /// On-demand streams retain standard http:// or https:// so Sonos recognizes them as static HLS (hls-static://),
    /// which allows track scrubbing and REL_TIME seeking.
    public static func sonosTransportURI(for url: URL, isLive: Bool = true) -> URL {
        if isLive {
            let str = url.absoluteString
            if str.hasPrefix("x-rincon-mp3radio:") || str.hasPrefix("hls-radio:") {
                return url
            }
            if str.hasPrefix("http://") {
                let replaced = "x-rincon-mp3radio://" + str.dropFirst("http://".count)
                return URL(string: replaced) ?? url
            }
            if str.hasPrefix("https://") {
                let replaced = "x-rincon-mp3radio://" + str.dropFirst("https://".count)
                return URL(string: replaced) ?? url
            }
            return url
        } else {
            let str = url.absoluteString
            if str.hasPrefix("x-rincon-mp3radio://") {
                let replaced = "http://" + str.dropFirst("x-rincon-mp3radio://".count)
                return URL(string: replaced) ?? url
            }
            return url
        }
    }

    /// Sets the playback URI and DIDL-Lite metadata on the target Sonos device.
    public func setAVTransportURI(url: URL, metadata: SonosMetadata? = nil) async throws {
        let isLive = metadata?.isLive ?? true
        let transportURL = Self.sonosTransportURI(for: url, isLive: isLive)
        let escapedURI = SonosMetadata.escapeXML(transportURL.absoluteString)
        let escapedDIDL = metadata.map { SonosMetadata.escapeXML($0.didlLiteXML(uri: transportURL.absoluteString)) } ?? ""

        let actionBody = """
          <CurrentURI>\(escapedURI)</CurrentURI>
          <CurrentURIMetaData>\(escapedDIDL)</CurrentURIMetaData>
        """

        _ = try await sendAVTransportAction("SetAVTransportURI", actionBody: actionBody)
    }

    /// Convenience overload to set AVTransport URI with metadata from a `Programme`.
    func setAVTransportURI(url: URL, programme: Programme) async throws {
        try await setAVTransportURI(url: url, metadata: SonosMetadata(programme: programme))
    }

    /// Sends the `Play` command to the target Sonos speaker.
    public func play() async throws {
        _ = try await sendAVTransportAction("Play", actionBody: "<Speed>1</Speed>")
        self.transportState = .playing
        self.isPlaying = true
    }

    /// Sends the `Pause` command to the target Sonos speaker.
    public func pause() async throws {
        _ = try await sendAVTransportAction("Pause")
        self.transportState = .paused
        self.isPlaying = false
    }

    /// Sends the `Stop` command to the target Sonos speaker.
    public func stop() async throws {
        _ = try await sendAVTransportAction("Stop")
        self.transportState = .stopped
        self.isPlaying = false
    }

    /// Fetches the current transport status and playback state via GetTransportInfo.
    @discardableResult
    public func getTransportInfo() async throws -> SonosTransportInfo {
        let data = try await sendAVTransportAction("GetTransportInfo")
        let info = try SonosTransportInfoParser.parse(xmlData: data)
        self.transportInfo = info
        self.transportState = info.state
        self.isPlaying = (info.state == .playing)
        return info
    }

    /// Fetches track duration and relative elapsed time via GetPositionInfo.
    @discardableResult
    public func getPositionInfo() async throws -> SonosPositionInfo {
        let data = try await sendAVTransportAction("GetPositionInfo")
        let info = try SonosPositionInfoParser.parse(xmlData: data)
        self.positionInfo = info
        self.currentTime = info.trackRelTime
        if info.trackDuration > 0 {
            self.duration = info.trackDuration
        }
        return info
    }

    /// Seeks to a specific timestamp in seconds (converts to REL_TIME format HH:MM:SS).
    public func seek(to seconds: TimeInterval) async throws {
        let formatted = SonosPositionInfo.formatTimeInterval(seconds)
        try await seek(target: formatted)
        self.currentTime = seconds
    }

    /// Seeks using a raw UPnP target timestamp (e.g. "00:15:30").
    public func seek(target: String) async throws {
        let actionBody = """
          <Unit>REL_TIME</Unit>
          <Target>\(target)</Target>
        """
        _ = try await sendAVTransportAction("Seek", actionBody: actionBody)
    }

    // MARK: - State Polling

    /// Starts periodic background polling of volume, transport info, and position info.
    public func startPolling(interval: TimeInterval = 1.5) {
        stopPolling()
        isPolling = true
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollState()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// Stops periodic background polling.
    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    /// Polls volume, transport info, and position info from the speaker once, ignoring individual transient errors.
    public func pollState() async {
        if let vol = try? await getVolume() {
            self.volume = vol
        }
        if let muted = try? await getMute() {
            self.isMuted = muted
        }
        if let tInfo = try? await getTransportInfo() {
            self.transportInfo = tInfo
            self.transportState = tInfo.state
            if tInfo.state == .playing {
                self.isPlaying = true
            } else if tInfo.state == .stopped || tInfo.state == .paused {
                self.isPlaying = false
            }
        }
        if let pInfo = try? await getPositionInfo() {
            self.positionInfo = pInfo
            self.currentTime = pInfo.trackRelTime
            self.duration = pInfo.trackDuration
        }
    }

    // MARK: - SOAP Dispatch Helpers

    @discardableResult
    private func sendAVTransportAction(_ action: String, actionBody: String = "") async throws -> Data {
        guard let endpoint = avTransportEndpoint else {
            throw SonosError.invalidEndpoint
        }

        let innerBody = actionBody.isEmpty
            ? "<InstanceID>0</InstanceID>"
            : "<InstanceID>0</InstanceID>\n        \(actionBody)"

        let soapBody = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:\(action) xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              \(innerBody)
            </u:\(action)>
          </s:Body>
        </s:Envelope>
        """

        return try await sendSOAP(
            endpoint: endpoint,
            service: "AVTransport:1",
            action: action,
            body: soapBody
        )
    }

    @discardableResult
    private func sendSOAP(
        endpoint: URL,
        service: String,
        action: String,
        body: String
    ) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:\(service)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(body.utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SonosError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SonosError.invalidResponse(statusCode: 0)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw SonosError.soapFault(statusCode: httpResponse.statusCode, detail: detail)
        }

        return data
    }
}
