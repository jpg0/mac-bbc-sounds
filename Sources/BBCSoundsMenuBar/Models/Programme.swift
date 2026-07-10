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
}

struct Segment: Identifiable, Equatable, Codable {
    let id: String
    let artist: String
    let title: String
    let startTime: Int // offset in seconds
    let label: String?
    var isNowPlaying: Bool
}

