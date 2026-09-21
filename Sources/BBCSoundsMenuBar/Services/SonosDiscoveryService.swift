import Foundation
import Combine
import SSDPClient

/// Service responsible for SSDP multicast discovery of Sonos speakers on the local network,
/// topology resolution, and exposing an observable list of discovered rooms and groups.
@MainActor
public final class SonosDiscoveryService: NSObject, ObservableObject {

    // MARK: - Constants

    public static let zonePlayerSearchTarget = "urn:schemas-upnp-org:device:ZonePlayer:1"

    // MARK: - Published Properties

    /// Discovered playable Sonos targets (group coordinators and standalone rooms)
    @Published public private(set) var discoveredDevices: [SonosDevice] = []

    /// All discovered individual zone player devices (including group slave members)
    @Published public private(set) var allZoneDevices: [SonosDevice] = []

    /// Whether an SSDP discovery scan is actively in progress
    @Published public private(set) var isScanning: Bool = false

    // MARK: - Dependencies & State

    private let discoveryClient: SSDPDiscovery
    private let session: URLSession
    private var scanTimer: Timer?
    private var knownDescriptions: [String: SonosDeviceDescription] = [:]
    private var deviceLastSeen: [String: Date] = [:]

    /// Maximum duration (in seconds) a speaker remains in discoveredDevices without being re-seen.
    public var deviceTTL: TimeInterval = 180

    // MARK: - Init

    public init(discoveryClient: SSDPDiscovery = SSDPDiscovery(), session: URLSession = .shared) {
        self.discoveryClient = discoveryClient
        self.session = session
        super.init()
        self.discoveryClient.delegate = self
    }

    deinit {
        scanTimer?.invalidate()
        discoveryClient.stop()
    }

    // MARK: - Discovery Controls

    /// Starts periodic SSDP discovery scans.
    public func startDiscovery(interval: TimeInterval = 60) {
        scan()
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scan()
            }
        }
    }

    /// Stops discovery scans and cancels pending timers.
    public func stopDiscovery() {
        scanTimer?.invalidate()
        scanTimer = nil
        discoveryClient.stop()
        isScanning = false
    }

    /// Triggers an immediate SSDP discovery scan and prunes expired devices.
    public func scan(duration: TimeInterval = 5) {
        pruneStaleDevices()
        guard !isScanning else { return }
        isScanning = true
        discoveryClient.discoverService(forDuration: duration, searchTarget: Self.zonePlayerSearchTarget, port: 1900)
    }

    /// Prunes any discovered speakers that have not been seen within the TTL duration.
    public func pruneStaleDevices(olderThan maxAge: TimeInterval? = nil) {
        let ttl = maxAge ?? deviceTTL
        let cutoff = Date().addingTimeInterval(-ttl)

        var changed = false
        let filteredCoordinators = discoveredDevices.filter { device in
            if let seen = deviceLastSeen[device.id], seen < cutoff {
                changed = true
                return false
            }
            return true
        }

        if changed {
            self.discoveredDevices = filteredCoordinators
            self.allZoneDevices = allZoneDevices.filter { device in
                if let seen = deviceLastSeen[device.id], seen < cutoff {
                    return false
                }
                return true
            }
        }
    }

    // MARK: - Location & Topology Processing

    /// Fetches device description and topology from a discovered UPnP location URL.
    public func processDiscoveredLocation(_ locationURL: URL) async {
        guard let host = locationURL.host else { return }
        let port = UInt16(locationURL.port ?? 1400)

        // 1. Fetch and parse device description
        var description: SonosDeviceDescription?
        do {
            let (descData, _) = try await session.data(from: locationURL)
            let desc = try SonosDeviceDescriptionParser.parse(xmlData: descData)
            description = desc
            let normalizedUDN = desc.udn.normalizedSonosUUID
            knownDescriptions[normalizedUDN] = desc
            knownDescriptions[host] = desc
        } catch {
            print("⚠️ [SonosDiscoveryService] Failed to fetch device description from \(locationURL): \(error)")
        }

        // 2. Fetch and parse zone topology
        guard let topologyURL = URL(string: "http://\(host):\(port)/status/topology") else { return }
        do {
            let (topoData, _) = try await session.data(from: topologyURL)
            let groups = try SonosTopologyParser.parse(xmlData: topoData)
            updateDevices(with: groups, fallbackHost: host, fallbackPort: port, currentDesc: description)
        } catch {
            print("⚠️ [SonosDiscoveryService] Failed to fetch topology from \(topologyURL): \(error)")
            // If topology fails but we have a description, expose the single device
            if let desc = description {
                handleSingleDeviceFallback(desc: desc, host: host, port: port)
            }
        }
    }

    private func updateDevices(
        with groups: [SonosZoneGroup],
        fallbackHost: String,
        fallbackPort: UInt16,
        currentDesc: SonosDeviceDescription?
    ) {
        let now = Date()
        var newCoordinators: [SonosDevice] = []
        var newMembers: [SonosDevice] = []

        for group in groups {
            guard let coordinator = group.coordinatorMember else { continue }
            let coordUUID = group.normalizedCoordinatorUUID
            let coordHost = coordinator.location?.host ?? fallbackHost
            let coordPort = UInt16(coordinator.location?.port ?? Int(fallbackPort))

            let isGrouped = group.audioMembers.count > 1
            let groupDisplayName = isGrouped ? group.groupName : nil

            let coordinatorModel = knownDescriptions[coordUUID]?.modelName ??
                (coordUUID == currentDesc?.udn.normalizedSonosUUID ? currentDesc?.modelName : nil)

            let coordinatorDevice = SonosDevice(
                id: coordinator.uuid,
                name: coordinator.zoneName,
                ipAddress: coordHost,
                port: coordPort,
                modelName: coordinatorModel,
                isCoordinator: true,
                groupId: group.id,
                groupName: groupDisplayName,
                coordinatorUUID: coordUUID,
                coordinatorIP: coordHost,
                coordinatorPort: coordPort
            )
            newCoordinators.append(coordinatorDevice)
            deviceLastSeen[coordinatorDevice.id] = now

            for member in group.audioMembers {
                let isCoord = member.normalizedUUID == coordUUID
                let memberHost = member.location?.host ?? coordHost
                let memberPort = UInt16(member.location?.port ?? Int(coordPort))

                let memberModel = knownDescriptions[member.normalizedUUID]?.modelName ??
                    (member.normalizedUUID == currentDesc?.udn.normalizedSonosUUID ? currentDesc?.modelName : nil)

                let memberDevice = SonosDevice(
                    id: member.uuid,
                    name: member.zoneName,
                    ipAddress: memberHost,
                    port: memberPort,
                    modelName: memberModel,
                    isCoordinator: isCoord,
                    groupId: group.id,
                    groupName: groupDisplayName,
                    coordinatorUUID: coordUUID,
                    coordinatorIP: coordHost,
                    coordinatorPort: coordPort
                )
                newMembers.append(memberDevice)
                deviceLastSeen[memberDevice.id] = now
            }
        }

        // Merge with existing devices to retain any known coordinators while updating existing ones
        var coordMap: [String: SonosDevice] = [:]
        for dev in discoveredDevices {
            coordMap[dev.id] = dev
        }
        for dev in newCoordinators {
            coordMap[dev.id] = dev
        }

        var memberMap: [String: SonosDevice] = [:]
        for dev in allZoneDevices {
            memberMap[dev.id] = dev
        }
        for dev in newMembers {
            memberMap[dev.id] = dev
        }

        self.discoveredDevices = Array(coordMap.values).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        self.allZoneDevices = Array(memberMap.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func handleSingleDeviceFallback(desc: SonosDeviceDescription, host: String, port: UInt16) {
        let normUUID = desc.udn.normalizedSonosUUID
        let fallback = SonosDevice(
            id: normUUID,
            name: desc.roomName,
            ipAddress: host,
            port: port,
            modelName: desc.modelName,
            isCoordinator: true,
            groupId: "\(normUUID):1",
            groupName: nil,
            coordinatorUUID: normUUID,
            coordinatorIP: host,
            coordinatorPort: port
        )

        deviceLastSeen[fallback.id] = Date()
        var current = discoveredDevices.filter { $0.id != fallback.id }
        current.append(fallback)
        self.discoveredDevices = current.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        self.allZoneDevices = self.discoveredDevices
    }
}

// MARK: - SSDPDiscoveryDelegate

extension SonosDiscoveryService: SSDPDiscoveryDelegate {
    public nonisolated func ssdpDiscovery(_ discovery: SSDPDiscovery, didDiscoverService service: SSDPService) {
        guard let locationStr = service.location, let url = URL(string: locationStr) else { return }
        Task { @MainActor [weak self] in
            await self?.processDiscoveredLocation(url)
        }
    }

    public nonisolated func ssdpDiscoveryDidStart(_ discovery: SSDPDiscovery) {
        Task { @MainActor [weak self] in
            self?.isScanning = true
        }
    }

    public nonisolated func ssdpDiscoveryDidFinish(_ discovery: SSDPDiscovery) {
        Task { @MainActor [weak self] in
            self?.isScanning = false
        }
    }

    public nonisolated func ssdpDiscovery(_ discovery: SSDPDiscovery, didFinishWithError error: Error) {
        print("⚠️ [SonosDiscoveryService] SSDP discovery error: \(error)")
        Task { @MainActor [weak self] in
            self?.isScanning = false
        }
    }
}
