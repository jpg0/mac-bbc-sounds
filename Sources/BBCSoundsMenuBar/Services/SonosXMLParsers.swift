import Foundation

public enum SonosXMLError: LocalizedError {
    case invalidXML
    case missingRequiredField(String)

    public var errorDescription: String? {
        switch self {
        case .invalidXML:
            return "Failed to parse XML data."
        case .missingRequiredField(let field):
            return "Required XML field '\(field)' is missing."
        }
    }
}

// MARK: - UUID Normalization Helper

extension String {
    /// Strips leading "uuid:" prefix if present for Sonos UDNs / UUIDs
    public var normalizedSonosUUID: String {
        hasPrefix("uuid:") ? String(dropFirst(5)) : self
    }
}

// MARK: - Device Description

public struct SonosDeviceDescription: Equatable, Sendable {
    public let roomName: String
    public let displayName: String
    public let udn: String
    public let modelName: String?

    public init(roomName: String, displayName: String, udn: String, modelName: String?) {
        self.roomName = roomName
        self.displayName = displayName
        self.udn = udn
        self.modelName = modelName
    }
}

public enum SonosDeviceDescriptionParser {
    public static func parse(xmlData: Data) throws -> SonosDeviceDescription {
        let delegate = DeviceDescriptionXMLDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse() else {
            throw parser.parserError ?? SonosXMLError.invalidXML
        }

        guard let udn = delegate.udn, !udn.isEmpty else {
            throw SonosXMLError.missingRequiredField("UDN")
        }

        let room = delegate.roomName ?? delegate.displayName ?? delegate.friendlyName ?? "Sonos Speaker"
        let display = delegate.displayName ?? delegate.roomName ?? delegate.friendlyName ?? room

        return SonosDeviceDescription(
            roomName: room,
            displayName: display,
            udn: udn,
            modelName: delegate.modelName
        )
    }
}

private final class DeviceDescriptionXMLDelegate: NSObject, XMLParserDelegate {
    var roomName: String?
    var displayName: String?
    var friendlyName: String?
    var udn: String?
    var modelName: String?

    private var currentText: String = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "roomName":
            roomName = trimmed
        case "displayName":
            displayName = trimmed
        case "friendlyName":
            friendlyName = trimmed
        case "UDN":
            udn = trimmed
        case "modelName":
            modelName = trimmed
        default:
            break
        }
    }
}

// MARK: - Zone Topology

public struct SonosZoneMember: Equatable, Sendable {
    public let uuid: String
    public let location: URL?
    public let zoneName: String
    public let isZoneBridge: Bool
    public let isInvisible: Bool

    public init(uuid: String, location: URL?, zoneName: String, isZoneBridge: Bool = false, isInvisible: Bool = false) {
        self.uuid = uuid
        self.location = location
        self.zoneName = zoneName
        self.isZoneBridge = isZoneBridge
        self.isInvisible = isInvisible
    }

    public var normalizedUUID: String {
        uuid.normalizedSonosUUID
    }
}

public struct SonosZoneGroup: Equatable, Sendable {
    public let id: String
    public let coordinatorUUID: String
    public let members: [SonosZoneMember]

    public init(id: String, coordinatorUUID: String, members: [SonosZoneMember]) {
        self.id = id
        self.coordinatorUUID = coordinatorUUID
        self.members = members
    }

    public var normalizedCoordinatorUUID: String {
        coordinatorUUID.normalizedSonosUUID
    }

    public var audioMembers: [SonosZoneMember] {
        members.filter { !$0.isZoneBridge && !$0.isInvisible }
    }

    public var coordinatorMember: SonosZoneMember? {
        let target = normalizedCoordinatorUUID
        return members.first { $0.normalizedUUID == target }
    }

    public var groupName: String {
        let active = audioMembers
        guard !active.isEmpty else {
            return coordinatorMember?.zoneName ?? "Sonos Group"
        }

        let coord = coordinatorMember
        var names: [String] = []
        if let coord = coord, !coord.isZoneBridge && !coord.isInvisible {
            names.append(coord.zoneName)
        }
        for member in active {
            if member.normalizedUUID != coord?.normalizedUUID {
                names.append(member.zoneName)
            }
        }

        return names.isEmpty ? "Sonos Group" : names.joined(separator: " + ")
    }
}

public enum SonosTopologyParser {
    public static func parse(xmlData: Data) throws -> [SonosZoneGroup] {
        let delegate = TopologyXMLDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse() else {
            throw parser.parserError ?? SonosXMLError.invalidXML
        }

        return delegate.groups
    }
}

private final class TopologyXMLDelegate: NSObject, XMLParserDelegate {
    var groups: [SonosZoneGroup] = []

    private var currentGroupID: String?
    private var currentCoordinator: String?
    private var currentMembers: [SonosZoneMember] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "ZoneGroup" {
            currentGroupID = attributeDict["ID"]
            currentCoordinator = attributeDict["Coordinator"]
            currentMembers = []
        } else if elementName == "ZoneGroupMember" {
            let uuid = attributeDict["UUID"] ?? ""
            let locString = attributeDict["Location"] ?? ""
            let location = URL(string: locString)
            let zoneName = attributeDict["ZoneName"] ?? "Sonos"
            let isBridge = attributeDict["IsZoneBridge"] == "1"
            let isInvisible = attributeDict["Invisible"] == "1"

            if !uuid.isEmpty {
                let member = SonosZoneMember(
                    uuid: uuid,
                    location: location,
                    zoneName: zoneName,
                    isZoneBridge: isBridge,
                    isInvisible: isInvisible
                )
                currentMembers.append(member)
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "ZoneGroup" {
            if let groupID = currentGroupID, let coordinator = currentCoordinator {
                let group = SonosZoneGroup(id: groupID, coordinatorUUID: coordinator, members: currentMembers)
                groups.append(group)
            }
            currentGroupID = nil
            currentCoordinator = nil
            currentMembers = []
        }
    }
}
