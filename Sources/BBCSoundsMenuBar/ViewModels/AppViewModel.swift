import Foundation
import Combine

@MainActor
class AppViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var searchResults: [Programme] = []
    @Published var isSearching = false
    @Published var isLoadingStream = false
    @Published var errorMessage: String? = nil
    @Published var menubarTitle: String? = nil
    @Published var resumeSession: PlaybackSession? = nil
    @Published var marqueeText: String? = nil
    @Published var marqueeStartTime: Date? = nil

    // Proxy Settings
    @Published var proxyEnabled: Bool { didSet { UserDefaults.standard.set(proxyEnabled, forKey: "ProxyEnabled"); updateServicesProxy() } }
    @Published var proxyHost: String { didSet { UserDefaults.standard.set(proxyHost, forKey: "ProxyHost"); updateServicesProxy() } }
    @Published var proxyPort: String { didSet { UserDefaults.standard.set(proxyPort, forKey: "ProxyPort"); updateServicesProxy() } }
    @Published var proxyUser: String { didSet { UserDefaults.standard.set(proxyUser, forKey: "ProxyUser"); updateServicesProxy() } }
    @Published var proxyPass: String { didSet { UserDefaults.standard.set(proxyPass, forKey: "ProxyPass"); updateServicesProxy() } }
    @Published var proxySkipVerify: Bool { didSet { UserDefaults.standard.set(proxySkipVerify, forKey: "ProxySkipVerify"); updateServicesProxy() } }
    @Published var proxyForDiscovery: Bool { didSet { UserDefaults.standard.set(proxyForDiscovery, forKey: "ProxyForDiscovery"); updateServicesProxy() } }

    let player: PlayerService
    private let bbcSounds: BBCSoundsService
    private var searchTask: Task<Void, Never>?
    private var marqueeTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.proxyEnabled = UserDefaults.standard.bool(forKey: "ProxyEnabled")
        self.proxyHost = UserDefaults.standard.string(forKey: "ProxyHost") ?? ""
        self.proxyPort = UserDefaults.standard.string(forKey: "ProxyPort") ?? "89"
        self.proxyUser = UserDefaults.standard.string(forKey: "ProxyUser") ?? ""
        self.proxyPass = UserDefaults.standard.string(forKey: "ProxyPass") ?? ""
        self.proxySkipVerify = UserDefaults.standard.bool(forKey: "ProxySkipVerify")
        self.proxyForDiscovery = UserDefaults.standard.bool(forKey: "ProxyForDiscovery")
        
        let pService = PlayerService()
        self.player = pService
        let sounds = BBCSoundsService()
        self.bbcSounds = sounds
        pService.bbcSounds = sounds
        
        // Observe player state
        player.$playerError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.errorMessage = error
                }
            }
            .store(in: &cancellables)
            
        player.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: \.isLoadingStream, on: self)
            .store(in: &cancellables)
        
        player.$activeTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                if let track = track {
                    self?.startMarquee(for: track)
                } else {
                    self?.marqueeTask?.cancel()
                    self?.menubarTitle = nil
                }
            }
            .store(in: &cancellables)
        
        loadSavedSession()
        
        updateServicesProxy()
        handleCommandLineArgs()
    }
    
    func updateServicesProxy() {
        let config = proxyEnabled ? ProxyConfiguration(host: proxyHost, port: Int(proxyPort) ?? 89, user: proxyUser, pass: proxyPass, skipVerify: proxySkipVerify) : nil
        player.proxyConfig = config
    }

    func onSearchQueryChanged() {
        searchTask?.cancel()
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    func performSearch() async {
        isSearching = true
        errorMessage = nil
        do {
            searchResults = try await bbcSounds.search(query: searchQuery)
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            searchResults = []
        }
        isSearching = false
    }

    func playProgramme(_ programme: Programme) async {
        resumeSession = nil // Clear resume prompt if we start something else
        isLoadingStream = true
        errorMessage = nil
        do {
            var updatedProgramme = programme
            
            // Resolve the actual stream URL and the Episode/Version PID
            let (url, resolvedPID) = try await bbcSounds.resolveStream(pid: programme.id)
            updatedProgramme.resolvedPID = resolvedPID
            
            // Fetch metadata to get the duration if not already present
            if let fullProg = try? await bbcSounds.getProgramme(pid: resolvedPID) {
                updatedProgramme.durationInSeconds = fullProg.durationInSeconds
            }
            
            player.play(url: url, programme: updatedProgramme)
        } catch {
            errorMessage = "Could not load stream: \(error.localizedDescription)"
        }
        isLoadingStream = false
    }

    func autoPlay(pid: String) async {
        // Log to the debug file from the view model
        let logMsg = "🚀 Auto-play Triggered for PID: \(pid)"
        print(logMsg)
        let logURL = URL(fileURLWithPath: "/tmp/bbc_sounds_debug.log")
        if let data = "[\(Date())] \(logMsg)\n".data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
        
        errorMessage = "Auto-playing PID: \(pid)..."
        
        // If it looks like a PID, bypass search and go straight to streaming
        if pid.hasPrefix("m") || pid.hasPrefix("p") || pid.count == 8 {
            do {
                let programme = try await bbcSounds.getProgramme(pid: pid)
                await playProgramme(programme)
            } catch {
                errorMessage = "Auto-play direct link failed: \(error.localizedDescription)"
                // Fallback to dummy if metadata fetch fails but URL might still work
                if let (url, resolvedPID) = try? await bbcSounds.resolveStream(pid: pid) {
                     var dummyProgramme = Programme(id: pid, index: 0, name: "Auto-Play Stream", channel: "BBC", duration: nil, description: pid, firstBroadcast: nil, artworkURL: nil, isLive: true)
                     dummyProgramme.resolvedPID = resolvedPID
                     player.play(url: url, programme: dummyProgramme)
                }
            }
            return
        }

        do {
            let results = try await bbcSounds.search(query: pid)
            if let first = results.first(where: { $0.id == pid }) ?? results.first {
                await playProgramme(first)
            } else {
                errorMessage = "Auto-play failed: PID \(pid) not found in search results."
            }
        } catch {
            errorMessage = "Auto-play search failed: \(error.localizedDescription)"
        }
    }

    func togglePlayPause() {
        player.isPlaying ? player.pause() : player.resume()
    }

    func handleCommandLineArgs() {
        let args = CommandLine.arguments
        if let playIndex = args.firstIndex(of: "--play"), playIndex + 1 < args.count {
            let pid = args[playIndex + 1]
            Task {
                await autoPlay(pid: pid)
            }
        }
    }

    func resumePlayback() {
        guard let session = resumeSession else { return }
        let programme = session.programme
        let time = session.time
        
        Task {
            await playProgramme(programme)
            player.seek(to: time)
        }
        resumeSession = nil
    }

    func dismissResume() {
        resumeSession = nil
        UserDefaults.standard.removeObject(forKey: "LastPlaybackSession")
    }

    private func loadSavedSession() {
        if let data = UserDefaults.standard.data(forKey: "LastPlaybackSession"),
           let session = try? JSONDecoder().decode(PlaybackSession.self, from: data) {
            // Only suggest resume if it's from the last 24 hours
            if abs(session.date.timeIntervalSinceNow) < 24 * 3600 {
                self.resumeSession = session
            } else {
                UserDefaults.standard.removeObject(forKey: "LastPlaybackSession")
            }
        }
    }

    func refreshCache() async {
        // No-op: The new BBCSoundsService uses live RMS Search API, so no cache is needed.
        errorMessage = "No cache refresh needed with modern API."
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if errorMessage == "No cache refresh needed with modern API." { errorMessage = nil }
        }
    }

    private func startMarquee(for segment: Segment) {
        let text = "\(segment.artist) - \(segment.title)"
        marqueeText = text
        marqueeStartTime = Date()
        
        Task {
            // Scroll for approx 8 seconds which is enough for one pass at 3x width
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await MainActor.run {
                if self.marqueeText == text {
                    self.marqueeText = nil
                    self.marqueeStartTime = nil
                }
            }
        }
    }
}
