import XCTest
import MediaPlayer
@testable import BBCSoundsMenuBar

@MainActor
final class NowPlayingSystemMediaTests: XCTestCase {

    func testRemoteCommandCenterCommandsAreConfiguredAndEnabled() {
        let player = PlayerService()
        player.setupRemoteCommandCenter()

        let commandCenter = MPRemoteCommandCenter.shared()
        XCTAssertTrue(commandCenter.playCommand.isEnabled)
        XCTAssertTrue(commandCenter.pauseCommand.isEnabled)
        XCTAssertTrue(commandCenter.togglePlayPauseCommand.isEnabled)
        XCTAssertTrue(commandCenter.skipForwardCommand.isEnabled)
        XCTAssertTrue(commandCenter.skipBackwardCommand.isEnabled)
        XCTAssertTrue(commandCenter.seekForwardCommand.isEnabled)
        XCTAssertTrue(commandCenter.seekBackwardCommand.isEnabled)
        XCTAssertTrue(commandCenter.changePlaybackPositionCommand.isEnabled)
        XCTAssertTrue(commandCenter.nextTrackCommand.isEnabled)
        XCTAssertTrue(commandCenter.previousTrackCommand.isEnabled)
    }

    func testPlaybackStateReflectsPauseAndStop() {
        let player = PlayerService()
        
        let prog = Programme(
            id: "test_prog_1",
            index: 0,
            name: "Test Programme",
            channel: "BBC Radio 4",
            duration: "00:30:00",
            description: "Test Description",
            firstBroadcast: nil,
            artworkURL: nil,
            isLive: false
        )
        player.currentProgramme = prog
        player.isPlaying = true

        // Pause should update MPNowPlayingInfoCenter playbackState to .paused
        player.pause()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)

        // Stop should update MPNowPlayingInfoCenter playbackState to .stopped and clear info
        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .stopped)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }

    func testNowPlayingInfoCenterReflectsPlayingRateAndState() {
        let player = PlayerService()

        let prog = Programme(
            id: "test_prog_2",
            index: 0,
            name: "Live Radio 1",
            channel: "BBC Radio 1",
            duration: nil,
            description: "Live broadcast",
            firstBroadcast: nil,
            artworkURL: nil,
            isLive: true
        )
        player.currentProgramme = prog
        player.isPlaying = true
        player.pause()

        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
        let pausedRate = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double
        XCTAssertEqual(pausedRate, 0.0)
    }
}
