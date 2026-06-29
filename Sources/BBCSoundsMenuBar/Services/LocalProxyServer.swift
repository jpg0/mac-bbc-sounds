import Foundation
import Network

/// A local HTTP server bound to 127.0.0.1 that proxies HLS playlist and segment
/// requests through the configured upstream proxy (e.g. NordVPN browser proxy).
///
/// AVPlayer cannot route through a custom URLProtocol for HLS segments, so instead
/// we present it with plain http://127.0.0.1:<port> URLs. The server fetches the
/// real content via `clientSession` (which carries proxy credentials) and returns it.
final class LocalProxyServer {

    // MARK: - Public

    /// The port the server is listening on. Valid only after `start()` succeeds.
    private(set) var port: UInt16 = 0

    /// The URLSession that carries proxy configuration. Use this to make requests
    /// that go through the upstream proxy (e.g. for tests or playlist pre-fetch).
    let clientSession: URLSession

    // MARK: - Private

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.trillica.LocalProxyServer", qos: .userInitiated)
    private let cache = MediaCacheManager.shared

    // MARK: - Init

    init(proxyConfig: ProxyConfiguration?) {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15

        if let cfg = proxyConfig {
            if #available(macOS 14.0, *) {
                let endpoint = NWEndpoint.hostPort(
                    host: NWEndpoint.Host(cfg.host),
                    port: NWEndpoint.Port(rawValue: UInt16(cfg.port)) ?? 89
                )
                let tlsOptions = NWProtocolTLS.Options()
                if cfg.skipVerify {
                    sec_protocol_options_set_verify_block(
                        tlsOptions.securityProtocolOptions,
                        { _, _, completion in completion(true) },
                        DispatchQueue.global()
                    )
                }
                let nwProxy = Network.ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: tlsOptions)
                nwProxy.applyCredential(username: cfg.user, password: cfg.pass)
                sessionConfig.proxyConfigurations = [nwProxy]
            } else {
                sessionConfig.connectionProxyDictionary = [
                    "HTTPEnable": 1,
                    "HTTPProxy": cfg.host,
                    "HTTPPort": cfg.port,
                    "HTTPProxyUsername": cfg.user,
                    "HTTPProxyPassword": cfg.pass,
                    "HTTPSEnable": 1,
                    "HTTPSProxy": cfg.host,
                    "HTTPSPort": cfg.port,
                    "HTTPSProxyUsername": cfg.user,
                    "HTTPSProxyPassword": cfg.pass
                ]
            }
            let delegate = BBCProxySessionDelegate(proxyConfig: cfg)
            self.clientSession = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        } else {
            self.clientSession = URLSession(configuration: sessionConfig)
        }
    }

    // MARK: - Lifecycle

    /// Start the listener and return the bound port number.
    @discardableResult
    func start() throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback

        let l = try NWListener(using: params, on: .any)
        self.listener = l

        let ready = DispatchGroup()
        ready.enter()

        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.port = l.port?.rawValue ?? 0
                ready.leave()
            case .failed(let err):
                print("⚠️ [LocalProxyServer] Listener failed: \(err)")
                ready.leave()
            default:
                break
            }
        }

        l.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }

        l.start(queue: queue)
        ready.wait()

        guard port > 0 else {
            throw NSError(domain: "LocalProxyServer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Listener failed to bind"])
        }

        print("🟢 [LocalProxyServer] Listening on 127.0.0.1:\(port)")
        return port
    }

    func stop() {
        listener?.cancel()
        listener = nil
        print("🔴 [LocalProxyServer] Stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(on: conn)
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, err in
            guard let self else { return }
            guard err == nil, let data else { conn.cancel(); return }
            self.processRequest(data: data, conn: conn)
        }
    }

    private func processRequest(data: Data, conn: NWConnection) {
        guard let text = String(data: data, encoding: .utf8) else {
            send(conn: conn, code: 400, body: Data("Bad Request".utf8))
            return
        }

        let lines = text.components(separatedBy: "\r\n")
        let requestParts = lines.first?.split(separator: " ", maxSplits: 2) ?? []
        guard requestParts.count >= 2 else {
            send(conn: conn, code: 400, body: Data("Bad Request".utf8))
            return
        }

        let method = String(requestParts[0])
        let rawPath = String(requestParts[1])

        guard method == "GET" || method == "HEAD" else {
            send(conn: conn, code: 405, body: Data("Method Not Allowed".utf8))
            return
        }

        // Parse ?url=<encoded-upstream-url> from the path
        guard let localURL = URL(string: "http://127.0.0.1\(rawPath)"),
              let comps = URLComponents(url: localURL, resolvingAgainstBaseURL: false),
              let encodedTarget = comps.queryItems?.first(where: { $0.name == "url" })?.value,
              let target = URL(string: encodedTarget) else {
            send(conn: conn, code: 400, body: Data("Missing or invalid ?url= parameter".utf8))
            return
        }

        var req = URLRequest(url: target)
        req.httpMethod = method

        // Forward Range and User-Agent headers
        for line in lines.dropFirst() {
            guard !line.isEmpty else { break }
            let headerParts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard headerParts.count == 2 else { continue }
            let name = headerParts[0].lowercased()
            if name == "range" || name == "user-agent" {
                req.setValue(headerParts[1], forHTTPHeaderField: headerParts[0])
            }
        }
        if req.value(forHTTPHeaderField: "User-Agent") == nil {
            req.setValue("Mozilla/5.0 (compatible; BBCSounds/1.0)", forHTTPHeaderField: "User-Agent")
        }

        print("⬇️ [LocalProxyServer] \(method) → \(target.absoluteString)")

        // Serve from cache for segments (not playlists — they are time-sensitive)
        let isSegment = !target.pathExtension.contains("m3u8") && !target.absoluteString.contains(".m3u8")
        if isSegment, let cached = cache.getCachedData(for: target) {
            print("📦 [LocalProxyServer] Cache hit: \(target.lastPathComponent)")
            send(conn: conn, code: 200, headers: ["Content-Length": "\(cached.count)",
                                                   "Content-Type": "video/MP2T"], body: cached)
            return
        }

        let task = clientSession.dataTask(with: req) { [weak self] responseData, response, error in
            guard let self else { return }

            if let error {
                print("❌ [LocalProxyServer] Fetch error: \(error.localizedDescription)")
                self.send(conn: conn, code: 502, body: Data("Bad Gateway: \(error.localizedDescription)".utf8))
                return
            }

            guard let http = response as? HTTPURLResponse, let responseData else {
                self.send(conn: conn, code: 502, body: Data("Bad Gateway".utf8))
                return
            }

            var body = responseData

            // Rewrite m3u8 playlists so segment URLs route back through this server
            if target.pathExtension == "m3u8" || target.absoluteString.contains(".m3u8"),
               let text = String(data: responseData, encoding: .utf8) {
                body = self.rewritePlaylist(text, masterURL: target).data(using: .utf8) ?? responseData
            } else {
                // Cache segments after a successful fetch
                self.cache.cacheData(responseData, for: target)
                print("💾 [LocalProxyServer] Cached: \(target.lastPathComponent) (\(responseData.count) bytes)")
            }

            // Strip hop-by-hop headers and set correct content-length
            var headers: [String: String] = [:]
            for (k, v) in http.allHeaderFields {
                guard let key = k as? String, let val = v as? String else { continue }
                let lower = key.lowercased()
                if lower == "transfer-encoding" || lower == "content-encoding" || lower == "content-length" { continue }
                headers[key] = val
            }
            headers["Content-Length"] = "\(body.count)"

            self.send(conn: conn, code: http.statusCode, headers: headers, body: body)
        }
        task.resume()
    }

    // MARK: - Playlist Rewriting

    private func rewritePlaylist(_ text: String, masterURL: URL) -> String {
        text.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Leave directives and blank lines alone
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return line }
            // Resolve relative or absolute segment/variant URLs
            guard let resolved = URL(string: trimmed, relativeTo: masterURL)?.absoluteURL else { return line }
            return localURL(for: resolved)
        }.joined(separator: "\n")
    }

    private func localURL(for upstream: URL) -> String {
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = "127.0.0.1"
        comps.port = Int(port)
        comps.path = "/segment"
        comps.queryItems = [URLQueryItem(name: "url", value: upstream.absoluteString)]
        return comps.url?.absoluteString ?? upstream.absoluteString
    }

    // MARK: - HTTP Response

    private func send(conn: NWConnection, code: Int, headers: [String: String] = [:], body: Data) {
        let phrase: String
        switch code {
        case 200: phrase = "OK"
        case 206: phrase = "Partial Content"
        case 400: phrase = "Bad Request"
        case 404: phrase = "Not Found"
        case 405: phrase = "Method Not Allowed"
        case 502: phrase = "Bad Gateway"
        default:  phrase = "Unknown"
        }

        var response = "HTTP/1.1 \(code) \(phrase)\r\n"
        for (key, val) in headers { response += "\(key): \(val)\r\n" }
        response += "\r\n"

        var packet = Data(response.utf8)
        packet.append(body)

        conn.send(content: packet, completion: .contentProcessed { _ in conn.cancel() })
    }
}


