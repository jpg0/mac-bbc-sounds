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
        print("📡 [BBCSounds] \(msg)")
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
                let isLive = item.type == "live_search_result_item"
                let id = isLive ? (item.now?.service_id ?? item.id) : item.id
                let name = item.titles?.primary ?? item.now?.station_name ?? "Unknown"
                let description = item.synopses?.short ?? item.now?.short_synopsis
                let artworkURL = (item.image_url ?? item.now?.episode_image_url)?
                    .replacingOccurrences(of: "{recipe}", with: "400x400")
                
                programmes.append(Programme(
                    id: id,
                    index: 0,
                    name: name,
                    channel: item.network?.short_title ?? item.now?.station_name ?? "BBC",
                    duration: nil,
                    description: description,
                    firstBroadcast: nil,
                    artworkURL: artworkURL,
                    isLive: isLive
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
        guard let prog = response.programme ?? response.version?.parent?.programme else { throw BBCSoundsError.noVPIDFound }
        
        let duration = prog.versions?.first?.duration ?? response.version?.duration ?? 0
        
        var programme = Programme(
            id: pid,
            index: 0,
            name: prog.title ?? "Unknown Programme",
            channel: prog.ownership?.service?.title ?? "BBC",
            duration: formatDuration(duration),
            description: prog.short_synopsis,
            firstBroadcast: nil,
            artworkURL: prog.image?.pid != nil ? "https://ichef.bbci.co.uk/images/ic/400x400/\(prog.image!.pid!).jpg" : nil,
            isLive: prog.type == "station" || prog.type == "masterbrand"
        )
        programme.durationInSeconds = duration
        return programme
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
    
    // Returns both the URL and the actual Episode/Version PID resolved
    func resolveStream(pid: String) async throws -> (URL, String) {
        let vpid = try await fetchVPID(pid: pid)
        let url = try await getStreamURL(pid: pid)
        return (url, vpid)
    }
    
    func fetchSegments(pid: String, isLive: Bool) async throws -> [Segment] {
        let urlString: String
        if isLive {
            urlString = "https://rms.api.bbc.co.uk/v2/services/\(pid)/segments/latest?experience=domestic&limit=10"
        } else {
            urlString = "https://rms.api.bbc.co.uk/v2/programmes/\(pid)/segments?experience=domestic"
        }
        
        guard let url = URL(string: urlString) else { throw BBCSoundsError.invalidURL }
        
        do {
            let data = try await request(url)
            let response = try JSONDecoder().decode(RMSSegmentResponse.self, from: data)
            let segments = response.data.compactMap { item -> Segment? in
                guard item.segment_type == "music" || item.type == "segment_item" else { return nil }
                return Segment(
                    id: item.id,
                    artist: item.titles.primary,
                    title: item.titles.secondary ?? "Unknown",
                    startTime: item.offset.start,
                    label: item.offset.label,
                    isNowPlaying: item.offset.now_playing ?? false
                )
            }
            
            if !segments.isEmpty || isLive {
                return segments
            }
        } catch {
            logToDebugFile("RMS Segments failed for \(pid): \(error.localizedDescription)")
        }
        
        // Fallback for on-demand episodes where RMS is empty
        if !isLive {
            logToDebugFile("Attempting fallback segments for \(pid)")
            return (try? await fetchSegmentsFallback(pid: pid)) ?? []
        }
        
        return []
    }
    
    private func fetchSegmentsFallback(pid: String) async throws -> [Segment] {
        let urlString = "https://www.bbc.co.uk/programmes/\(pid)/segments.json"
        guard let url = URL(string: urlString) else { throw BBCSoundsError.invalidURL }
        
        let data = try await request(url)
        let response = try JSONDecoder().decode(ProgrammesSegmentResponse.self, from: data)
        
        return response.segment_events.compactMap { event in
            guard let seg = event.segment, (seg.type == "music" || seg.artist != nil) else { return nil }
            return Segment(
                id: event.pid,
                artist: seg.artist ?? "Unknown Artist",
                title: seg.track_title ?? seg.title ?? "Unknown Track",
                startTime: event.version_offset,
                label: nil,
                isNowPlaying: false
            )
        }
    }
    
    // MARK: - Private Helpers
    
    private func fetchVPID(pid: String) async throws -> String {
        // Live station fallback: service IDs like bbc_radio_one are their own VPID
        if pid.hasPrefix("bbc_") || pid.contains("radio") {
            logToDebugFile("PID \(pid) looks like a live service, using as VPID.")
            return pid
        }

        let urlString = "https://www.bbc.co.uk/programmes/\(pid).json"
        guard let url = URL(string: urlString) else { throw BBCSoundsError.invalidURL }
        
        let data: Data
        do {
            data = try await request(url)
        } catch {
            logToDebugFile("Metadata request failed for \(pid) (\(error.localizedDescription)). Using PID as fallback VPID.")
            return pid
        }

        let response: ProgrammeMetadataResponse
        do {
            response = try JSONDecoder().decode(ProgrammeMetadataResponse.self, from: data)
        } catch {
            logToDebugFile("Decoding failed for \(pid), using as fallback VPID.")
            return pid
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
                        // Recursively resolve the playable item (it might be an episode or a version)
                        return try await fetchVPID(pid: playableVpid)
                    }
                } catch {
                    logToDebugFile("Failed to fetch playable info for container: \(error)")
                }
            }
        }

        if let vpid = response.version?.pid {
            logToDebugFile("Found VPID in version root: \(vpid)")
            return vpid
        }

        if let vpid = response.programme?.versions?.first?.pid {
            logToDebugFile("Found VPID in versions: \(vpid)")
            return vpid
        }

        logToDebugFile("No explicit VPID found for PID \(pid), falling back to PID itself.")
        return pid
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
    let type: String?
    let titles: RMSTitles?
    let synopses: RMSSynopses?
    let image_url: String?
    let network: RMSNetwork?
    let now: RMSNow?
}

struct RMSNow: Codable {
    let service_id: String?
    let station_name: String?
    let title: String?
    let short_synopsis: String?
    let episode_image_url: String?
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
    let version: ProgrammeVersionInfo?
}

struct ProgrammeVersionInfo: Codable {
    let pid: String?
    let duration: Int?
    let parent: ProgrammeParent?
}

struct ProgrammeParent: Codable {
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

// MARK: - RMS Segments

struct RMSSegmentResponse: Codable {
    let data: [RMSSegmentItem]
}

struct RMSSegmentItem: Codable {
    let type: String
    let id: String
    let segment_type: String?
    let titles: RMSSegmentTitles
    let offset: RMSSegmentOffset
}

struct RMSSegmentTitles: Codable {
    let primary: String
    let secondary: String?
}

struct RMSSegmentOffset: Codable {
    let start: Int
    let label: String?
    let now_playing: Bool?
}

// MARK: - Older Programmes API Segments

struct ProgrammesSegmentResponse: Codable {
    let segment_events: [ProgrammesSegmentEvent]
}

struct ProgrammesSegmentEvent: Codable {
    let pid: String
    let version_offset: Int
    let segment: ProgrammesSegmentData?
}

struct ProgrammesSegmentData: Codable {
    let type: String?
    let artist: String?
    let track_title: String?
    let title: String?
    let duration: Int?
}

