import Foundation

/// UPnP AVTransport playback states reported by Sonos.
public enum SonosTransportState: String, Sendable, Equatable {
    case playing = "PLAYING"
    case paused = "PAUSED_PLAYBACK"
    case stopped = "STOPPED"
    case transitioning = "TRANSITIONING"
    case unknown = "UNKNOWN"

    public init(fromRaw: String) {
        let upper = fromRaw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch upper {
        case "PLAYING":
            self = .playing
        case "PAUSED_PLAYBACK", "PAUSED":
            self = .paused
        case "STOPPED":
            self = .stopped
        case "TRANSITIONING":
            self = .transitioning
        default:
            self = .unknown
        }
    }
}

/// Transport info representing the current status and speed of playback on Sonos.
public struct SonosTransportInfo: Equatable, Sendable {
    public let state: SonosTransportState
    public let status: String
    public let speed: String

    public init(
        state: SonosTransportState = .stopped,
        status: String = "OK",
        speed: String = "1"
    ) {
        self.state = state
        self.status = status
        self.speed = speed
    }
}

/// Playback position information reported by AVTransport GetPositionInfo.
public struct SonosPositionInfo: Equatable, Sendable {
    public let trackDuration: TimeInterval
    public let trackRelTime: TimeInterval
    public let rawTrackDuration: String
    public let rawRelTime: String
    public let trackURI: String?

    public static let zero = SonosPositionInfo(
        trackDuration: 0,
        trackRelTime: 0,
        rawTrackDuration: "00:00:00",
        rawRelTime: "00:00:00",
        trackURI: nil
    )

    public init(
        trackDuration: TimeInterval,
        trackRelTime: TimeInterval,
        rawTrackDuration: String,
        rawRelTime: String,
        trackURI: String? = nil
    ) {
        self.trackDuration = trackDuration
        self.trackRelTime = trackRelTime
        self.rawTrackDuration = rawTrackDuration
        self.rawRelTime = rawRelTime
        self.trackURI = trackURI
    }

    /// Convenience initializer parsing raw UPnP time strings (HH:MM:SS).
    public init(
        rawTrackDuration: String,
        rawRelTime: String,
        trackURI: String? = nil
    ) {
        self.rawTrackDuration = rawTrackDuration
        self.rawRelTime = rawRelTime
        self.trackDuration = Self.parseTimeInterval(rawTrackDuration)
        self.trackRelTime = Self.parseTimeInterval(rawRelTime)
        self.trackURI = trackURI
    }

    /// Parses a UPnP timestamp string ("HH:MM:SS" or "HH:MM:SS.mmm") into seconds.
    public static func parseTimeInterval(_ string: String) -> TimeInterval {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != "NOT_IMPLEMENTED",
              trimmed != "0",
              !trimmed.hasPrefix("-") else {
            return 0
        }

        let parts = trimmed.split(separator: ":")
        guard parts.count == 3 else { return 0 }

        guard let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return 0
        }

        return (hours * 3600.0) + (minutes * 60.0) + seconds
    }

    /// Formats a time interval in seconds into UPnP "HH:MM:SS" timestamp string.
    public static func formatTimeInterval(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "00:00:00" }
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}
