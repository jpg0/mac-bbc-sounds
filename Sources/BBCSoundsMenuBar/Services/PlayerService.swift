import AVFoundation
import Combine
import MediaPlayer
import AppKit

@MainActor
class PlayerService: ObservableObject {
    @Published var isPlaying = false
    @Published var volume: Float {
        didSet {
            if outputTarget.isMac {
                UserDefaults.app.set(volume, forKey: "PlayerVolume")
            }
        }
    }
    @Published var outputTarget: AudioOutputTarget = .thisMac {
        didSet {
            guard oldValue != outputTarget else { return }
            handleOutputTargetChanged(from: oldValue, to: outputTarget)
        }
    }
    @Published public private(set) var sonosController: SonosController? = nil
    @Published public private(set) var currentStreamURL: URL? = nil

    public let discoveryService: SonosDiscoveryService
    public let systemAudioService: SystemAudioServiceProtocol
    var deliveryService = SonosStreamDeliveryService()
    var sonosControllerFactory: ((SonosDevice) -> SonosController)?

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
    private var localProxyServer: LocalProxyServer?
    private var trackUpdateTask: Task<Void, Never>?
    private var lastSavedTime: Double = 0
    private var isUpdatingTracks = false
    private var currentLoadingArtworkURL: URL?
    private var sonosCancellables = Set<AnyCancellable>()
    private var discoveryCancellable: AnyCancellable?
    private var handoffTask: Task<Void, Never>?
    private var sonosVolumeTask: Task<Void, Never>?
    private var pendingSonosVolume: Int?

    init(
        discoveryService: SonosDiscoveryService? = nil,
        systemAudioService: SystemAudioServiceProtocol? = nil
    ) {
        self.volume = UserDefaults.app.value(forKey: "PlayerVolume") as? Float ?? 0.7
        let discovery = discoveryService ?? SonosDiscoveryService()
        self.discoveryService = discovery
        let sysAudio = systemAudioService ?? SystemAudioService()
        self.systemAudioService = sysAudio
        setupDiscoveryObservation()
        setupSystemAudioObservation()
    }

    private func setupSystemAudioObservation() {
        systemAudioService.onVolumeChanged = { [weak self] newVolume in
            Task { @MainActor [weak self] in
                guard let self = self, self.outputTarget.isSonos else { return }
                self.setVolume(newVolume)
            }
        }

        systemAudioService.onMuteChanged = { [weak self] isMuted in
            Task { @MainActor [weak self] in
                guard let self = self, self.outputTarget.isSonos else { return }
                self.handleSystemMuteChanged(isMuted)
            }
        }

        systemAudioService.startMonitoring()
    }

    private func setupDiscoveryObservation() {
        discoveryCancellable = discoveryService.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self = self, case .sonos(let activeDevice) = self.outputTarget else { return }
                if let updated = devices.first(where: { $0.id == activeDevice.id }), updated != activeDevice {
                    self.outputTarget = .sonos(updated)
                }
            }
    }

    /// Starts periodic SSDP discovery for Sonos speakers.
    public func startDiscovery() {
        discoveryService.startDiscovery()
    }

    /// Triggers an immediate SSDP search for Sonos speakers.
    public func scanForDevices() {
        discoveryService.scan()
    }

    /// Manually adds and probes a known Sonos speaker host/IP (useful across VLANs/subnets).
    public func addKnownSonosHost(_ host: String) {
        discoveryService.addKnownHost(host)
    }

    /// Fetches the volume level for a Sonos device, returning the live volume if currently active.
    public func fetchVolume(for device: SonosDevice) async -> Int? {
        if case .sonos(let active) = outputTarget, active.id == device.id {
            return Int(round(volume * 100))
        }
        return try? await makeSonosController(for: device).getVolume()
    }

    private func logToDebugFile(_ msg: String) {
        print("🔊 [PlayerService] \(msg)")
    }

    func play(url: URL, programme: Programme) {
        player?.pause()
        player = nil
        statusObserver = nil
        durationObserver = nil
        currentArtwork = nil
        currentTracks = []
        activeTrack = nil
        trackUpdateTask?.cancel()
        trackUpdateTask = nil
        playerError = nil

        self.currentStreamURL = url
        self.currentProgramme = programme

        switch outputTarget {
        case .thisMac:
            setupLocalPlayer(url: url, programme: programme, seekTo: nil, autoPlay: true)

        case .sonos(let device):
            let controller = sonosController ?? makeSonosController(for: device)
            self.sonosController = controller
            observeSonosController(controller)

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let initialVol = try? await controller.getVolume() {
                    let normalized = Float(initialVol) / 100.0
                    self.volume = normalized
                    self.systemAudioService.setVolume(normalized, silently: true)
                }
                if let initialMute = try? await controller.getMute() {
                    self.systemAudioService.setMute(initialMute, silently: true)
                }
                do {
                    try await self.startSonosPlayback(
                        controller: controller,
                        url: url,
                        programme: programme,
                        seekTo: nil,
                        autoPlay: true
                    )
                } catch {
                    self.logToDebugFile("❌ Failed to play to Sonos: \(error.localizedDescription)")
                    self.playerError = error.localizedDescription
                    self.isLoading = false
                    self.isPlaying = false
                }
            }
        }
    }

    private func setupLocalPlayer(
        url: URL,
        programme: Programme,
        seekTo: Double? = nil,
        autoPlay: Bool = true
    ) {
        player?.pause()
        player = nil
        statusObserver = nil
        durationObserver = nil
        playerError = nil

        let item: AVPlayerItem

        if let proxy = proxyConfig {
            let server: LocalProxyServer
            if let existing = localProxyServer, existing.isRunning {
                server = existing
            } else {
                server = LocalProxyServer(proxyConfig: proxy)
                do {
                    _ = try server.start()
                    self.localProxyServer = server
                } catch {
                    logToDebugFile("❌ LocalProxyServer failed to start: \(error.localizedDescription)")
                    item = AVPlayerItem(url: url)
                    setupAVPlayerWithItem(item, programme: programme, seekTo: seekTo, autoPlay: autoPlay)
                    return
                }
            }

            if let localURL = server.relayURL(for: url) {
                logToDebugFile("🔀 Stream routed via local proxy (\(programme.isLive ? "live" : "on-demand")): \(localURL)")
                item = AVPlayerItem(url: localURL)
            } else {
                item = AVPlayerItem(url: url)
            }
        } else {
            logToDebugFile("▶️ Playing directly (no proxy): \(url.absoluteString)")
            item = AVPlayerItem(url: url)
        }

        setupAVPlayerWithItem(item, programme: programme, seekTo: seekTo, autoPlay: autoPlay)
    }

    private func setupAVPlayerWithItem(
        _ item: AVPlayerItem,
        programme: Programme,
        seekTo: Double? = nil,
        autoPlay: Bool = true
    ) {
        item.preferredForwardBufferDuration = 3600 * 3
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        p.volume = volume
        self.player = p

        if let targetSeek = seekTo, targetSeek > 0, !programme.isLive {
            p.seek(to: CMTime(seconds: targetSeek, preferredTimescale: 1))
            self.currentTime = targetSeek
        }

        if autoPlay {
            p.play()
            isPlaying = true
        } else {
            isPlaying = false
        }

        currentProgramme = programme
        isLoading = true
        updateNowPlaying()
        startTrackUpdates(for: programme)

        // Observe time
        p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self, self.outputTarget.isMac else { return }
                self.currentTime = time.seconds
                self.updateNowPlayingTrack()
                if abs(self.lastSavedTime - time.seconds) >= 5 {
                    self.saveSession()
                }
            }
        }

        // Observe status and duration
        statusObserver = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self, self.outputTarget.isMac else { return }
                if status == .readyToPlay {
                    self.logToDebugFile("Status: Ready to Play")
                    self.isLoading = false
                    self.updateDuration(item: item)
                    self.setupRemoteCommandCenter()
                    self.updateNowPlaying()
                } else if status == .failed {
                    let errMsg = item.error?.localizedDescription ?? "Unknown failure"
                    self.logToDebugFile("Status: Failed - \(errMsg)")
                    self.playerError = errMsg
                    self.isLoading = false
                }
                self.logMediaError(for: item)
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
                guard let self = self, self.outputTarget.isMac else { return }
                self.updateDuration(item: item)
                self.updateNowPlaying()
            }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    private func startSonosPlayback(
        controller: SonosController,
        url: URL,
        programme: Programme,
        seekTo: Double? = nil,
        autoPlay: Bool = true
    ) async throws {
        isLoading = true
        playerError = nil
        defer {
            isLoading = false
        }

        let deliveryURL: URL
        do {
            if let proxy = proxyConfig {
                let server = try deliveryService.prepareServer(proxyConfig: proxy, existingServer: localProxyServer)
                self.localProxyServer = server
                deliveryURL = try deliveryService.resolveDeliveryURL(for: url, proxyConfig: proxy, proxyServer: server)
            } else {
                deliveryURL = url
            }
        } catch {
            logToDebugFile("❌ Failed to resolve delivery URL for Sonos: \(error.localizedDescription)")
            playerError = error.localizedDescription
            throw error
        }

        logToDebugFile("📡 Setting Sonos transport URI: \(deliveryURL)")
        do {
            try await controller.setAVTransportURI(url: deliveryURL, programme: programme)

            if let seekTime = seekTo, seekTime > 0, !programme.isLive {
                do {
                    logToDebugFile("⏩ Seeking Sonos to \(seekTime)s")
                    try await controller.seek(to: seekTime)
                    self.currentTime = seekTime
                } catch {
                    logToDebugFile("⚠️ Seek not supported for this stream on Sonos: \(error.localizedDescription)")
                }
            }

            if autoPlay {
                try await controller.play()
                self.isPlaying = true
            }

            controller.startPolling()
            setupRemoteCommandCenter()
            updateNowPlaying()
            startTrackUpdates(for: programme)
        } catch {
            logToDebugFile("❌ Sonos playback error: \(error.localizedDescription)")
            playerError = error.localizedDescription
            isPlaying = false
            throw error
        }
    }

    private func teardownSonosController() async {
        sonosController?.stopPolling()
        let prevController = sonosController
        sonosController = nil
        sonosCancellables.removeAll()
        _ = try? await prevController?.pause()
    }

    private var isPerformingProgrammaticHandoff = false

    public func setOutputTarget(_ target: AudioOutputTarget) async throws {
        guard target != outputTarget else { return }
        let previous = outputTarget
        isPerformingProgrammaticHandoff = true
        self.outputTarget = target
        isPerformingProgrammaticHandoff = false
        do {
            try await performHandoff(from: previous, to: target)
        } catch {
            self.playerError = error.localizedDescription
            self.isLoading = false
            self.isPlaying = false
            throw error
        }
    }

    private func handleOutputTargetChanged(from previous: AudioOutputTarget, to target: AudioOutputTarget) {
        guard !isPerformingProgrammaticHandoff else { return }
        handoffTask?.cancel()
        handoffTask = Task { @MainActor [weak self] in
            do {
                try await self?.performHandoff(from: previous, to: target)
            } catch {
                self?.logToDebugFile("❌ Handoff failed: \(error.localizedDescription)")
                self?.playerError = error.localizedDescription
                self?.isLoading = false
                self?.isPlaying = false
            }
        }
    }

    private func performHandoff(from previous: AudioOutputTarget, to target: AudioOutputTarget) async throws {
        logToDebugFile("🔄 Output target changing from \(previous.displayName) to \(target.displayName)")

        let wasPlaying = self.isPlaying
        let handoffTime = self.currentTime
        let prog = self.currentProgramme
        let streamURL = self.currentStreamURL

        switch target {
        case .thisMac:
            await teardownSonosController()

            let savedVol = UserDefaults.app.value(forKey: "PlayerVolume") as? Float ?? 0.7
            self.volume = savedVol
            self.systemAudioService.setVolume(savedVol, silently: true)
            self.systemAudioService.setMute(false, silently: true)

            if let streamURL = streamURL, let prog = prog {
                setupLocalPlayer(url: streamURL, programme: prog, seekTo: handoffTime, autoPlay: wasPlaying)
            }

        case .sonos(let device):
            if case .sonos(let prevDevice) = previous, prevDevice.id != device.id {
                await teardownSonosController()
            } else {
                player?.pause()
                player = nil
                statusObserver = nil
                durationObserver = nil
            }

            let controller = makeSonosController(for: device)
            self.sonosController = controller
            observeSonosController(controller)

            if let initialVol = try? await controller.getVolume() {
                let normalized = Float(initialVol) / 100.0
                self.volume = normalized
                self.systemAudioService.setVolume(normalized, silently: true)
            }
            if let initialMute = try? await controller.getMute() {
                self.systemAudioService.setMute(initialMute, silently: true)
            }

            if let streamURL = streamURL, let prog = prog {
                do {
                    try await startSonosPlayback(
                        controller: controller,
                        url: streamURL,
                        programme: prog,
                        seekTo: handoffTime,
                        autoPlay: wasPlaying
                    )
                } catch {
                    logToDebugFile("❌ Failed to handoff to Sonos: \(error.localizedDescription)")
                    self.playerError = error.localizedDescription
                    self.isLoading = false
                    self.isPlaying = false
                    throw error
                }
            }
        }
    }

    private func makeSonosController(for device: SonosDevice) -> SonosController {
        if let factory = sonosControllerFactory {
            return factory(device)
        }
        return SonosController(device: device)
    }

    private func observeSonosController(_ controller: SonosController) {
        sonosCancellables.removeAll()

        controller.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self = self, self.outputTarget.isSonos else { return }
                if self.isPlaying != isPlaying {
                    self.isPlaying = isPlaying
                    self.updateNowPlaying()
                }
            }
            .store(in: &sonosCancellables)

        controller.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self = self, self.outputTarget.isSonos else { return }
                self.currentTime = time
                self.updateNowPlayingTrack()
                if abs(self.lastSavedTime - time) >= 5 {
                    self.saveSession()
                }
            }
            .store(in: &sonosCancellables)

        controller.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in
                guard let self = self, self.outputTarget.isSonos else { return }
                if dur > 0 {
                    self.duration = dur
                    self.updateNowPlaying()
                }
            }
            .store(in: &sonosCancellables)

        controller.$volume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] vol in
                guard let self = self, self.outputTarget.isSonos else { return }
                let normalized = Float(vol) / 100.0
                if abs(self.volume - normalized) > 0.01 {
                    self.volume = normalized
                    self.systemAudioService.setVolume(normalized, silently: true)
                }
            }
            .store(in: &sonosCancellables)

        controller.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isMuted in
                guard let self = self, self.outputTarget.isSonos else { return }
                self.systemAudioService.setMute(isMuted, silently: true)
            }
            .store(in: &sonosCancellables)
    }

    func pause() {
        switch outputTarget {
        case .thisMac:
            player?.pause()
        case .sonos:
            Task { try? await sonosController?.pause() }
        }
        isPlaying = false
        updateNowPlaying()
        saveSession()
    }

    func resume() {
        switch outputTarget {
        case .thisMac:
            player?.play()
        case .sonos:
            Task { try? await sonosController?.play() }
        }
        isPlaying = true
        updateNowPlaying()
    }
    
    func seek(to seconds: Double) {
        switch outputTarget {
        case .thisMac:
            let time = CMTime(seconds: seconds, preferredTimescale: 1)
            player?.seek(to: time) { [weak self] finished in
                if finished {
                    Task { @MainActor in
                        self?.updateNowPlaying()
                    }
                }
            }
        case .sonos:
            currentTime = seconds
            Task { [weak self] in
                try? await self?.sonosController?.seek(to: seconds)
                await MainActor.run {
                    self?.updateNowPlaying()
                }
            }
        }
    }
    
    func seek(by seconds: Double) {
        switch outputTarget {
        case .thisMac:
            guard let player = player else { return }
            let currentSeconds = player.currentTime().seconds
            seek(to: currentSeconds + seconds)
        case .sonos:
            seek(to: max(0, currentTime + seconds))
        }
    }

    func stop() {
        saveSession()
        switch outputTarget {
        case .thisMac:
            player?.pause()
            player = nil
        case .sonos:
            sonosController?.stopPolling()
            Task { [weak self] in
                try? await self?.sonosController?.stop()
            }
        }
        isPlaying = false
        currentArtwork = nil
        currentTracks = []
        activeTrack = nil
        currentStreamURL = nil
        currentProgramme = nil
        trackUpdateTask?.cancel()
        trackUpdateTask = nil
        localProxyServer?.stop()
        localProxyServer = nil
        sonosVolumeTask?.cancel()
        sonosVolumeTask = nil
        pendingSonosVolume = nil

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        durationObserver = nil
        statusObserver = nil
    }

    func setVolume(_ v: Float) {
        let clamped = max(0.0, min(1.0, v))
        volume = clamped
        switch outputTarget {
        case .thisMac:
            player?.volume = clamped
        case .sonos:
            let sonosVol = Int(round(clamped * 100))
            systemAudioService.setVolume(clamped, silently: true)
            dispatchSonosVolume(sonosVol)
        }
    }

    private func dispatchSonosVolume(_ sonosVol: Int) {
        if sonosVolumeTask != nil {
            pendingSonosVolume = sonosVol
            return
        }

        sonosVolumeTask = Task { [weak self] in
            guard let self = self else { return }
            try? await self.sonosController?.setVolume(sonosVol)
            self.sonosVolumeTask = nil

            if let nextVol = self.pendingSonosVolume {
                self.pendingSonosVolume = nil
                if nextVol != sonosVol {
                    self.dispatchSonosVolume(nextVol)
                }
            }
        }
    }

    private func handleSystemMuteChanged(_ isMuted: Bool) {
        Task { [weak self] in
            guard let self = self, self.outputTarget.isSonos else { return }
            try? await self.sonosController?.setMute(isMuted)
        }
    }

    func skipToTrack(_ segment: Segment) {
        seek(to: Double(segment.startTime))
    }

    func skipToNextTrack() {
        guard !currentTracks.isEmpty else {
            seek(by: 15)
            return
        }
        // Find the first track that starts after current time (+ small buffer)
        if let next = currentTracks.first(where: { Double($0.startTime) > currentTime + 2 }) {
            skipToTrack(next)
        } else {
            seek(by: 15)
        }
    }

    func skipToPreviousTrack() {
        guard !currentTracks.isEmpty else {
            seek(by: -15)
            return
        }
        
        // Find the track we are currently in
        let sortedTracks = currentTracks.sorted { $0.startTime < $1.startTime }
        guard let currentIndex = sortedTracks.firstIndex(where: { $0.isNowPlaying }) else {
            // Fallback: just go back 15s if no tracks
            seek(by: -15)
            return
        }
        
        let currentTrack = sortedTracks[currentIndex]
        
        // If we are more than 3 seconds into the current track, go to start of it
        if currentTime > Double(currentTrack.startTime) + 3 {
            skipToTrack(currentTrack)
        } else if currentIndex > 0 {
            // Otherwise go to previous track
            skipToTrack(sortedTracks[currentIndex - 1])
        } else {
            // We are in the first track, just go to 0
            seek(to: 0)
        }
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
        currentStreamURL = nil
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
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        
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

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipToNextTrack()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.skipToPreviousTrack()
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
        UserDefaults.app.set(data, forKey: "LastPlaybackSession")
        
        // 2. Save into the global history dictionary
        var history = UserDefaults.app.dictionary(forKey: "PlaybackHistory") as? [String: Data] ?? [:]
        let historyKey = programme.resolvedPID ?? programme.id
        history[historyKey] = data
        UserDefaults.app.set(history, forKey: "PlaybackHistory")
        
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
