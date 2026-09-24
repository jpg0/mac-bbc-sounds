import SwiftUI

struct ProgrammeRowView: View {
    let programme: Programme
    var onSelectShow: ((Programme) -> Void)? = nil
    @EnvironmentObject var viewModel: AppViewModel

    @State private var isExpanded = false

    private var targetPID: String {
        if let latest = viewModel.brandLatestEpisodes[programme.id] {
            return latest.vpid
        }
        return programme.resolvedPID ?? programme.id
    }

    private var isCurrentlyPlaying: Bool {
        let activePID = viewModel.player.currentProgramme?.resolvedPID ?? viewModel.player.currentProgramme?.id
        return activePID == targetPID
    }

    private var progress: Double? {
        guard let session = viewModel.playbackHistory[targetPID], 
              let dur = session.duration, dur > 0 else { return nil }
        return session.time / dur
    }

    private var unplayedCount: Int? {
        guard programme.type == "brand" || programme.type == "series" else { return nil }
        guard let episodes = viewModel.brandEpisodes[programme.id], !episodes.isEmpty else { return nil }
        return episodes.filter { ep in
            let pid = ep.resolvedPID ?? ep.id
            guard let session = viewModel.playbackHistory[pid],
                  let dur = session.duration, dur > 0 else {
                return true
            }
            return (session.time / dur) < 0.9
        }.count
    }

    private var hasUnplayedLatest: Bool {
        guard let latest = viewModel.brandLatestEpisodes[programme.id] else { return false }
        if let session = viewModel.playbackHistory[latest.vpid], let dur = session.duration, dur > 0 {
            return (session.time / dur) < 0.9
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if let onSelect = onSelectShow, (programme.type == "brand" || programme.type == "series") {
                    onSelect(programme)
                } else {
                    Task {
                        await viewModel.playProgramme(programme)
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    ZStack {
                        if let artworkURL = programme.artworkURL, let url = URL(string: artworkURL) {
                            AsyncImage(url: url) { image in
                                image.resizable()
                            } placeholder: {
                                Color.secondary.opacity(0.1)
                            }
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 48)
                            .cornerRadius(4)
                        } else {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: 48, height: 48)
                                .cornerRadius(4)
                        }
                        
                        if isCurrentlyPlaying {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.accentColor)
                                .font(.caption)
                        }
                        
                        // Progress bar overlay
                        if let progress = progress, !programme.isLive {
                            VStack {
                                Spacer()
                                if progress > 0.95 {
                                    ZStack {
                                        Color.black.opacity(0.4)
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 14))
                                    }
                                    .frame(height: 16)
                                } else {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                            Rectangle()
                                                .fill(Color.accentColor)
                                                .frame(width: geo.size.width * progress)
                                        }
                                    }
                                    .frame(height: 3)
                                }
                            }
                        }
                    }
                    .frame(width: 48, height: 48)
                    .cornerRadius(4)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .center, spacing: 4) {
                            Text(programme.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            
                            if programme.isLive {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.red)
                            }
                            
                            if programme.type == "brand" {
                                if let count = unplayedCount {
                                    if count > 0 {
                                        Text("\(count) unplayed")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.15))
                                            .foregroundColor(.accentColor)
                                            .cornerRadius(8)
                                    } else {
                                        HStack(spacing: 2) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 8, weight: .bold))
                                            Text("Played")
                                                .font(.system(size: 9, weight: .medium))
                                        }
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.12))
                                        .foregroundColor(.secondary)
                                        .cornerRadius(8)
                                    }
                                } else if hasUnplayedLatest {
                                    Text("New")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundColor(.accentColor)
                                        .cornerRadius(8)
                                } else {
                                    Text("Show")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundColor(.accentColor)
                                        .cornerRadius(3)
                                }
                            }
                        }

                        HStack(spacing: 4) {
                            Text(programme.channel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let dur = programme.duration {
                                Text("·")
                                    .foregroundColor(.secondary)
                                Text(dur)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if programme.type == "episode", let release = programme.releaseLabel {
                            Text("Released: \(release)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.top, 1)
                        }

                        if let latest = viewModel.brandLatestEpisodes[programme.id] {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                    Text("Latest: \(latest.releaseLabel ?? "")")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    if let latestDur = latest.duration {
                                        Text("· \(latestDur)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                if let title = latest.title, !title.isEmpty {
                                    Text(title)
                                        .font(.system(size: 11))
                                        .foregroundColor(.primary.opacity(0.8))
                                        .lineLimit(1)
                                }
                            }
                            .padding(.top, 2)
                        }

                        if let desc = programme.description {
                            Text(desc)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    if programme.type == "brand" || programme.type == "series" {
                        Button {
                            viewModel.toggleBookmark(programme)
                        } label: {
                            Image(systemName: viewModel.isBookmarked(programme) ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 13))
                                .foregroundColor(viewModel.isBookmarked(programme) ? .accentColor : .secondary)
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                        
                        if let onSelect = onSelectShow {
                            Button {
                                Task {
                                    await viewModel.playProgramme(programme)
                                }
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.accentColor)
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                onSelect(programme)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                isExpanded.toggle()
                            } label: {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, programme.type == "brand" {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .padding(.vertical, 4)
                    
                    if viewModel.loadingEpisodes.contains(programme.id) {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.6)
                                .padding(8)
                            Spacer()
                        }
                    } else if let episodes = viewModel.brandEpisodes[programme.id] {
                        if episodes.isEmpty {
                            Text("No episodes found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 56)
                                .padding(.vertical, 4)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(episodes) { ep in
                                    EpisodeRowView(episode: ep, parentArtworkURL: programme.artworkURL)
                                }
                            }
                            .padding(.leading, 12)
                            .padding(.bottom, 6)
                        }
                    }
                }
                .task(id: isExpanded) {
                    if isExpanded && viewModel.brandEpisodes[programme.id] == nil {
                        viewModel.loadEpisodes(for: programme.id)
                    }
                }
                .onChange(of: viewModel.lastBookmarkRefreshDate) { _ in
                    if isExpanded {
                        viewModel.loadEpisodes(for: programme.id, force: true)
                    }
                }
            }
        }
        .onAppear {
            if (programme.type == "brand" || programme.type == "series") && viewModel.brandEpisodes[programme.id] == nil {
                viewModel.loadEpisodes(for: programme.id)
            }
        }
    }
}

struct EpisodeRowView: View {
    let episode: Programme
    let parentArtworkURL: String?
    @EnvironmentObject var viewModel: AppViewModel
    
    private var isCurrentlyPlaying: Bool {
        let activePID = viewModel.player.currentProgramme?.resolvedPID ?? viewModel.player.currentProgramme?.id
        let targetPID = episode.resolvedPID ?? episode.id
        return activePID == targetPID
    }
    
    private var progress: Double? {
        let targetPID = episode.resolvedPID ?? episode.id
        guard let session = viewModel.playbackHistory[targetPID],
              let dur = session.duration, dur > 0 else { return nil }
        return session.time / dur
    }
    
    var body: some View {
        Button {
            Task {
                var playableEp = episode
                playableEp.artworkURL = parentArtworkURL
                await viewModel.playProgramme(playableEp)
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    if isCurrentlyPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.accentColor)
                            .font(.caption)
                    } else {
                        Image(systemName: "play.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    if let progress = progress {
                        VStack {
                            Spacer()
                            if progress > 0.95 {
                                ZStack {
                                    Color.black.opacity(0.4)
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 10))
                                }
                                .frame(height: 12)
                            } else {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                        Rectangle()
                                            .fill(Color.accentColor)
                                            .frame(width: geo.size.width * progress)
                                    }
                                }
                                .frame(height: 2)
                            }
                        }
                    }
                }
                .frame(width: 24, height: 24)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(3)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(episode.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        if let release = episode.releaseLabel {
                            Text(release)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        if let dur = episode.duration {
                            Text("·")
                                .foregroundColor(.secondary)
                            Text(dur)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isCurrentlyPlaying ? Color.secondary.opacity(0.05) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}
