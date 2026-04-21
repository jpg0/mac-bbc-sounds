import Foundation

struct Programme: Identifiable, Equatable, Codable {
    let id: String          // BBC PID e.g. "m002q4mp"
    let index: Int
    let name: String        // Full show + episode title
    let channel: String     // e.g. "BBC Radio 3"
    let duration: String?   // e.g. "01:00:00"
    let description: String?
    let firstBroadcast: String?
    let artworkURL: String?
    let isLive: Bool
    
    var resolvedPID: String? = nil // Validated episode/version PID
    var durationInSeconds: Int = 0
}

struct Segment: Identifiable, Equatable, Codable {
    let id: String
    let artist: String
    let title: String
    let startTime: Int // offset in seconds
    let label: String?
    var isNowPlaying: Bool
}

