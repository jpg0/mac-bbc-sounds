import SwiftUI

struct TracklistView: View {
    @ObservedObject var player: PlayerService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TRACKLIST")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            
            if player.currentTracks.isEmpty {
                Text("No tracks found.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(player.currentTracks) { segment in
                            TrackRow(
                                segment: segment,
                                onSelect: { player.skipToTrack(segment) },
                                onSpotify: { player.openInSpotify(track: segment) }
                            )
                            
                            if segment != player.currentTracks.last {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .background(Color.primary.opacity(0.03))
    }
}

struct TrackRow: View {
    let segment: Segment
    let onSelect: () -> Void
    let onSpotify: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    // Time / Offset
                    Text(formatOffset(segment.startTime))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(segment.isNowPlaying ? .red : .secondary)
                        .frame(width: 32, alignment: .trailing)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(segment.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(segment.artist)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    if segment.isNowPlaying {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Button(action: onSpotify) {
                Image(systemName: "plus.circle")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .help("Search on Spotify")
            .padding(.trailing, 4)
        }
        .background(segment.isNowPlaying ? Color.red.opacity(0.05) : Color.clear)
    }
    
    private func formatOffset(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
