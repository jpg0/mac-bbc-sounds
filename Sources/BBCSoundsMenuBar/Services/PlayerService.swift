import AVFoundation
import Combine
import MediaPlayer
import AppKit

@MainActor
class PlayerService: ObservableObject {
    @Published var isPlaying = false
    @Published var volume: Float = 0.7
    @Published var currentProgramme: Programme? = nil
    @Published var isLoading = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playerError: String? = nil
    @Published var currentArtwork: NSImage? = nil
    
    var proxyConfig: ProxyConfiguration?

    private var player: AVPlayer?
    private var statusObserver: AnyCancellable?
    private var durationObserver: AnyCancellable?
    private func logToDebugFile(_ msg: String) {
        print(msg)
        let logURL = URL(fileURLWithPath: "/tmp/bbc_sounds_debug.log")
        if let data = "[\(Date())] 🔊 [PlayerService] \(msg)\n".data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    func play(url: URL, programme: Programme) {
        stop()
        playerError = nil
        
        let item = AVPlayerItem(url: url)
        
        logToDebugFile("Playing URL: \(url.absoluteString)")
        
        player = AVPlayer(playerItem: item)
        player?.volume = volume
        player?.play()
        
        isPlaying = true
        currentProgramme = programme
        isLoading = true // Will be set to false when ready to play
        updateNowPlaying()
        
        // Observe time
        player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] time in
            print("🎬 Current Time: \(String(format: "%.1f", time.seconds))s")
            Task { @MainActor in
                self?.currentTime = time.seconds
            }
        }
        
        // Observe status and duration
        statusObserver = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .readyToPlay {
                    self?.logToDebugFile("Status: Ready to Play")
                    self?.isLoading = false
                    self?.updateDuration(item: item)
                    self?.setupRemoteCommandCenter()
                    self?.updateNowPlaying()
                } else if status == .failed {
                    let errMsg = item.error?.localizedDescription ?? "Unknown failure"
                    self?.logToDebugFile("Status: Failed - \(errMsg)")
                    self?.playerError = errMsg
                    self?.isLoading = false
                }
                self?.logMediaError(for: item)
            }
        
        NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self?.logToDebugFile("Playback Failed To Play To End: \(error?.localizedDescription ?? "Unknown")")
        }
            
        durationObserver = item.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDuration(item: item)
                self?.updateNowPlaying()
            }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        player?.play()
        isPlaying = true
        updateNowPlaying()
    }
    
    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 1)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            if finished {
                Task { @MainActor in
                    self?.updateNowPlaying()
                }
            }
        }
    }
    
    func seek(by seconds: Double) {
        guard let player = player else { return }
        let currentSeconds = player.currentTime().seconds
        seek(to: currentSeconds + seconds)
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        currentProgramme = nil
        playerError = nil
        currentArtwork = nil
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        durationObserver = nil
        statusObserver = nil
    }

    func setVolume(_ v: Float) {
        volume = v
        player?.volume = v
    }

    @objc private func didFinish() {
        isPlaying = false
        currentProgramme = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    private func updateDuration(item: AVPlayerItem) {
        let d = item.duration.seconds
        if !d.isNaN && !d.isInfinite {
            self.duration = d
        }
    }
    
    // MARK: - Media Center Integration
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Remove existing targets to avoid duplication
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.seekForwardCommand.removeTarget(nil)
        commandCenter.seekBackwardCommand.removeTarget(nil)
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.isPlaying ?? false ? self?.pause() : self?.resume()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: e.positionTime)
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.seekForwardCommand.addTarget { [weak self] _ in
            self?.seek(by: 15)
            return .success
        }
        
        commandCenter.seekBackwardCommand.addTarget { [weak self] _ in
            self?.seek(by: -15)
            return .success
        }
    }
    
    private func updateNowPlaying() {
        guard let programme = currentProgramme else { return }
        
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = programme.name
        nowPlayingInfo[MPMediaItemPropertyArtist] = programme.channel
        
        if duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        if let image = currentArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { size in
                return image
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        
        // Fetch artwork if not already loaded
        if currentArtwork == nil, let urlString = programme.artworkURL, let url = URL(string: urlString) {
            Task {
                if let rawImage = try? await downloadImage(url: url) {
                    let squareImage = cropToSquare(image: rawImage)
                    self.currentArtwork = squareImage
                    self.updateNowPlaying()
                }
            }
        }
    }
    
    private func downloadImage(url: URL) async throws -> NSImage? {
        let (data, _) = try await URLSession.shared.data(from: url)
        return NSImage(data: data)
    }

    private func cropToSquare(image: NSImage) -> NSImage {
        let size = image.size
        let side = min(size.width, size.height)
        let squareSize = NSSize(width: side, height: side)
        
        let rect = NSRect(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2,
            width: side,
            height: side
        )
        
        let targetRect = NSRect(origin: .zero, size: squareSize)
        let result = NSImage(size: squareSize)
        
        result.lockFocus()
        image.draw(in: targetRect, from: rect, operation: .copy, fraction: 1.0)
        result.unlockFocus()
        
        return result
    }
    
    private func logMediaError(for item: AVPlayerItem) {
        if let errorLog = item.errorLog() {
            for event in errorLog.events {
                print("🎬 [AVPlayer ErrorLog] \(event.errorDomain) (\(event.errorStatusCode)): \(event.errorComment ?? "No comment")")
                print("   -> URL: \(event.uri ?? "No URI")")
            }
        }
        if let accessLog = item.accessLog() {
            for event in accessLog.events {
                if event.numberOfDroppedVideoFrames > 0 || event.numberOfStalls > 0 {
                    print("🎬 [AVPlayer AccessLog] Stalls: \(event.numberOfStalls), Dropped Frames: \(event.numberOfDroppedVideoFrames)")
                }
            }
        }
    }
}
