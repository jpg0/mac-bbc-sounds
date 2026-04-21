import Foundation

func formatTime(_ seconds: Double) -> String {
    guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
    let h = Int(seconds) / 3600
    let m = (Int(seconds) % 3600) / 60
    let s = Int(seconds) % 60
    
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%02d:%02d", m, s)
}
