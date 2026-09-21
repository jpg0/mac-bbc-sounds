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
            return "Sonos SOAP fault (status \(statusCode)): \(detail)"
        case .networkError(let message):
            return "Network error communicating with Sonos: \(message)"
        }
    }
}

/// Controller responsible for sending UPnP AVTransport commands to a Sonos device or group.
/// Transport commands are always directed to the group coordinator.
public final class SonosController: Sendable {

    // MARK: - Properties

    /// Target Sonos device (or coordinator)
    public let device: SonosDevice

    /// URLSession used for SOAP HTTP requests
    public let session: URLSession

    // MARK: - Init

    public init(device: SonosDevice, session: URLSession = .shared) {
        self.device = device
        self.session = session
    }

    // MARK: - Endpoints

    /// AVTransport control endpoint URL on the group coordinator.
    public var avTransportEndpoint: URL? {
        device.avTransportControlURL
    }

    // MARK: - AVTransport Actions

    /// Sets the playback URI and DIDL-Lite metadata on the target Sonos device.
    public func setAVTransportURI(url: URL, metadata: SonosMetadata? = nil) async throws {
        let escapedURI = SonosMetadata.escapeXML(url.absoluteString)
        let escapedDIDL = metadata.map { SonosMetadata.escapeXML($0.didlLiteXML()) } ?? ""

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
    }

    /// Sends the `Pause` command to the target Sonos speaker.
    public func pause() async throws {
        _ = try await sendAVTransportAction("Pause")
    }

    /// Sends the `Stop` command to the target Sonos speaker.
    public func stop() async throws {
        _ = try await sendAVTransportAction("Stop")
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
