import Foundation

/// Errors that can occur during Sonos stream delivery resolution.
public enum SonosDeliveryError: LocalizedError, Equatable {
    case lanAddressNotFound
    case proxyServerNotRunning
    case failedToGenerateRelayURL

    public var errorDescription: String? {
        switch self {
        case .lanAddressNotFound:
            return "Unable to resolve the Mac's local network (LAN) IP address for Sonos streaming."
        case .proxyServerNotRunning:
            return "Local proxy server is not running."
        case .failedToGenerateRelayURL:
            return "Failed to construct the local relay URL for Sonos."
        }
    }
}

/// Service responsible for smart stream delivery to Sonos devices.
///
/// Delivery Strategy:
/// - When no proxy is configured: Sonos streams directly from the BBC CDN over the internet.
/// - When a proxy is configured: A LAN-bound `LocalProxyServer` (listening on `0.0.0.0`) relays
///   the stream and media segments, providing Sonos with an accessible `http://<lan-ip>:<port>/playlist?url=...` URL.
struct SonosStreamDeliveryService: Sendable {

    /// Closure used to resolve the Mac's LAN IPv4 address.
    let getLANIP: @Sendable () -> String?

    init(getLANIP: @escaping @Sendable () -> String? = { NetworkUtilities.primaryIPv4Address() }) {
        self.getLANIP = getLANIP
    }

    /// Determines the playback URL to supply to Sonos via AVTransport.
    /// - Parameters:
    ///   - streamURL: The canonical BBC stream URL.
    ///   - proxyConfig: Active proxy configuration, if any.
    ///   - proxyServer: Active running `LocalProxyServer` instance, required if `proxyConfig` is present.
    /// - Returns: The URL Sonos should stream from (direct BBC URL or local LAN relay URL).
    func resolveDeliveryURL(
        for streamURL: URL,
        proxyConfig: ProxyConfiguration?,
        proxyServer: LocalProxyServer?
    ) throws -> URL {
        guard proxyConfig != nil else {
            // Direct streaming from BBC CDN
            return streamURL
        }

        guard let server = proxyServer, server.isRunning else {
            throw SonosDeliveryError.proxyServerNotRunning
        }

        guard let lanIP = server.advertisedHost ?? getLANIP() else {
            throw SonosDeliveryError.lanAddressNotFound
        }

        guard let relayURL = server.relayURL(for: streamURL, host: lanIP) else {
            throw SonosDeliveryError.failedToGenerateRelayURL
        }

        return relayURL
    }

    /// Default fixed LAN port for Sonos streaming so firewall rules can target a stable port.
    public static let defaultPort: UInt16 = LocalProxyServer.defaultFixedPort

    /// Prepares or restarts a `LocalProxyServer` bound to all interfaces (`0.0.0.0`) for Sonos streaming.
    /// - Parameters:
    ///   - proxyConfig: The active proxy configuration.
    ///   - existingServer: An optional currently active server instance.
    ///   - preferredPort: Optional port to bind to (defaults to defaultPort 52800).
    /// - Returns: A running `LocalProxyServer` bound to all interfaces.
    func prepareServer(
        proxyConfig: ProxyConfiguration,
        existingServer: LocalProxyServer? = nil,
        preferredPort: UInt16? = defaultPort
    ) throws -> LocalProxyServer {
        if let existing = existingServer, existing.isRunning, existing.bindAddress == .any {
            return existing
        }

        existingServer?.stop()
        let lanIP = getLANIP()
        let server = LocalProxyServer(
            proxyConfig: proxyConfig,
            bindAddress: .any,
            advertisedHost: lanIP,
            preferredPort: preferredPort
        )
        try server.start()
        return server
    }
}
