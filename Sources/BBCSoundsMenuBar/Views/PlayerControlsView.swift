import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var player: PlayerService
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            // Header: Artwork, Metadata, and Stop
            HStack(alignment: .center, spacing: 12) {
                // Square Artwork
                if let image = player.currentArtwork {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 54, height: 54)
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.1), radius: 2)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 54, height: 54)
                        .cornerRadius(6)
                        .overlay {
                             if player.isLoading {
                                 ProgressView().scaleEffect(0.6)
                             }
                        }
                }

                // Title & Channel
                VStack(alignment: .leading, spacing: 2) {
                    if let programme = player.currentProgramme {
                        Text(programme.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                        
                        Text(programme.channel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if player.isLoading {
                        Text("Loading...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Stop Button
                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Stop Playback")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Timeline / Scrubber
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 1)
                )
                .accentColor(.red)
                .controlSize(.small)
                
                HStack {
                    Text(formatTime(player.currentTime))
                    Spacer()
                    if player.duration > 0 {
                        Text(formatTime(player.duration))
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)

            // Transport & Volume Bar
            HStack(spacing: 0) {
                // Centered Transport Controls
                Spacer()
                HStack(spacing: 24) {
                    Button {
                        player.seek(by: -15)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.isPlaying ? player.pause() : player.resume()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                            .frame(width: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                    
                    Button {
                        player.seek(by: 15)
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                
                // Compact Volume Control
                HStack(spacing: 6) {
                    Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.1.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Slider(
                        value: Binding(
                            get: { Double(player.volume) },
                            set: { player.setVolume(Float($0)) }
                        ),
                        in: 0...1
                    )
                    .frame(width: 60)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
