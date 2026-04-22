import SwiftUI

struct ProgrammeRowView: View {
    let programme: Programme
    @EnvironmentObject var viewModel: AppViewModel

    private var isCurrentlyPlaying: Bool {
        viewModel.player.currentProgramme?.id == programme.id
    }

    private var progress: Double? {
        guard let session = viewModel.playbackHistory[programme.id], 
              let dur = session.duration, dur > 0 else { return nil }
        return session.time / dur
    }

    var body: some View {
        Button {
            Task {
                await viewModel.playProgramme(programme)
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
                            .foregroundColor(.red)
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
                                            .fill(Color.red)
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

                    if let desc = programme.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
