import SwiftUI

struct BookmarksView: View {
    var onSelectShow: ((Programme) -> Void)? = nil
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Live Radio Quick-Tune Strip
            LiveStationsCarouselView()
                .environmentObject(viewModel)

            // Shows List Header
            HStack {
                HStack(spacing: 4) {
                    Text("SAVED SHOWS")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.secondary)

                    if !viewModel.bookmarkedShows.isEmpty {
                        Text("(\(viewModel.bookmarkedShows.count))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }

                Spacer()

                if viewModel.isRefreshingBookmarks {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    HStack(spacing: 6) {
                        Text("Click to view episodes")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary.opacity(0.6))

                        Button {
                            viewModel.refreshBookmarks(force: true)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh shows and episodes")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 4)

            // Shows Elevated Cards List
            if !viewModel.bookmarkedShows.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.bookmarkedShows) { programme in
                            ShowCardView(
                                programme: programme,
                                onSelect: { onSelectShow?(programme) },
                                onPlay: {
                                    Task {
                                        await viewModel.playProgramme(programme)
                                    }
                                }
                            )
                            .environmentObject(viewModel)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .padding(.bottom, 12)
                }
            } else {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No saved shows")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Search for your favorite BBC shows or podcasts and tap the bookmark icon to follow them here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                Spacer()
            }
        }
        .onAppear {
            viewModel.refreshBookmarks(force: false)
        }
    }
}
