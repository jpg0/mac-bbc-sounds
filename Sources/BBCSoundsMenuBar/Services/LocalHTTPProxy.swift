import Foundation
import Network

class LocalHTTPProxy {
    private let proxyConfig: ProxyConfiguration
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.bbc-sounds.local-proxy")
    private var session: URLSession!
    
    var port: UInt16? {
        return listener?.port?.rawValue
    }
    
    init(proxyConfig: ProxyConfiguration) {
        self.proxyConfig = proxyConfig
        setupSession()
    }
    
    private func setupSession() {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [
            "HTTPEnable": 1,
            "HTTPProxy": proxyConfig.host,
            "HTTPPort": proxyConfig.port,
            "HTTPProxyUsername": proxyConfig.user,
            "HTTPProxyPassword": proxyConfig.pass
        ]
        session = URLSession(configuration: config)
    }
    
    func start() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        
        let semaphore = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            print("🚀 Local Proxy State: \(state)")
            if case .ready = state {
                semaphore.signal()
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        
        listener.start(queue: queue)
        
        // Wait up to 2 seconds for the listener to become ready and assign a port
        _ = semaphore.wait(timeout: .now() + 2.0)
        
        if let assignedPort = listener.port {
            print("🚀 Local Proxy successfully bound to port \(assignedPort.rawValue)")
        } else {
            print("❌ Local Proxy failed to bind to a port within timeout.")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveData(from: connection)
    }
    
    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }
            
            if let requestString = String(data: data, encoding: .utf8) {
                self.processRequest(requestString, connection: connection)
            }
        }
    }
    
    private func processRequest(_ request: String, connection: NWConnection) {
        let lines = request.components(separatedBy: .newlines)
        guard let firstLine = lines.first else {
            connection.cancel()
            return
        }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendResponse(status: "405 Method Not Allowed", body: "Only GET supported".data(using: .utf8)!, connection: connection)
            return
        }
        
        let rawPath = parts[1]
        guard let url = URL(string: "http://localhost" + rawPath),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let targetEncoded = components.queryItems?.first(where: { $0.name == "target" })?.value,
              let targetURL = URL(string: targetEncoded) else {
            sendResponse(status: "400 Bad Request", body: "Missing target parameter".data(using: .utf8)!, connection: connection)
            return
        }
        
        logToFile("📡 Local Proxy Requesting: \(targetURL.absoluteString)")
        
        // Forward headers (like Range)
        var forwardRequest = URLRequest(url: targetURL)
        for line in lines.dropFirst() {
            let parts = line.components(separatedBy: ": ")
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                if !["host", "connection", "user-agent"].contains(key.lowercased()) {
                    forwardRequest.setValue(value, forHTTPHeaderField: key)
                }
            }
        }
        forwardRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: forwardRequest) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.sendResponse(status: "502 Bad Gateway", body: error.localizedDescription.data(using: .utf8)!, connection: connection)
                return
            }
            
            guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                self.sendResponse(status: "500 Internal Server Error", body: "Invalid proxy response".data(using: .utf8)!, connection: connection)
                return
            }
            
            var responseData = data
            if targetURL.pathExtension == "m3u8", let playlist = String(data: data, encoding: .utf8) {
                responseData = self.rewritePlaylist(playlist, targetURL: targetURL).data(using: .utf8) ?? data
            }
            
            self.sendProxyResponse(httpResponse: httpResponse, data: responseData, connection: connection)
        }
        task.resume()
    }
    
    private func rewritePlaylist(_ playlist: String, targetURL: URL) -> String {
        let lines = playlist.components(separatedBy: .newlines)
        let masterComponents = URLComponents(url: targetURL, resolvingAgainstBaseURL: false)
        let masterQueryItems = masterComponents?.queryItems ?? []
        let port = self.port ?? 0
        
        let rewrittenLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#USP") }.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#EXT-X-VERSION:") { return "#EXT-X-VERSION:3" }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return line }
            
            guard let url = URL(string: trimmed, relativeTo: targetURL) else { return line }
            var comp = URLComponents(url: url, resolvingAgainstBaseURL: true)
            
            // Merge security tokens
            var currentQueryItems = comp?.queryItems ?? []
            for item in masterQueryItems {
                if !currentQueryItems.contains(where: { $0.name == item.name }) {
                    currentQueryItems.append(item)
                }
            }
            comp?.queryItems = currentQueryItems
            
            if let finalURL = comp?.url {
                let encodedTarget = finalURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                return "http://127.0.0.1:\(port)/proxy?target=\(encodedTarget)"
            }
            return line
        }
        
        var finalLines = rewrittenLines
        if !finalLines.contains(where: { $0.contains("#EXT-X-PLAYLIST-TYPE") }) {
            if let index = finalLines.firstIndex(where: { $0.hasPrefix("#EXT-X-VERSION") }) {
                finalLines.insert("#EXT-X-PLAYLIST-TYPE:VOD", at: index + 1)
            }
        }
        
        return finalLines.joined(separator: "\n")
    }
    
    private func sendProxyResponse(httpResponse: HTTPURLResponse, data: Data, connection: NWConnection) {
        var response = "HTTP/1.1 \(httpResponse.statusCode) OK\r\n"
        let clashingHeaders = [
            "content-encoding", "content-length", "transfer-encoding", 
            "content-range", "accept-ranges", "connection", "server", "x-usp"
        ]
        
        for (key, value) in httpResponse.allHeaderFields {
            let sKey = "\(key)".lowercased()
            if !clashingHeaders.contains(where: { sKey.contains($0) }) {
                response += "\(key): \(value)\r\n"
            }
        }
        
        response += "Content-Length: \(data.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"
        
        guard let headerData = response.data(using: .utf8) else {
            connection.cancel()
            return
        }
        
        connection.send(content: headerData + data, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func sendResponse(status: String, body: Data, connection: NWConnection) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        if let headerData = response.data(using: .utf8) {
            connection.send(content: headerData + body, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        } else {
            connection.cancel()
        }
    }
    
    private func logToFile(_ message: String) {
        let logMessage = "[\(Date())] [LocalProxy] \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            let logURL = URL(fileURLWithPath: "/tmp/bbc_sounds_debug.log")
            if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
