import SwiftUI

struct ProgrammeRowView: View {
    let programme: Programme
    @EnvironmentObject var viewModel: AppViewModel

    private var isCurrentlyPlaying: Bool {
        viewModel.player.currentProgramme?.id == programme.id
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
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(programme.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)

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
