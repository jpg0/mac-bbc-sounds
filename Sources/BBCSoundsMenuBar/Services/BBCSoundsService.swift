import Foundation

enum BBCSoundsError: LocalizedError {
    case invalidURL
    case noVPIDFound
    case noStreamFound
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL generated."
        case .noVPIDFound: return "Could not find a playable version for this programme."
        case .noStreamFound: return "No streaming URL found for this programme."
        case .apiError(let msg): return "BBC API error: \(msg)"
        }
    }
}

actor BBCSoundsService {
    private let session = URLSession.shared
    
    private func logToDebugFile(_ msg: String) {
        print(msg)
        let logURL = URL(fileURLWithPath: "/tmp/bbc_sounds_debug.log")
        if let data = "[\(Date())] 📡 [BBCSounds] \(msg)\n".data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
    
    // MARK: - Public API
    
    func search(query: String) async throws -> [Programme] {
        logToDebugFile("Searching for: \(query)")
        let escapedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://rms.api.bbc.co.uk/v2/experience/inline/search?q=\(escapedQuery)"
        
        guard let url = URL(string: urlString) else { throw BBCSoundsError.invalidURL }
        
        logToDebugFile("Requesting Search URL: \(urlString)")
        let data = try await request(url)
        logToDebugFile("Received Search Data (\(data.count) bytes)")
        let response: RMSSearchResponse
        do {
            response = try JSONDecoder().decode(RMSSearchResponse.self, from: data)
        } catch {
            print("❌ RMSSearchResponse Decoding Error: \(error)")
            throw error
        }
        
        var programmes: [Programme] = []
        for module in response.data {
            guard let items = module.data else { continue }
            for item in items {
                programmes.append(Programme(
                    id: item.id,
                    index: 0,
                    name: item.titles.primary,
                    channel: item.network?.short_title ?? "BBC",
                    duration: nil,
                    description: item.synopses?.short,
                    firstBroadcast: nil,
                    artworkURL: item.image_url?.replacingOccurrences(of: "{recipe}", with: "400x400")
                ))
            }
        }
        return programmes
    }
    
    func getProgramme(pid: String) async throws -> Programme {
        let urlString = "https://www.bbc.co.uk/programmes/\(pid).json"
        guard let url = URL(string: urlString) else { throw BBCSoundsError.invalidURL }
        
        let data: Data
        do {
            data = try await request(url)
        } catch {
            print("❌ Request failed for \(url): \(error)")
            throw error
        }
        
        let response: ProgrammeMetadataResponse
        do {
            response = try JSONDecoder().decode(ProgrammeMetadataResponse.self, from: data)
        } catch {
            if let string = String(data: data, encoding: .utf8) {
                print("❌ ProgrammeMetadataResponse Decoding Error: \(error)")
                print("📄 Raw Data (first 1000 chars):\n\(String(string.prefix(1000)))")
            }
            throw error
        }
        guard let prog = response.programme else { throw BBCSoundsError.noVPIDFound }
        
        return Programme(
            id: pid,
            index: 0,
            name: prog.title ?? "Unknown Programme",
            channel: prog.ownership?.service?.title ?? "BBC",
            duration: formatDuration(prog.versions?.first?.duration ?? 0),
            description: prog.short_synopsis,
            firstBroadcast: nil,
            artworkURL: prog.image?.pid != nil ? "https://ichef.bbci.co.uk/images/ic/400x400/\(prog.image!.pid!).jpg" : nil
        )
    }
    
    func getStreamURL(pid: String) async throws -> URL {
        logToDebugFile("Getting Stream URL for PID: \(pid)")
        
        // Step 1: Get VPID from programme metadata
        let vpid = try await fetchVPID(pid: pid)
        logToDebugFile("Resolved VPID: \(vpid)")
        
        // Step 2: Query Media Selector with fallbacks
        let mediasets = ["pc", "iptv-all", "mobile-cellular-main"]
        var lastError: Error?
        
        for mediaset in mediasets {
            let urlString = "https://open.live.bbc.co.uk/mediaselector/6/select/version/2.0/mediaset/\(mediaset)/vpid/\(vpid)/format/json"
            logToDebugFile("Attempting Mediaset: \(mediaset) via \(urlString)")
            
            guard let url = URL(string: urlString) else { continue }
            
            do {
                // IMPORTANT: Media Selector 6 returns 404 if a modern browser User-Agent is used.
                // We use nil here to fall back to a simple or no User-Agent.
                let data = try await request(url, userAgent: nil) 
                logToDebugFile("Received Media Selector Data for \(mediaset) (\(data.count) bytes)")
                
                let response = try JSONDecoder().decode(MediaSelectorResponse.self, from: data)
                
                // Step 3: Find HLS stream
                if let media = response.media {
                    for m in media {
                        if let connections = m.connection {
                            for conn in connections {
                                if conn.transferFormat == "hls", let streamURL = URL(string: conn.href) {
                                    logToDebugFile("✅ Found Streaming URL via \(mediaset): \(streamURL.absoluteString)")
                                    return streamURL
                                }
                            }
                        }
                    }
                }
                logToDebugFile("No HLS stream in \(mediaset) response.")
            } catch {
                logToDebugFile("❌ Mediaset \(mediaset) failed: \(error.localizedDescription)")
                lastError = error
            }
        }
        
        throw lastError ?? BBCSoundsError.noStreamFound
    }
    
    // MARK: - Private Helpers
    
    private func fetchVPID(pid: String) async throws -> String {
        let urlString = "https://www.bbc.co.uk/programmes/\(pid).json"
        guard let url = URL(string: urlString) else { throw BBCSoundsError.invalidURL }
        
        let data = try await request(url)
        let response: ProgrammeMetadataResponse
        do {
            response = try JSONDecoder().decode(ProgrammeMetadataResponse.self, from: data)
        } catch {
            print("❌ fetchVPID Decoding Error: \(error)")
            throw error
        }
        
        if let type = response.programme?.type, type == "brand" || type == "series" {
            logToDebugFile("PID \(pid) is a \(type). Fetching latest playable item...")
            let latestUrlStr = "https://rms.api.bbc.co.uk/v2/programmes/playable?container=\(pid)&sort=sequential&type=episode&experience=domestic"
            
            if let latestUrl = URL(string: latestUrlStr) {
                do {
                    let latestData = try await request(latestUrl)
                    let rmsResponse = try JSONDecoder().decode(RMSPlayableResponse.self, from: latestData)
                    if let playableVpid = rmsResponse.data?.first?.id {
                        logToDebugFile("✅ Found playable VPID: \(playableVpid) for container \(pid)")
                        return playableVpid
                    }
                } catch {
                    logToDebugFile("Failed to fetch playable info for container: \(error)")
                }
            }
        }

        
        if let vpid = response.programme?.versions?.first?.pid {
            logToDebugFile("Found VPID in versions: \(vpid)")
            return vpid
        }
        logToDebugFile("No VPID found in versions array for PID \(pid).")
        throw BBCSoundsError.noVPIDFound
    }
    
    private func formatDuration(_ seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func request(_ url: URL, userAgent: String? = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") async throws -> Data {
        var request = URLRequest(url: url)
        if let ua = userAgent {
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw BBCSoundsError.apiError("HTTP \(httpResponse.statusCode)")
        }
        return data
    }
}

// MARK: - API Models

struct RMSSearchResponse: Codable {
    let data: [RMSModule]
}

struct RMSModule: Codable {
    let data: [RMSItem]?
}

struct RMSItem: Codable {
    let id: String
    let titles: RMSTitles
    let synopses: RMSSynopses?
    let image_url: String?
    let network: RMSNetwork?
}

struct RMSTitles: Codable {
    let primary: String
}

struct RMSSynopses: Codable {
    let short: String?
}

struct RMSNetwork: Codable {
    let short_title: String?
}

struct ProgrammeMetadataResponse: Codable {
    let programme: ProgrammeInfo?
}

struct ProgrammeInfo: Codable {
    let type: String?
    let pid: String?
    let title: String?
    let short_synopsis: String?
    let image: ProgrammeImage?
    let ownership: ProgrammeOwnership?
    let versions: [ProgrammeVersion]?
}

struct ProgrammeImage: Codable {
    let pid: String?
}

struct ProgrammeOwnership: Codable {
    let service: ProgrammeService?
}

struct ProgrammeService: Codable {
    let title: String?
}

struct ProgrammeVersion: Codable {
    let pid: String?
    let duration: Int?
}

struct MediaSelectorResponse: Codable {
    let media: [MediaItem]?
}

struct MediaItem: Codable {
    let connection: [MediaConnection]?
}

struct MediaConnection: Codable {
    let transferFormat: String
    let href: String
}

// MARK: - RMS Playable Items

struct RMSPlayableResponse: Codable {
    let data: [RMSPlayableItem]?
}

struct RMSPlayableItem: Codable {
    let id: String?
}

