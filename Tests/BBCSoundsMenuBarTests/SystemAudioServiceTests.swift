import XCTest
import Combine
@testable import BBCSoundsMenuBar

final class MockSystemAudioService: SystemAudioServiceProtocol {
    var onVolumeChanged: (@Sendable (Float) -> Void)?
    var onMuteChanged: (@Sendable (Bool) -> Void)?

    var currentVolume: Float = 0.5
    var isMuted: Bool = false
    var isMonitoring: Bool = false

    var setVolumeCallCount = 0
    var lastSetVolume: Float?
    var lastSetVolumeSilently: Bool?

    var setMuteCallCount = 0
    var lastSetMute: Bool?
    var lastSetMuteSilently: Bool?

    func getVolume() -> Float? {
        currentVolume
    }

    func getMute() -> Bool? {
        isMuted
    }

    func setVolume(_ volume: Float, silently: Bool) {
        setVolumeCallCount += 1
        lastSetVolume = volume
        lastSetVolumeSilently = silently
        currentVolume = volume
        if !silently {
            onVolumeChanged?(volume)
        }
    }

    func setMute(_ isMuted: Bool, silently: Bool) {
        setMuteCallCount += 1
        lastSetMute = isMuted
        lastSetMuteSilently = silently
        self.isMuted = isMuted
        if !silently {
            onMuteChanged?(isMuted)
        }
    }

    func startMonitoring() {
        isMonitoring = true
    }

    func stopMonitoring() {
        isMonitoring = false
    }

    /// Simulates user pressing keyboard volume keys (F11/F12) or dragging Control Center slider.
    func simulateUserVolumeChange(_ newVolume: Float) {
        currentVolume = newVolume
        onVolumeChanged?(newVolume)
    }

    /// Simulates user pressing keyboard mute key (F10).
    func simulateUserMuteChange(_ muted: Bool) {
        isMuted = muted
        onMuteChanged?(muted)
    }
}

final class SystemAudioServiceTests: XCTestCase {

    // MARK: - Mute XML Parsing Tests

    func testSonosMuteParserNumericOneAndZero() throws {
        let xmlMuted = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetMuteResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <CurrentMute>1</CurrentMute>
            </u:GetMuteResponse>
          </s:Body>
        </s:Envelope>
        """
        XCTAssertTrue(try SonosMuteParser.parse(xmlData: Data(xmlMuted.utf8)))

        let xmlUnmuted = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetMuteResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <CurrentMute>0</CurrentMute>
            </u:GetMuteResponse>
          </s:Body>
        </s:Envelope>
        """
        XCTAssertFalse(try SonosMuteParser.parse(xmlData: Data(xmlUnmuted.utf8)))
    }

    func testSonosMuteParserBooleanStrings() throws {
        let xmlTrue = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetMuteResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <CurrentMute>true</CurrentMute>
            </u:GetMuteResponse>
          </s:Body>
        </s:Envelope>
        """
        XCTAssertTrue(try SonosMuteParser.parse(xmlData: Data(xmlTrue.utf8)))

        let xmlFalse = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetMuteResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <CurrentMute>false</CurrentMute>
            </u:GetMuteResponse>
          </s:Body>
        </s:Envelope>
        """
        XCTAssertFalse(try SonosMuteParser.parse(xmlData: Data(xmlFalse.utf8)))
    }

    // MARK: - SonosController Mute against MockSonosDevice

    @MainActor
    func testSonosControllerMuteControlsOnMockDevice() async throws {
        let mock = MockSonosDevice(roomName: "Lounge", isMuted: false)
        let port = try mock.start()
        defer { mock.stop() }

        let device = SonosDevice(
            id: "RINCON_LOUNGE",
            name: "Lounge",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        let controller = SonosController(device: device)

        let initialMute = try await controller.getMute()
        XCTAssertFalse(initialMute)
        XCTAssertFalse(controller.isMuted)

        try await controller.setMute(true)
        XCTAssertTrue(mock.isMuted)
        XCTAssertTrue(controller.isMuted)

        try await controller.setMute(false)
        XCTAssertFalse(mock.isMuted)
        XCTAssertFalse(controller.isMuted)
    }

    // MARK: - System Volume Integration with PlayerService

    @MainActor
    func testAdjustingMacBookVolumeAppliesToActiveSonosSpeaker() async throws {
        let mock = MockSonosDevice(roomName: "Kitchen", currentVolume: 20)
        let port = try mock.start()
        defer { mock.stop() }

        let mockSystemAudio = MockSystemAudioService()
        let player = PlayerService(systemAudioService: mockSystemAudio)

        let device = SonosDevice(
            id: "RINCON_KITCHEN",
            name: "Kitchen",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        player.sonosControllerFactory = { _ in SonosController(device: device) }

        // Switch to Sonos
        player.outputTarget = .sonos(device)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify initial volume synced to system audio
        XCTAssertEqual(mockSystemAudio.lastSetVolume, 0.20)
        XCTAssertEqual(mockSystemAudio.lastSetVolumeSilently, true)

        // User adjusts volume on MacBook (e.g. presses F12 to increase volume to 45%)
        mockSystemAudio.simulateUserVolumeChange(0.45)
        try await Task.sleep(nanoseconds: 150_000_000)

        // Verify Sonos device received the updated volume
        XCTAssertEqual(mock.currentVolume, 45)
        XCTAssertEqual(player.volume, 0.45)
    }

    @MainActor
    func testAdjustingMacBookMuteAppliesToActiveSonosSpeaker() async throws {
        let mock = MockSonosDevice(roomName: "Kitchen", isMuted: false)
        let port = try mock.start()
        defer { mock.stop() }

        let mockSystemAudio = MockSystemAudioService()
        let player = PlayerService(systemAudioService: mockSystemAudio)

        let device = SonosDevice(
            id: "RINCON_KITCHEN_MUTE",
            name: "Kitchen",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        player.sonosControllerFactory = { _ in SonosController(device: device) }

        // Switch to Sonos
        player.outputTarget = .sonos(device)
        try await Task.sleep(nanoseconds: 100_000_000)

        // User presses Mute on MacBook (F10)
        mockSystemAudio.simulateUserMuteChange(true)
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertTrue(mock.isMuted)

        // User unmutes on MacBook
        mockSystemAudio.simulateUserMuteChange(false)
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertFalse(mock.isMuted)
    }

    @MainActor
    func testRapidMacBookVolumeAdjustmentsCoalesceToFinalTarget() async throws {
        let mock = MockSonosDevice(roomName: "Office", currentVolume: 10)
        let port = try mock.start()
        defer { mock.stop() }

        let mockSystemAudio = MockSystemAudioService()
        let player = PlayerService(systemAudioService: mockSystemAudio)

        let device = SonosDevice(
            id: "RINCON_OFFICE_RAPID",
            name: "Office",
            ipAddress: "127.0.0.1",
            port: port,
            isCoordinator: true
        )

        player.sonosControllerFactory = { _ in SonosController(device: device) }
        player.outputTarget = .sonos(device)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Simulate user holding down volume up key rapidly
        mockSystemAudio.simulateUserVolumeChange(0.15)
        mockSystemAudio.simulateUserVolumeChange(0.20)
        mockSystemAudio.simulateUserVolumeChange(0.25)
        mockSystemAudio.simulateUserVolumeChange(0.30)
        mockSystemAudio.simulateUserVolumeChange(0.35)

        // Allow in-flight and pending coalesced tasks to complete
        try await Task.sleep(nanoseconds: 300_000_000)

        // Final volume on mock device must match the latest user input
        XCTAssertEqual(mock.currentVolume, 35)
        XCTAssertEqual(player.volume, 0.35)
    }

    @MainActor
    func testMacBookVolumeChangeIgnoredWhenOutputTargetIsMac() async throws {
        let mockSystemAudio = MockSystemAudioService()
        let player = PlayerService(systemAudioService: mockSystemAudio)

        player.outputTarget = .thisMac
        player.volume = 0.5

        // Adjust system volume on Mac
        mockSystemAudio.simulateUserVolumeChange(0.8)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Because outputTarget is thisMac, the local player is not overridden via callback
        XCTAssertEqual(player.volume, 0.5)
    }
}
