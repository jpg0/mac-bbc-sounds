import Foundation
import Combine

extension UserDefaults {
    static var app: UserDefaults {
        return UserDefaults(suiteName: "com.trillica.BBCSoundsMenuBar") ?? .standard
    }
}

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
    @Published var playbackHistory: [String: PlaybackSession] = [:]

    struct LatestEpisodeInfo: Codable, Equatable {
        let episodePID: String
        let vpid: String
        let title: String?
        let releaseLabel: String?
        let duration: String?
    }
    @Published var brandLatestEpisodes: [String: LatestEpisodeInfo] = [:]

    // History of fetched episodes per container
    @Published var brandEpisodes: [String: [Programme]] = [:]
    @Published var loadingEpisodes: Set<String> = []

    // Persistent Bookmarks
    @Published var bookmarkedShows: [Programme] = []
    @Published var lastBookmarkRefreshDate: Date? = nil
    @Published var isRefreshingBookmarks = false
    private var bookmarkAutoRefreshTask: Task<Void, Never>?

    // Proxy Settings
    @Published var proxyEnabled: Bool { didSet { UserDefaults.app.set(proxyEnabled, forKey: "ProxyEnabled"); updateServicesProxy() } }
    @Published var proxyHost: String { didSet { UserDefaults.app.set(proxyHost, forKey: "ProxyHost"); updateServicesProxy() } }
    @Published var proxyPort: String { didSet { UserDefaults.app.set(proxyPort, forKey: "ProxyPort"); updateServicesProxy() } }
    @Published var proxyUser: String { didSet { UserDefaults.app.set(proxyUser, forKey: "ProxyUser"); updateServicesProxy() } }
    @Published var proxyPass: String { didSet { UserDefaults.app.set(proxyPass, forKey: "ProxyPass"); updateServicesProxy() } }
    @Published var proxySkipVerify: Bool { didSet { UserDefaults.app.set(proxySkipVerify, forKey: "ProxySkipVerify"); updateServicesProxy() } }
    @Published var proxyForDiscovery: Bool { didSet { UserDefaults.app.set(proxyForDiscovery, forKey: "ProxyForDiscovery"); updateServicesProxy() } }

    let player: PlayerService
    private let bbcSounds: BBCSoundsService
    private var searchTask: Task<Void, Never>?
    private var marqueeTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.proxyEnabled = UserDefaults.app.bool(forKey: "ProxyEnabled")
        self.proxyHost = UserDefaults.app.string(forKey: "ProxyHost") ?? ""
        self.proxyPort = UserDefaults.app.string(forKey: "ProxyPort") ?? "89"
        self.proxyUser = UserDefaults.app.string(forKey: "ProxyUser") ?? ""
        self.proxyPass = UserDefaults.app.string(forKey: "ProxyPass") ?? ""
        self.proxySkipVerify = UserDefaults.app.bool(forKey: "ProxySkipVerify")
        self.proxyForDiscovery = UserDefaults.app.bool(forKey: "ProxyForDiscovery")
        
        let pService = PlayerService()
        self.player = pService
        let sounds = BBCSoundsService()
        self.bbcSounds = sounds
        pService.bbcSounds = sounds
        pService.startDiscovery()
        
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
        
        if let date = UserDefaults.app.object(forKey: "LastBookmarkRefreshDate") as? Date {
            self.lastBookmarkRefreshDate = date
        }
        
        loadSavedSession()
        loadPlaybackHistory()
        loadBookmarks()
        startBookmarkAutoRefreshTimer()
        
        player.onSessionSaved = { [weak self] in
            Task { @MainActor in
                self?.loadPlaybackHistory()
            }
        }
        
        updateServicesProxy()
        handleCommandLineArgs()
    }
    
    func updateServicesProxy() {
        let config = proxyEnabled ? ProxyConfiguration(host: proxyHost, port: Int(proxyPort) ?? 89, user: proxyUser, pass: proxyPass, skipVerify: proxySkipVerify) : nil
        player.proxyConfig = config
        Task {
            await bbcSounds.updateProxy(config: config, proxyForDiscovery: proxyForDiscovery)
        }
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
            resolveLatestEpisodes(for: searchResults)
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            searchResults = []
        }
        isSearching = false
    }

    private func resolveLatestEpisodes(for programmes: [Programme], force: Bool = false) {
        for programme in programmes {
            guard programme.type == "brand" || programme.type == "series" else { continue }
            let pid = programme.id
            if !force && brandLatestEpisodes[pid] != nil { continue }
            
            Task {
                do {
                    let latest = try await bbcSounds.resolveLatestEpisode(brandPID: pid)
                    await MainActor.run {
                        self.brandLatestEpisodes[pid] = LatestEpisodeInfo(
                            episodePID: latest.episodePID,
                            vpid: latest.vpid,
                            title: latest.title,
                            releaseLabel: latest.releaseLabel,
                            duration: latest.duration
                        )
                    }
                } catch {
                    print("⚠️ Failed to resolve latest episode for brand \(pid): \(error)")
                }
            }
        }
    }

    func loadEpisodes(for brandPID: String, force: Bool = false) {
        guard !loadingEpisodes.contains(brandPID) else { return }
        if !force && brandEpisodes[brandPID] != nil { return }
        loadingEpisodes.insert(brandPID)
        
        Task {
            do {
                let eps = try await bbcSounds.fetchContainerEpisodes(brandPID: brandPID)
                self.brandEpisodes[brandPID] = eps
                self.loadingEpisodes.remove(brandPID)
            } catch {
                print("⚠️ Failed to fetch episodes for \(brandPID): \(error)")
                self.loadingEpisodes.remove(brandPID)
            }
        }
    }

    func isBookmarked(_ programme: Programme) -> Bool {
        bookmarkedShows.contains(where: { $0.id == programme.id })
    }

    func toggleBookmark(_ programme: Programme) {
        if isBookmarked(programme) {
            bookmarkedShows.removeAll(where: { $0.id == programme.id })
        } else {
            bookmarkedShows.append(programme)
            // Resolve latest episode in background for the new bookmark
            resolveLatestEpisodes(for: [programme])
        }
        saveBookmarks()
    }

    private func loadBookmarks() {
        if let data = UserDefaults.app.data(forKey: "BookmarkedShows"),
           let list = try? JSONDecoder().decode([Programme].self, from: data) {
            self.bookmarkedShows = list
            refreshBookmarks(force: false)
        }
    }

    func refreshBookmarks(force: Bool = false) {
        guard !bookmarkedShows.isEmpty else { return }
        
        let shouldRefresh: Bool
        if force {
            shouldRefresh = true
        } else if let lastRefresh = lastBookmarkRefreshDate {
            // Refresh if older than 24 hours (86,400 seconds)
            shouldRefresh = Date().timeIntervalSince(lastRefresh) >= 24 * 3600
        } else {
            shouldRefresh = true
        }
        
        guard shouldRefresh else { return }
        
        isRefreshingBookmarks = true
        // Clear cached container episodes so expanding shows fetches fresh data
        brandEpisodes.removeAll()
        
        resolveLatestEpisodes(for: bookmarkedShows, force: true)
        
        let now = Date()
        lastBookmarkRefreshDate = now
        UserDefaults.app.set(now, forKey: "LastBookmarkRefreshDate")
        
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                self.isRefreshingBookmarks = false
            }
        }
    }

    private func startBookmarkAutoRefreshTimer() {
        bookmarkAutoRefreshTask?.cancel()
        bookmarkAutoRefreshTask = Task {
            while !Task.isCancelled {
                // Check every hour (3,600 seconds) whether 24h has elapsed
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.refreshBookmarks(force: false)
                }
            }
        }
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarkedShows) {
            UserDefaults.app.set(data, forKey: "BookmarkedShows")
        }
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
            
            // Auto-resume from history if available and not finished
            if let history = playbackHistory[resolvedPID], history.time > 15 {
                // If duration is missing or more than 30s left, resume. 
                // Otherwise start from beginning (assume finished)
                let remaining = (history.duration ?? Double(updatedProgramme.durationInSeconds)) - history.time
                if remaining > 30 || history.duration == nil {
                    player.seek(to: history.time)
                    print("🔄 Auto-resuming \(programme.name) from \(Int(history.time))s")
                }
            }
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
        UserDefaults.app.removeObject(forKey: "LastPlaybackSession")
    }

    private func loadSavedSession() {
        if let data = UserDefaults.app.data(forKey: "LastPlaybackSession"),
           let session = try? JSONDecoder().decode(PlaybackSession.self, from: data) {
            // Only suggest resume if it's from the last 24 hours
            if abs(session.date.timeIntervalSinceNow) < 24 * 3600 {
                self.resumeSession = session
            } else {
                UserDefaults.app.removeObject(forKey: "LastPlaybackSession")
            }
        }
    }

    private func loadPlaybackHistory() {
        let historyData = UserDefaults.app.dictionary(forKey: "PlaybackHistory") as? [String: Data] ?? [:]
        var loadedHistory: [String: PlaybackSession] = [:]
        let decoder = JSONDecoder()
        
        for (pid, data) in historyData {
            if let session = try? decoder.decode(PlaybackSession.self, from: data) {
                loadedHistory[pid] = session
            }
        }
        self.playbackHistory = loadedHistory
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
