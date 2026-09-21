import XCTest
@testable import BBCSoundsMenuBar

@MainActor
final class SpeakerPickerUITests: XCTestCase {

    func testStandaloneSonosDeviceHasNoGroupBadge() {
        let device = SonosDevice(
            id: "RINCON_001",
            name: "Living Room",
            ipAddress: "192.168.1.50",
            isCoordinator: true,
            groupId: "RINCON_001:1",
            groupName: nil
        )

        XCTAssertNil(device.groupBadge)
        XCTAssertEqual(device.displayName, "Living Room")
    }

    func testStandaloneSonosDeviceWithIdenticalGroupNameHasNoGroupBadge() {
        let device = SonosDevice(
            id: "RINCON_001",
            name: "Living Room",
            ipAddress: "192.168.1.50",
            isCoordinator: true,
            groupId: "RINCON_001:1",
            groupName: "Living Room"
        )

        XCTAssertNil(device.groupBadge)
        XCTAssertEqual(device.displayName, "Living Room")
    }

    func testGroupedSonosDeviceWithSingleAdditionalMemberBadge() {
        let device = SonosDevice(
            id: "RINCON_001",
            name: "Living Room",
            ipAddress: "192.168.1.50",
            isCoordinator: true,
            groupId: "RINCON_001:1",
            groupName: "Living Room + Kitchen"
        )

        XCTAssertEqual(device.groupBadge, "(+ Kitchen)")
        XCTAssertEqual(device.displayName, "Living Room + Kitchen")
    }

    func testGroupedSonosDeviceWithMultipleAdditionalMembersBadge() {
        let device = SonosDevice(
            id: "RINCON_001",
            name: "Living Room",
            ipAddress: "192.168.1.50",
            isCoordinator: true,
            groupId: "RINCON_001:1",
            groupName: "Living Room + Kitchen + Patio"
        )

        XCTAssertEqual(device.groupBadge, "(+ Kitchen, Patio)")
        XCTAssertEqual(device.displayName, "Living Room + Kitchen + Patio")
    }

    func testAudioOutputTargetDisplayNames() {
        let mac = AudioOutputTarget.thisMac
        XCTAssertEqual(mac.displayName, "This Mac")
        XCTAssertTrue(mac.isMac)
        XCTAssertFalse(mac.isSonos)

        let sonos = SonosDevice(
            id: "RINCON_002",
            name: "Bedroom",
            ipAddress: "192.168.1.51",
            isCoordinator: true,
            groupName: "Bedroom + Ensuite"
        )
        let sonosTarget = AudioOutputTarget.sonos(sonos)
        XCTAssertEqual(sonosTarget.displayName, "Bedroom + Ensuite")
        XCTAssertFalse(sonosTarget.isMac)
        XCTAssertTrue(sonosTarget.isSonos)
        XCTAssertEqual(sonosTarget.sonosDevice?.id, "RINCON_002")
    }

    func testDiscoveryServiceScanTriggering() {
        let service = SonosDiscoveryService()
        XCTAssertFalse(service.isScanning)
        service.scan(duration: 1)
        XCTAssertTrue(service.isScanning)
        service.stopDiscovery()
        XCTAssertFalse(service.isScanning)
    }

    func testSpeakerPickerPopoverInstantiation() {
        let player = PlayerService()
        let popover = SpeakerPickerPopover(player: player)
        XCTAssertNotNil(popover)
    }

    func testOutputTargetSwitchingReflectsInPlayerService() async throws {
        let mock = MockSonosDevice(roomName: "Kitchen", currentVolume: 55)
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_KITCHEN_TEST",
            name: "Kitchen",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let player = PlayerService()
        XCTAssertTrue(player.outputTarget.isMac)

        try await player.setOutputTarget(.sonos(device))
        XCTAssertTrue(player.outputTarget.isSonos)
        XCTAssertEqual(player.outputTarget.displayName, "Kitchen")
        XCTAssertEqual(player.volume, 0.55, accuracy: 0.01)

        try await player.setOutputTarget(.thisMac)
        XCTAssertTrue(player.outputTarget.isMac)
    }
}
