import Foundation

/// Represents a discovered Sonos zone player or room on the local network.
public struct SonosDevice: Identifiable, Hashable, Equatable, Sendable {
    /// Unique Device Name / UDN (e.g. "uuid:RINCON_000E5800000001400" or "RINCON_000E5800000001400")
    public let id: String

    /// Friendly room name (e.g. "Living Room")
    public let name: String

    /// IP address of the speaker
    public let ipAddress: String

    /// Port of the speaker UPnP service (typically 1400)
    public let port: UInt16

    /// Device hardware model name (e.g. "Sonos One")
    public let modelName: String?

    /// Whether this speaker is the coordinator of its zone group
    public let isCoordinator: Bool

    /// Sonos ZoneGroup ID it belongs to (e.g. "RINCON_000E5800000001400:1")
    public let groupId: String?

    /// Combined display name for grouped rooms (e.g. "Living Room + Kitchen"), or nil if not grouped
    public let groupName: String?

    /// UUID of the group coordinator (without "uuid:" prefix)
    public let coordinatorUUID: String?

    /// IP address of the coordinator to send transport commands to
    public let coordinatorIP: String?

    /// Port of the coordinator (typically 1400)
    public let coordinatorPort: UInt16?

    /// Names of other zone members in the group (excluding coordinator)
    public let memberNames: [String]

    public init(
        id: String,
        name: String,
        ipAddress: String,
        port: UInt16 = 1400,
        modelName: String? = nil,
        isCoordinator: Bool = true,
        groupId: String? = nil,
        groupName: String? = nil,
        coordinatorUUID: String? = nil,
        coordinatorIP: String? = nil,
        coordinatorPort: UInt16? = nil,
        memberNames: [String] = []
    ) {
        self.id = id.normalizedSonosUUID
        self.name = name
        self.ipAddress = ipAddress
        self.port = port
        self.modelName = modelName
        self.isCoordinator = isCoordinator
        self.groupId = groupId
        self.groupName = groupName
        let normCoordUUID = coordinatorUUID?.normalizedSonosUUID ?? (isCoordinator ? self.id : nil)
        self.coordinatorUUID = normCoordUUID
        self.coordinatorIP = coordinatorIP ?? (isCoordinator ? ipAddress : nil)
        self.coordinatorPort = coordinatorPort ?? (isCoordinator ? port : nil)
        self.memberNames = memberNames
    }

    /// Display title: uses combined group name if available, otherwise room name
    public var displayName: String {
        groupName ?? name
    }

    /// Formatted group badge text if device is part of a multi-speaker group, e.g. "(+ Kitchen)"
    public var groupBadge: String? {
        if !memberNames.isEmpty {
            return "(+ \(memberNames.joined(separator: ", ")))"
        }
        guard let groupName = groupName, groupName != name else { return nil }
        let members = groupName.components(separatedBy: " + ").filter { $0 != name }
        guard !members.isEmpty else { return nil }
        return "(+ \(members.joined(separator: ", ")))"
    }

    /// Base URL for this individual speaker's HTTP/UPnP endpoints
    public var baseURL: URL? {
        URL(string: "http://\(ipAddress):\(port)")
    }

    /// Base URL for the group coordinator (where AVTransport commands must be sent)
    public var coordinatorBaseURL: URL? {
        if let coordinatorIP = coordinatorIP, let coordinatorPort = coordinatorPort {
            return URL(string: "http://\(coordinatorIP):\(coordinatorPort)")
        }
        return baseURL
    }

    /// Control URL for the AVTransport service on the group coordinator
    public var avTransportControlURL: URL? {
        guard let base = coordinatorBaseURL else { return nil }
        let baseStr = base.absoluteString.hasSuffix("/") ? String(base.absoluteString.dropLast()) : base.absoluteString
        return URL(string: "\(baseStr)/MediaRenderer/AVTransport/Control")
    }

    /// Control URL for the RenderingControl service on this individual speaker
    public var renderingControlURL: URL? {
        guard let base = baseURL else { return nil }
        let baseStr = base.absoluteString.hasSuffix("/") ? String(base.absoluteString.dropLast()) : base.absoluteString
        return URL(string: "\(baseStr)/MediaRenderer/RenderingControl/Control")
    }
}
