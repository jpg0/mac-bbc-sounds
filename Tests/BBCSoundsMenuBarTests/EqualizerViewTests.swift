import XCTest
import AppKit
@testable import BBCSoundsMenuBar

@MainActor
final class EqualizerViewTests: XCTestCase {
    
    func testEqualizerAnimatorGeneratesMatchingFrames() {
        let animator = EqualizerAnimator()
        
        XCTAssertFalse(animator.isPlaying, "Animator should not be playing initially")
        XCTAssertEqual(animator.frames.count, 16, "Should generate 16 animation frames")
        XCTAssertTrue(animator.defaultImage.isTemplate, "Default image must be a template image")
        
        for (index, frame) in animator.frames.enumerated() {
            XCTAssertEqual(frame.size, animator.defaultImage.size, "Frame \(index) size must match default radio image")
            XCTAssertTrue(frame.isTemplate, "Frame \(index) must be a template image")
        }
    }
    
    func testEqualizerAnimatorStartAndStop() {
        let animator = EqualizerAnimator()
        let button = NSStatusBarButton()
        button.image = animator.defaultImage
        
        animator.start(button: button)
        XCTAssertTrue(animator.isPlaying)
        XCTAssertNotNil(button.image)
        
        animator.stop(button: button)
        XCTAssertFalse(animator.isPlaying)
        XCTAssertEqual(button.image, animator.defaultImage)
    }
    
    func testMenubarIconWidthDoesNotChangeWhenPlaying() {
        let delegate = AppDelegate()
        delegate.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = delegate.statusItem.button else {
            XCTFail("Failed to acquire NSStatusBarButton")
            return
        }
        
        delegate.marqueeView = MacMarqueeView(frame: NSRect(x: 0, y: 0, width: 80, height: 22))
        delegate.marqueeView.isHidden = true
        button.addSubview(delegate.marqueeView)
        
        // 1. Idle state
        delegate.viewModel.player.isPlaying = false
        delegate.updateStatusItemAppearance()
        let idleWidth = button.frame.width
        XCTAssertEqual(button.title, "")
        XCTAssertEqual(button.image, delegate.equalizerAnimator.defaultImage)
        
        // 2. Playing state
        delegate.viewModel.player.isPlaying = true
        delegate.updateStatusItemAppearance()
        let playingWidth = button.frame.width
        XCTAssertEqual(button.title, "", "Title must remain empty so button width never expands")
        XCTAssertTrue(delegate.equalizerAnimator.isPlaying)
        
        // Crucial test: Icon width must NOT change!
        XCTAssertEqual(playingWidth, idleWidth, "Menubar icon width must remain strictly constant when playing")
        
        // 3. Paused state
        delegate.viewModel.player.isPlaying = false
        delegate.updateStatusItemAppearance()
        let pausedWidth = button.frame.width
        XCTAssertEqual(pausedWidth, idleWidth, "Menubar icon width must remain constant when paused")
        XCTAssertEqual(button.image, delegate.equalizerAnimator.defaultImage)
        
        // 4. Marquee overrides
        delegate.viewModel.player.isPlaying = true
        delegate.viewModel.marqueeText = "Artist - Title"
        delegate.updateStatusItemAppearance()
        XCTAssertFalse(delegate.equalizerAnimator.isPlaying)
        XCTAssertFalse(delegate.marqueeView.isHidden)
        XCTAssertNil(button.image)
        
        // 5. Marquee clears, returns to playing with exact same icon width
        delegate.viewModel.marqueeText = nil
        delegate.updateStatusItemAppearance()
        XCTAssertTrue(delegate.equalizerAnimator.isPlaying)
        XCTAssertTrue(delegate.marqueeView.isHidden)
        XCTAssertEqual(button.frame.width, idleWidth, "Width after marquee clears must match original width")
        
        // Clean up
        delegate.equalizerAnimator.stop(button: button)
        NSStatusBar.system.removeStatusItem(delegate.statusItem)
    }

    func testMenubarDoesNotShowMarqueeWhenPausedEvenIfMarqueeTextSet() {
        let delegate = AppDelegate()
        delegate.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = delegate.statusItem.button else {
            XCTFail("Failed to acquire NSStatusBarButton")
            return
        }

        delegate.marqueeView = MacMarqueeView(frame: NSRect(x: 0, y: 0, width: 80, height: 22))
        delegate.marqueeView.isHidden = true
        button.addSubview(delegate.marqueeView)

        // When paused / not playing, marqueeText should not be displayed in status bar
        delegate.viewModel.player.isPlaying = false
        delegate.viewModel.marqueeText = "Live Track Changed"
        delegate.updateStatusItemAppearance()

        XCTAssertTrue(delegate.marqueeView.isHidden, "Marquee must remain hidden when player is paused")
        XCTAssertEqual(button.image, delegate.equalizerAnimator.defaultImage, "Button image must remain default idle image")
        XCTAssertFalse(delegate.equalizerAnimator.isPlaying)
        XCTAssertEqual(delegate.statusItem.length, NSStatusItem.variableLength)

        // Clean up
        delegate.equalizerAnimator.stop(button: button)
        NSStatusBar.system.removeStatusItem(delegate.statusItem)
    }

    func testActiveTrackChangeWhilePausedDoesNotTriggerMarquee() async {
        let viewModel = AppViewModel()
        viewModel.player.isPlaying = false

        let segment = Segment(
            id: "track-123",
            artist: "Radio Artist",
            title: "New Song",
            startTime: 0,
            label: nil,
            isNowPlaying: true
        )

        viewModel.player.activeTrack = segment

        // Yield to allow Combine pipeline on main actor to process
        await Task.yield()

        XCTAssertNil(viewModel.marqueeText, "Marquee text must not be set when player is paused")
    }

    func testPausingPlaybackClearsActiveMarquee() async {
        let viewModel = AppViewModel()
        viewModel.player.isPlaying = true

        let segment = Segment(
            id: "track-456",
            artist: "Radio Artist",
            title: "Playing Song",
            startTime: 0,
            label: nil,
            isNowPlaying: true
        )

        viewModel.player.activeTrack = segment
        await Task.yield()

        XCTAssertEqual(viewModel.marqueeText, "Radio Artist - Playing Song")

        // User pauses playback
        viewModel.player.isPlaying = false
        await Task.yield()

        XCTAssertNil(viewModel.marqueeText, "Marquee text must be cleared immediately when player is paused")
    }
}
