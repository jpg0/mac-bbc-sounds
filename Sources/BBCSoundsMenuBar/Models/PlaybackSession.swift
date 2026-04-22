import Foundation

struct PlaybackSession: Codable {
    let programme: Programme
    let time: Double
    let duration: Double?
    let date: Date
}
