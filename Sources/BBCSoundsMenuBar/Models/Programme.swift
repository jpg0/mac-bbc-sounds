import Foundation

struct Programme: Identifiable, Equatable {
    let id: String          // BBC PID e.g. "m002q4mp"
    let index: Int
    let name: String        // Full show + episode title
    let channel: String     // e.g. "BBC Radio 3"
    let duration: String?   // e.g. "01:00:00"
    let description: String?
    let firstBroadcast: String?
    let artworkURL: String?
}
