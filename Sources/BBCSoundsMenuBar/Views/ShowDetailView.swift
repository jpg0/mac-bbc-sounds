import SwiftUI

struct ShowDetailView: View {
    let programme: Programme
    let onBack: () -> Void
    @EnvironmentObject var viewModel: AppViewModel

    private var episodes: [Programme] {
        viewModel.brandEpisodes[programme.id] ?? []
    }

    private var isLoading: Bool {
        viewModel.loadingEpisodes.contains(programme.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Navigation Header
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("All Shows")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    viewModel.toggleBookmark(programme)
                } label: {
                    Image(systemName: viewModel.isBookmarked(programme) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14))
                        .foregroundColor(viewModel.isBookmarked(programme) ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Show Hero Header Card
                    HStack(alignment: .top, spacing: 12) {
                        if let artworkURL = programme.artworkURL, let url = URL(string: artworkURL) {
                            AsyncImage(url: url) { image in
                                image.resizable()
                            } placeholder: {
                                Color.secondary.opacity(0.15)
                            }
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .cornerRadius(8)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Image(systemName: "radio")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(programme.name)
                                .font(.system(size: 15, weight: .bold))
                                .lineLimit(2)

                            Text(programme.channel)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let latest = viewModel.brandLatestEpisodes[programme.id],
                               let release = latest.releaseLabel {
                                Text("Latest: \(release)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }

                            Button {
                                Task {
                                    await viewModel.playProgramme(programme)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10))
                                    Text("Play Latest")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(10)

                    // Show Synopsis
                    if let desc = programme.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(4)
                            .padding(.horizontal, 2)
                    }

                    // Episodes Section Header
                    HStack {
                        Text("Available Episodes")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary)

                        if !episodes.isEmpty {
                            Text("(\(episodes.count))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }
                    .padding(.top, 4)

                    // Episodes List
                    if isLoading && episodes.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Loading episodes...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 24)
                            Spacer()
                        }
                    } else if episodes.isEmpty {
                        Text("No episodes available for this show.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(episodes) { ep in
                                EpisodeCardItemView(episode: ep, parentArtworkURL: programme.artworkURL)
                                    .environmentObject(viewModel)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .task {
            viewModel.loadEpisodes(for: programme.id)
        }
    }
}
