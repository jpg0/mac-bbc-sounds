import Foundation
import AVFoundation

class BBCProxyResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    private let proxyConfig: ProxyConfiguration?
    private let cacheManager = MediaCacheManager.shared
    private var _session: URLSession?
    private let processingQueue = DispatchQueue(label: "com.bbc-sounds.proxy-loader", qos: .userInitiated)
    private var prefetchingURLs = Set<URL>()
    var onProxyError: ((String) -> Void)?
    
    init(proxyConfig: ProxyConfiguration?) {
        self.proxyConfig = proxyConfig
        super.init()
    }
    
    private func getSession() -> URLSession {
        if let s = _session { return s }
        let config = URLSessionConfiguration.default
        if let proxy = proxyConfig {
            config.connectionProxyDictionary = [
                "HTTPEnable": 1,
                "HTTPProxy": proxy.host,
                "HTTPPort": proxy.port,
                "HTTPProxyUsername": proxy.user,
                "HTTPProxyPassword": proxy.pass
            ]
        }
        
        let operationQueue = OperationQueue()
        operationQueue.name = "com.bbc-sounds.proxy-session-queue"
        operationQueue.maxConcurrentOperationCount = 10
        
        let s = URLSession(configuration: config, delegate: self, delegateQueue: operationQueue)
        _session = s
        return s
    }
    
    public func getQueue() -> DispatchQueue {
        return processingQueue
    }
    
    private func logToFile(_ message: String) {
        print("🔍 [Proxy] \(message)")
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url else { return false }
        
        // Convert bbcproxy:// back to https://
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        guard let httpsURL = components?.url else { return false }
        
        logToFile("🔍 Resource Request: \(httpsURL.absoluteString)")
        
        // 1. Check Cache first
        if let cachedData = cacheManager.getCachedData(for: httpsURL) {
            var serveFromCacheFirst = false
            
            if httpsURL.pathExtension != "m3u8" {
                serveFromCacheFirst = true // Media segments are always static
            } else if let playlistString = String(data: cachedData, encoding: .utf8) {
                // Determine if the cached playlist is static (Master Playlist or VOD Variant)
                if playlistString.contains("#EXT-X-STREAM-INF") || 
                   playlistString.contains("#EXT-X-PLAYLIST-TYPE:VOD") || 
                   playlistString.contains("#EXT-X-ENDLIST") {
                    serveFromCacheFirst = true
                }
            }
            
            if serveFromCacheFirst {
                logToFile("📦 Cache Hit (Pre-Network): \(httpsURL.lastPathComponent)")
                
                if let contentRequest = loadingRequest.contentInformationRequest {
                    contentRequest.contentType = self.utiFromMimeType((httpsURL.pathExtension == "m3u8") ? "application/vnd.apple.mpegurl" : nil, url: httpsURL)
                    contentRequest.contentLength = Int64(cachedData.count)
                    contentRequest.isByteRangeAccessSupported = (httpsURL.pathExtension != "m3u8")
                }
                
                if let dataRequest = loadingRequest.dataRequest {
                    let start = Int(dataRequest.requestedOffset)
                    let length = Int(dataRequest.requestedLength)
                    if start < cachedData.count {
                        let end = min(start + length, cachedData.count)
                        dataRequest.respond(with: cachedData.subdata(in: start..<end))
                    }
                }
                
                loadingRequest.finishLoading()
                return true
            }
        }
        
        if let range = loadingRequest.dataRequest?.requestedOffset {
             logToFile("   -> Range Offset: \(range), Length: \(loadingRequest.dataRequest?.requestedLength ?? 0)")
        }
        
        var request = URLRequest(url: httpsURL)
        
        // Forward all headers from the original player request to the proxy
        if let originalHeaders = loadingRequest.request.allHTTPHeaderFields {
            for (key, value) in originalHeaders {
                // Skip 'Host' as it will be incorrectly pointing to bbcproxy scheme domain
                if key.lowercased() != "host" {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
        }
        
        // Ensure a modern User-Agent if not already set, to avoid proxy blocks
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        }
        
        // Log requested headers for verification
        if let reqHeaders = request.allHTTPHeaderFields {
             for (k, v) in reqHeaders {
                 logToFile("   >> Request Header [\(k)]: \(v)")
             }
        }

        let task = getSession().dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error as NSError? {
                self.logToFile("❌ Proxy Network Error [\(httpsURL.lastPathComponent)]: \(error.localizedDescription)")
                
                // OFFLINE FALLBACK
                if let cachedData = self.cacheManager.getCachedData(for: httpsURL) {
                    self.logToFile("♻️ Offline Fallback: Serving cached \(httpsURL.lastPathComponent)")
                    
                    if let contentRequest = loadingRequest.contentInformationRequest {
                        let uti = self.utiFromMimeType((httpsURL.pathExtension == "m3u8") ? "application/vnd.apple.mpegurl" : nil, url: httpsURL)
                        contentRequest.contentType = uti
                        contentRequest.contentLength = Int64(cachedData.count)
                        contentRequest.isByteRangeAccessSupported = (httpsURL.pathExtension != "m3u8")
                    }
                    
                    if let dataRequest = loadingRequest.dataRequest {
                        let start = Int(dataRequest.requestedOffset)
                        let length = Int(dataRequest.requestedLength)
                        if start < cachedData.count {
                            let end = min(start + length, cachedData.count)
                            dataRequest.respond(with: cachedData.subdata(in: start..<end))
                        }
                    }
                    loadingRequest.finishLoading()
                    return
                }
                
                loadingRequest.finishLoading(with: error)
                return
            }
            
            guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                self.logToFile("❌ Proxy Error: Invalid response for \(httpsURL.lastPathComponent)")
                loadingRequest.finishLoading(with: NSError(domain: "BBCProxy", code: -1))
                return
            }
            
            // Log full response headers for deep analysis
            let headers = httpResponse.allHeaderFields as? [String: Any] ?? [:]
            self.logToFile("📡 Proxy Response: \(httpResponse.statusCode) (\(data.count) bytes) - \(httpsURL.lastPathComponent)")
            for (key, value) in headers {
                self.logToFile("   -> Header [\(key)]: \(value)")
            }
            
            // Handle Redirects (301, 302, 303, 307, 308)
            if (300...399).contains(httpResponse.statusCode), let location = httpResponse.allHeaderFields["Location"] as? String, let nextURL = URL(string: location, relativeTo: httpsURL) {
                self.logToFile("🔀 Redirecting to: \(nextURL.absoluteString)")
                // Report the redirect to AVPlayer so it can handle it natively
                if let redirect = HTTPURLResponse(url: nextURL, statusCode: httpResponse.statusCode, httpVersion: "HTTP/1.1", headerFields: httpResponse.allHeaderFields as? [String: String]) {
                    loadingRequest.redirect = URLRequest(url: nextURL)
                    loadingRequest.response = redirect
                    loadingRequest.finishLoading() // This tells AVPlayer to follow the redirect
                    self.logToFile("✅ Reported redirect to AVPlayer")
                    return
                }
            }
                
            if data.count >= 8 {
                let magicBytes = data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
                self.logToFile("   -> Magic Bytes: [\(magicBytes)]")
            }
            
            if httpResponse.statusCode != 200 {
                let errorMsg = "BBC Proxy Error: \(httpResponse.statusCode) for \(httpsURL.lastPathComponent)"
                self.logToFile("❌ \(errorMsg)")
                
                // Try offline fallback for 4xx/5xx errors as well, just in case
                if let cachedData = self.cacheManager.getCachedData(for: httpsURL) {
                    self.logToFile("♻️ Offline Fallback (HTTP \(httpResponse.statusCode)): Serving cached \(httpsURL.lastPathComponent)")
                    if let contentRequest = loadingRequest.contentInformationRequest {
                        let uti = self.utiFromMimeType((httpsURL.pathExtension == "m3u8") ? "application/vnd.apple.mpegurl" : nil, url: httpsURL)
                        contentRequest.contentType = uti
                        contentRequest.contentLength = Int64(cachedData.count)
                        contentRequest.isByteRangeAccessSupported = (httpsURL.pathExtension != "m3u8")
                    }
                    if let dataRequest = loadingRequest.dataRequest {
                        let start = Int(dataRequest.requestedOffset)
                        let length = Int(dataRequest.requestedLength)
                        if start < cachedData.count {
                            let end = min(start + length, cachedData.count)
                            dataRequest.respond(with: cachedData.subdata(in: start..<end))
                        }
                    }
                    loadingRequest.finishLoading()
                    return
                }

                self.onProxyError?(errorMsg)
                loadingRequest.finishLoading(with: NSError(domain: "BBCProxy", code: httpResponse.statusCode))
                return
            }
            
            var responseData = data
            if httpsURL.pathExtension == "m3u8" {
                if let playlistString = String(data: data, encoding: .utf8) {
                    let rewritten = self.rewritePlaylist(playlistString, masterURL: httpsURL)
                    responseData = rewritten.data(using: .utf8) ?? data
                    self.logToFile("   -> Rewrote playlist (\(responseData.count) bytes)")
                    
                    // Cache the rewritten playlist so we can fall back to it offline
                    self.cacheManager.cacheData(responseData, for: httpsURL)
                    self.logToFile("💾 Cached playlist: \(httpsURL.lastPathComponent)")
                    
                    // If it's a VOD playlist, start pre-fetching segments
                    if rewritten.contains("#EXT-X-PLAYLIST-TYPE:VOD") {
                        self.logToFile("🎬 Detected VOD playlist. Starting background pre-fetch...")
                        self.prefetchSegments(rewritten, baseURL: httpsURL.deletingLastPathComponent())
                    }
                }
            } else {
                // Cache the segment
                self.cacheManager.cacheData(data, for: httpsURL)
                self.logToFile("💾 Cached segment: \(httpsURL.lastPathComponent)")
            }
            
            // 1. Set Content Information (MIME type and Length)
            if let contentRequest = loadingRequest.contentInformationRequest {
                let uti = self.utiFromMimeType(httpResponse.mimeType, url: httpsURL)
                contentRequest.contentType = uti
                contentRequest.contentLength = Int64(responseData.count) 
                contentRequest.isByteRangeAccessSupported = (httpsURL.pathExtension != "m3u8")
                self.logToFile("   -> Set ContentType: \(uti), Length: \(responseData.count), RangeSupport: \(contentRequest.isByteRangeAccessSupported)")
            }
            
            // 2. Set the HTTP Response Metadata
            if var headers = httpResponse.allHeaderFields as? [String: String] {
                let clashingHeaders = [
                    "Content-Encoding", "content-encoding",
                    "Content-Length", "content-length",
                    "Transfer-Encoding", "transfer-encoding",
                    "Content-Range", "content-range",
                    "Accept-Ranges", "accept-ranges",
                    "Connection", "connection",
                    "X-USP", "x-usp", "X-USP-Info1", "x-usp-info1"
                ]
                for header in clashingHeaders {
                    headers.removeValue(forKey: header)
                }
                
                if let proxyResponse = HTTPURLResponse(url: url, statusCode: httpResponse.statusCode, httpVersion: "HTTP/1.1", headerFields: headers) {
                    loadingRequest.response = proxyResponse
                }
            }
            
            // 3. Respond with Media Data
            if let dataRequest = loadingRequest.dataRequest {
                let start = Int(dataRequest.requestedOffset)
                let length = Int(dataRequest.requestedLength)
                
                if start < responseData.count {
                    let end = min(start + length, responseData.count)
                    let subdata = responseData.subdata(in: start..<end)
                    dataRequest.respond(with: subdata)
                    self.logToFile("   -> Responded with subdata: [\(start) - \(end)] of \(responseData.count)")
                } else {
                    self.logToFile("⚠️ Requested offset \(start) is beyond data size \(responseData.count)")
                }
            }
            
            // 4. Signal completion
            loadingRequest.finishLoading()
            self.logToFile("✅ Finished Loading: \(httpsURL.lastPathComponent)")
        }
        
        task.resume()
        return true
    }
    
    private func rewritePlaylist(_ playlist: String, masterURL: URL) -> String {
        let lines = playlist.components(separatedBy: .newlines)
        
        // 1. Identify playlist type
        let isMasterPlaylist = lines.contains { $0.contains("#EXT-X-STREAM-INF") }
        let isMediaPlaylist = lines.contains { $0.contains("#EXTINF") }
        
        // 2. Extract master security tokens
        let masterComponents = URLComponents(url: masterURL, resolvingAgainstBaseURL: false)
        let masterQueryItems = masterComponents?.queryItems ?? []
        
        var rewrittenLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#USP") }.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Force Upgrade HLS version to 3 for better modern AVPlayer support
            if trimmed.hasPrefix("#EXT-X-VERSION:") {
                return "#EXT-X-VERSION:3"
            }
            
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                return line
            }
            
            // For variant and segment lines, we should merge the master tokens
            guard let url = URL(string: trimmed, relativeTo: masterURL) else { return line }
            var comp = URLComponents(url: url, resolvingAgainstBaseURL: true)
            
            var currentQueryItems = comp?.queryItems ?? []
            for item in masterQueryItems {
                if !currentQueryItems.contains(where: { $0.name == item.name }) {
                    currentQueryItems.append(item)
                }
            }
            comp?.queryItems = currentQueryItems
            
            // We return a simplified absolute URL string for the player
            return comp?.url?.absoluteString ?? trimmed
        }
        
        // 3. Apply VOD tag ONLY to Media Playlists that are definitively finished
        // (Never add it to Master Playlists)
        if !isMasterPlaylist && isMediaPlaylist && !rewrittenLines.contains(where: { $0.contains("#EXT-X-PLAYLIST-TYPE") }) {
            if rewrittenLines.contains(where: { $0.contains("#EXT-X-ENDLIST") }) {
                if let index = rewrittenLines.firstIndex(where: { $0.hasPrefix("#EXT-X-VERSION") }) {
                    rewrittenLines.insert("#EXT-X-PLAYLIST-TYPE:VOD", at: index + 1)
                }
            }
        }
        
        return rewrittenLines.joined(separator: "\n")
    }
    
    private func utiFromMimeType(_ mimeType: String?, url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        
        if pathExtension == "m3u8" {
            return "com.apple.mpegurl"
        } else if pathExtension == "ts" {
            return "com.apple.mpegts" // Apple native UTI for MPEG-TS
        } else if pathExtension == "m4s" || pathExtension == "mp4" {
            return "public.mpeg-4"
        }
        
        switch mimeType?.lowercased() {
        case "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl":
            return "com.apple.mpegurl"
        case "video/mp2t", "audio/mp2t", "video/mpegts":
            return "com.apple.mpegts"
        case "audio/mp4", "video/mp4":
            return "public.mpeg-4"
        default:
            return "com.apple.mpegts" 
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == "NSURLAuthenticationMethodProxyBasic" {
            let credential = URLCredential(user: proxyConfig?.user ?? "", password: proxyConfig?.pass ?? "", persistence: .forSession)
            completionHandler(.useCredential, credential)
        } else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            // Only bypass if explicitly requested in config? For now handle default.
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    private func prefetchSegments(_ playlist: String, baseURL: URL) {
        let lines = playlist.components(separatedBy: .newlines)
        let segments = lines.filter { !$0.trimVariablePath().isEmpty && !$0.hasPrefix("#") }
        
        guard !prefetchingURLs.contains(baseURL) else { return }
        prefetchingURLs.insert(baseURL)
        
        Task.detached(priority: .background) { [weak self] in
            defer {
                Task { @MainActor in
                    self?.prefetchingURLs.remove(baseURL)
                }
            }
            guard let self = self else { return }
            for segment in segments {
                guard let segmentURL = URL(string: segment, relativeTo: baseURL) else { continue }
                
                // Check if already cached
                if MediaCacheManager.shared.getCachedData(for: segmentURL) != nil {
                    continue
                }
                
                print("🔄 Pre-fetching segment: \(segmentURL.lastPathComponent)")
                do {
                    let (data, _) = try await self.getSession().data(from: segmentURL)
                    MediaCacheManager.shared.cacheData(data, for: segmentURL)
                } catch {
                    print("⚠️ Pre-fetch failed for \(segmentURL.lastPathComponent): \(error)")
                }
                
                // Add a small delay to avoid saturating bandwidth
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            print("✅ Background pre-fetch complete.")
        }
    }
}

extension String {
    func trimVariablePath() -> String {
        return self.components(separatedBy: "?").first?.trimmingCharacters(in: .whitespaces) ?? self.trimmingCharacters(in: .whitespaces)
    }
}
