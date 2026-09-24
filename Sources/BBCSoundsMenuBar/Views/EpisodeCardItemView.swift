import SwiftUI

struct EpisodeCardItemView: View {
    let episode: Programme
    let parentArtworkURL: String?
    @EnvironmentObject var viewModel: AppViewModel
    @State private var isHovered = false

    private var targetPID: String {
        episode.resolvedPID ?? episode.id
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

    var body: some View {
        Button {
            Task {
                var playableEp = episode
                playableEp.artworkURL = parentArtworkURL
                await viewModel.playProgramme(playableEp)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if let release = episode.releaseLabel {
                            Text(release)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        if let dur = episode.duration {
                            if episode.releaseLabel != nil {
                                Text("•")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            Text(dur)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let desc = episode.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if let progress = progress {
                        if progress > 0.95 {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 10))
                                Text("Played")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 2)
                        } else {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.1))
                                    Capsule().fill(Color.accentColor)
                                        .frame(width: geo.size.width * CGFloat(min(1.0, progress)))
                                }
                            }
                            .frame(width: 140, height: 3.5)
                            .padding(.top, 2)
                        }
                    }
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(isCurrentlyPlaying ? Color.accentColor : Color.primary.opacity(isHovered ? 0.12 : 0.08))
                        .frame(width: 28, height: 28)

                    Image(systemName: isCurrentlyPlaying ? (viewModel.player.isPlaying ? "pause.fill" : "play.fill") : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isCurrentlyPlaying ? .white : .primary)
                }
                .padding(.top, 1)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
