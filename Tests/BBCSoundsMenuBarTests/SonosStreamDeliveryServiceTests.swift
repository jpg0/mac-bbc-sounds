import XCTest
@testable import BBCSoundsMenuBar

final class SonosStreamDeliveryServiceTests: XCTestCase {

    let sampleStreamURL = URL(string: "https://as-hls-uk-live.akamaized.net/live/bbc_radio_one.m3u8")!
    let mockProxyConfig = ProxyConfiguration(host: "proxy.example.com", port: 8080, user: "u", pass: "p", skipVerify: false)

    func testResolveDeliveryURLWithoutProxyDirectStreaming() throws {
        let service = SonosStreamDeliveryService(getLANIP: { "192.168.1.50" })

        let resolved = try service.resolveDeliveryURL(
            for: sampleStreamURL,
            proxyConfig: nil,
            proxyServer: nil
        )

        XCTAssertEqual(resolved, sampleStreamURL, "Without proxy, stream URL should be returned directly for CDN streaming")
    }

    func testResolveDeliveryURLWithProxyRelay() throws {
        let service = SonosStreamDeliveryService(getLANIP: { "192.168.1.77" })

        let server = LocalProxyServer(proxyConfig: mockProxyConfig, bindAddress: .any, advertisedHost: "192.168.1.77")
        let port = try server.start()
        defer { server.stop() }

        let resolved = try service.resolveDeliveryURL(
            for: sampleStreamURL,
            proxyConfig: mockProxyConfig,
            proxyServer: server
        )

        XCTAssertEqual(resolved.scheme, "http")
        XCTAssertEqual(resolved.host, "192.168.1.77")
        XCTAssertEqual(resolved.port, Int(port))
        XCTAssertEqual(resolved.path, "/playlist")

        let comps = URLComponents(url: resolved, resolvingAgainstBaseURL: false)
        let queryURL = comps?.queryItems?.first(where: { $0.name == "url" })?.value
        XCTAssertEqual(queryURL, sampleStreamURL.absoluteString)
    }

    func testResolveDeliveryURLThrowsWhenServerNotRunning() {
        let service = SonosStreamDeliveryService(getLANIP: { "192.168.1.77" })

        // Nil server
        XCTAssertThrowsError(
            try service.resolveDeliveryURL(for: sampleStreamURL, proxyConfig: mockProxyConfig, proxyServer: nil)
        ) { error in
            XCTAssertEqual(error as? SonosDeliveryError, .proxyServerNotRunning)
        }

        // Server created but not started (port == 0)
        let stoppedServer = LocalProxyServer(proxyConfig: mockProxyConfig, bindAddress: .any)
        XCTAssertThrowsError(
            try service.resolveDeliveryURL(for: sampleStreamURL, proxyConfig: mockProxyConfig, proxyServer: stoppedServer)
        ) { error in
            XCTAssertEqual(error as? SonosDeliveryError, .proxyServerNotRunning)
        }
    }

    func testResolveDeliveryURLThrowsWhenLANIPNotFound() throws {
        let service = SonosStreamDeliveryService(getLANIP: { nil })

        let server = LocalProxyServer(proxyConfig: mockProxyConfig, bindAddress: .any, advertisedHost: nil)
        // start() sets advertisedHost if NetworkUtilities returns an IP, so explicitly clear it:
        try server.start()
        defer { server.stop() }
        server.advertisedHost = nil

        XCTAssertThrowsError(
            try service.resolveDeliveryURL(for: sampleStreamURL, proxyConfig: mockProxyConfig, proxyServer: server)
        ) { error in
            XCTAssertEqual(error as? SonosDeliveryError, .lanAddressNotFound)
        }
    }

    func testPrepareServerReusesExistingLANBoundServer() throws {
        let service = SonosStreamDeliveryService(getLANIP: { "192.168.1.88" })

        let server = LocalProxyServer(proxyConfig: mockProxyConfig, bindAddress: .any, advertisedHost: "192.168.1.88")
        try server.start()
        defer { server.stop() }

        let prepared = try service.prepareServer(proxyConfig: mockProxyConfig, existingServer: server)
        XCTAssertTrue(prepared === server, "Should reuse existing running LAN-bound server")
    }

    func testPrepareServerReplacesLoopbackServer() throws {
        let service = SonosStreamDeliveryService(getLANIP: { "192.168.1.88" })

        let loopbackServer = LocalProxyServer(proxyConfig: mockProxyConfig, bindAddress: .loopback)
        try loopbackServer.start()

        let prepared = try service.prepareServer(proxyConfig: mockProxyConfig, existingServer: loopbackServer)
        defer { prepared.stop() }

        XCTAssertFalse(loopbackServer.isRunning, "Old loopback server should be stopped")
        XCTAssertTrue(prepared.isRunning, "New server should be running")
        XCTAssertEqual(prepared.bindAddress, LocalProxyServer.BindAddress.any, "New server should be bound to .any")
        XCTAssertFalse(prepared === loopbackServer, "Should return a newly created server")
    }
}
