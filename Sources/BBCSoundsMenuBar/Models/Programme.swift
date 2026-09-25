import Foundation

struct Programme: Identifiable, Equatable, Codable {
    let id: String          // BBC PID e.g. "m002q4mp"
    let index: Int
    let name: String        // Full show + episode title
    let channel: String     // e.g. "BBC Radio 3"
    let duration: String?   // e.g. "01:00:00"
    let description: String?
    let firstBroadcast: String?
    var artworkURL: String?
    let isLive: Bool
    
    var resolvedPID: String? = nil // Validated episode/version PID
    var durationInSeconds: Int = 0
    
    // New Fields for Search & Played Status
    var type: String? = nil                     // "brand", "series", "episode", or "live"
    var releaseLabel: String? = nil             // e.g. "27 Jun 2026"
    var latestEpisodePID: String? = nil         // Episode PID for containers
    var latestEpisodeVPID: String? = nil        // Version PID (VPID) for containers
    var latestEpisodeTitle: String? = nil       // Subtitle/title for latest episode
    var latestEpisodeReleaseLabel: String? = nil // Date label for latest episode
    var latestEpisodeDuration: String? = nil    // Duration label for latest episode

    var effectiveDurationInSeconds: Double {
        guard !isLive else { return 0 }
        if durationInSeconds > 0 {
            return Double(durationInSeconds)
        }
        guard let dur = duration?.trimmingCharacters(in: .whitespacesAndNewlines), !dur.isEmpty else {
            return 0
        }
        // Format 1: HH:MM:SS or MM:SS
        let parts = dur.split(separator: ":").compactMap { Double($0) }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        } else if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        // Format 2: "1 hr 30 mins", "57 mins", etc.
        var total: Double = 0
        if let hrRange = dur.range(of: "hr") {
            let hrPart = dur[..<hrRange.lowerBound].trimmingCharacters(in: .whitespaces)
            if let last = hrPart.components(separatedBy: .whitespaces).last, let hrs = Double(last) {
                total += hrs * 3600
            }
        }
        if let minRange = dur.range(of: "min") {
            let beforeMin = dur[..<minRange.lowerBound]
            if let last = beforeMin.components(separatedBy: .whitespaces).filter({ !$0.isEmpty }).last, let mins = Double(last) {
                total += mins * 60
            }
        }
        return total
    }
}

struct Segment: Identifiable, Equatable, Codable {
    let id: String
    let artist: String
    let title: String
    let startTime: Int // offset in seconds
    let label: String?
    var isNowPlaying: Bool
}

