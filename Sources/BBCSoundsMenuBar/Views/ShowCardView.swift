import SwiftUI

struct ShowCardView: View {
    let programme: Programme
    let onSelect: () -> Void
    let onPlay: () -> Void
    @EnvironmentObject var viewModel: AppViewModel
    @State private var isHovered = false

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

    private var episodes: [Programme] {
        viewModel.brandEpisodes[programme.id] ?? []
    }

    private var unplayedCount: Int? {
        guard !episodes.isEmpty else { return nil }
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

    private var latestEpisode: AppViewModel.LatestEpisodeInfo? {
        viewModel.brandLatestEpisodes[programme.id]
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                // 1. Artwork Thumbnail with rounded corner & progress bar
                ZStack(alignment: .bottom) {
                    if let artworkURL = programme.artworkURL, let url = URL(string: artworkURL) {
                        AsyncImage(url: url) { image in
                            image.resizable()
                        } placeholder: {
                            Color.secondary.opacity(0.12)
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.12))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "radio")
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                            )
                    }

                    // Progress bar overlay at bottom of thumbnail
                    if let progress = progress, !programme.isLive {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.black.opacity(0.6))
                                Rectangle().fill(Color.accentColor)
                                    .frame(width: geo.size.width * CGFloat(min(1.0, progress)))
                            }
                        }
                        .frame(height: 3)
                    }

                    // Active playing indicator overlay
                    if isCurrentlyPlaying {
                        ZStack {
                            Color.black.opacity(0.4)
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 11))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 48, height: 48)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )

                // 2. Middle Content Column
                VStack(alignment: .leading, spacing: 2.5) {
                    // Top row: Title + Pill Badge + Episodes Count / Chevron
                    HStack(alignment: .center, spacing: 6) {
                        Text(programme.name)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let count = unplayedCount {
                            if count > 0 {
                                Text("\(count) unplayed")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Color.accentColor.opacity(0.18))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(10)
                            } else {
                                HStack(spacing: 2) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7.5, weight: .bold))
                                    Text("Played")
                                        .font(.system(size: 8.5, weight: .medium))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.secondary.opacity(0.12))
                                .foregroundColor(.secondary)
                                .cornerRadius(10)
                            }
                        } else if hasUnplayedLatest {
                            Text("New")
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.accentColor.opacity(0.18))
                                .foregroundColor(.accentColor)
                                .cornerRadius(10)
                        }

                        Spacer()

                        // Episode count drill-down prompt (matching mockup "15 Ep ›")
                        if !episodes.isEmpty {
                            Text("\(episodes.count) Ep ›")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isHovered ? .accentColor : .secondary)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(isHovered ? .accentColor : .secondary.opacity(0.5))
                        }
                    }

                    // Middle line: Latest episode title
                    if let latest = latestEpisode, let epTitle = latest.title, !epTitle.isEmpty {
                        Text(epTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary.opacity(0.85))
                            .lineLimit(1)
                    } else if let desc = programme.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    // Bottom line: Channel • Date / Duration
                    HStack(spacing: 4) {
                        Text(programme.channel.isEmpty ? "BBC" : programme.channel)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        if let latest = latestEpisode {
                            if let release = latest.releaseLabel {
                                Text("•")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary.opacity(0.6))
                                Text(release)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }
                            if let dur = latest.duration {
                                Text("•")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary.opacity(0.6))
                                Text(dur)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }
                        } else if let dur = programme.duration {
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text(dur)
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 3. Circular Play Button on the right
                Button(action: onPlay) {
                    ZStack {
                        Circle()
                            .fill(isCurrentlyPlaying ? Color.accentColor : Color.primary.opacity(isHovered ? 0.12 : 0.08))
                            .frame(width: 30, height: 30)

                        Image(systemName: isCurrentlyPlaying ? (viewModel.player.isPlaying ? "pause.fill" : "play.fill") : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isCurrentlyPlaying ? .white : .primary)
                    }
                }
                .buttonStyle(.plain)
                .help(isCurrentlyPlaying ? (viewModel.player.isPlaying ? "Pause" : "Resume") : "Play Latest Episode")
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.07), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            if viewModel.brandEpisodes[programme.id] == nil {
                viewModel.loadEpisodes(for: programme.id)
            }
        }
    }
}
