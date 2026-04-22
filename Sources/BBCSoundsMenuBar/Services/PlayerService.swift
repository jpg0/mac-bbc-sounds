import AVFoundation
import Combine
import MediaPlayer
import AppKit

@MainActor
class PlayerService: ObservableObject {
    @Published var isPlaying = false
    @Published var volume: Float {
        didSet {
            UserDefaults.standard.set(volume, forKey: "PlayerVolume")
        }
    }
    @Published var currentProgramme: Programme? = nil
    @Published var isLoading = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playerError: String? = nil
    @Published var currentArtwork: NSImage? = nil
    @Published var currentTracks: [Segment] = []
    @Published var activeTrack: Segment? = nil
    
    var proxyConfig: ProxyConfiguration?
    var bbcSounds: BBCSoundsService?
    var onSessionSaved: (() -> Void)?

    private var player: AVPlayer?
    private var statusObserver: AnyCancellable?
    private var durationObserver: AnyCancellable?
    private var resourceLoaderDelegate: BBCProxyResourceLoaderDelegate?
    private var trackUpdateTask: Task<Void, Never>?
    private var lastSavedTime: Double = 0
    private var isUpdatingTracks = false
    private var currentLoadingArtworkURL: URL?

    init() {
        self.volume = UserDefaults.standard.value(forKey: "PlayerVolume") as? Float ?? 0.7
    }

    private func logToDebugFile(_ msg: String) {
        print("🔊 [PlayerService] \(msg)")
    }

    func play(url: URL, programme: Programme) {
        stop()
        playerError = nil
        
        // Use custom resource loader for caching/proxying
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "bbcproxy"
        guard let proxyURL = components?.url else {
            logToDebugFile("❌ Could not create proxy URL")
            return
        }
        
        let asset = AVURLAsset(url: proxyURL)
        let delegate = BBCProxyResourceLoaderDelegate(proxyConfig: proxyConfig)
        self.resourceLoaderDelegate = delegate
        asset.resourceLoader.setDelegate(delegate, queue: delegate.getQueue())
        
        let item = AVPlayerItem(asset: asset)
        
        // Caching Requirements:
        // For Live: Minimal buffer (AVPlayer handles this naturally for live playlists)
        // For VOD: Buffer as much as possible (the entire show)
        item.preferredForwardBufferDuration = 3600 * 3 // Try to buffer up to 3 hours
        player = AVPlayer(playerItem: item)
        player?.automaticallyWaitsToMinimizeStalling = true
        player?.volume = volume
        player?.play()
        
        isPlaying = true
        currentProgramme = programme
        isLoading = true // Will be set to false when ready to play
        updateNowPlaying()
        startTrackUpdates(for: programme)
        
        // Observe time
        player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] time in
            print("🎬 Current Time: \(String(format: "%.1f", time.seconds))s")
            Task { @MainActor in
                self?.currentTime = time.seconds
                self?.updateNowPlayingTrack()
                
                // Save session every 5 seconds
                if abs((self?.lastSavedTime ?? 0) - time.seconds) >= 5 {
                    self?.saveSession()
                }
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
            Task { @MainActor in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self?.logToDebugFile("Playback Failed To Play To End: \(error?.localizedDescription ?? "Unknown")")
            }
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
        saveSession()
    }

    func resume() {
        player?.play()
        isPlaying = true
        updateNowPlaying()
    }
    
    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 1)
        // Use default tolerances to avoid heavy frame-accurate CPU spikes unless needed
        player?.seek(to: time) { [weak self] finished in
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
        saveSession()
        player?.pause()
        player = nil
        isPlaying = false
        currentArtwork = nil
        currentTracks = []
        activeTrack = nil
        trackUpdateTask?.cancel()
        trackUpdateTask = nil
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        durationObserver = nil
        statusObserver = nil
    }

    func setVolume(_ v: Float) {
        volume = v
        player?.volume = v
    }

    func skipToTrack(_ segment: Segment) {
        seek(to: Double(segment.startTime))
    }

    private func updateNowPlayingTrack() {
        guard let prog = currentProgramme, !prog.isLive else { return }
        guard !isUpdatingTracks else { return }
        isUpdatingTracks = true
        
        // Use a local copy to batch updates and avoid triggering @Published for every element
        var updatedTracks = currentTracks
        
        for i in 0..<updatedTracks.count {
            let start = Double(updatedTracks[i].startTime)
            let end = (i + 1 < updatedTracks.count) ? Double(updatedTracks[i+1].startTime) : Double(currentProgramme?.durationInSeconds ?? 999999)
            
            let isNow = currentTime >= start && currentTime < end
            if updatedTracks[i].isNowPlaying != isNow {
                updatedTracks[i].isNowPlaying = isNow
                if isNow && activeTrack?.id != updatedTracks[i].id {
                    activeTrack = updatedTracks[i]
                }
            }
        }
        
        if updatedTracks != currentTracks {
            currentTracks = updatedTracks
        }
        
        isUpdatingTracks = false
    }

    private func startTrackUpdates(for programme: Programme) {
        trackUpdateTask?.cancel()
        
        let pidToUse = programme.resolvedPID ?? programme.id
        
        trackUpdateTask = Task {
            // Give it a moment to stabilize if needed, or just fetch immediately
            while !Task.isCancelled {
                do {
                    if let sounds = self.bbcSounds {
                        let tracks = try await sounds.fetchSegments(pid: pidToUse, isLive: programme.isLive)
                        await MainActor.run {
                            self.currentTracks = tracks
                            if programme.isLive, let current = tracks.first(where: { $0.isNowPlaying }) {
                                if self.activeTrack?.id != current.id {
                                    self.activeTrack = current
                                }
                            }
                            self.updateNowPlayingTrack()
                        }
                    }
                } catch {
                    logToDebugFile("⚠️ Track update failed for \(pidToUse): \(error.localizedDescription)")
                }
                
                if programme.isLive {
                    // Poll live every 30 seconds
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                } else {
                    // For on-demand, one fetch is usually enough
                    break
                }
            }
        }
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
        
        // Fetch artwork if not already loaded and not already loading
        if currentArtwork == nil, let urlString = programme.artworkURL, let url = URL(string: urlString) {
            guard currentLoadingArtworkURL != url else { return }
            currentLoadingArtworkURL = url
            
            Task {
                do {
                    if let rawImage = try await downloadImage(url: url) {
                        let squareImage = cropToSquare(image: rawImage)
                        await MainActor.run {
                            self.currentArtwork = squareImage
                            self.currentLoadingArtworkURL = nil
                            self.updateNowPlaying()
                        }
                    } else {
                        await MainActor.run { self.currentLoadingArtworkURL = nil }
                    }
                } catch {
                    await MainActor.run { self.currentLoadingArtworkURL = nil }
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

    private func saveSession() {
        guard let programme = currentProgramme, !programme.isLive else { return }
        let session = PlaybackSession(programme: programme, time: currentTime, duration: duration, date: Date())
        
        guard let data = try? JSONEncoder().encode(session) else { return }
        
        // 1. Save as the single "last" session for the resume prompt
        UserDefaults.standard.set(data, forKey: "LastPlaybackSession")
        
        // 2. Save into the global history dictionary
        var history = UserDefaults.standard.dictionary(forKey: "PlaybackHistory") as? [String: Data] ?? [:]
        history[programme.id] = data
        UserDefaults.standard.set(history, forKey: "PlaybackHistory")
        
        lastSavedTime = currentTime
        logToDebugFile("💾 Session saved: \(programme.name) at \(Int(currentTime))s / \(Int(duration))s")
        
        onSessionSaved?()
    }

    func openInSpotify(track: Segment) {
        let query = "artist:\(track.artist) track:\(track.title)"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        
        // Open search results in Spotify
        if let url = URL(string: "https://open.spotify.com/search/\(encodedQuery)") {
            NSWorkspace.shared.open(url)
        }
    }
}
