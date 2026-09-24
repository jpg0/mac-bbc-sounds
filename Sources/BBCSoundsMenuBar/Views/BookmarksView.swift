import SwiftUI

struct BookmarksView: View {
    var onSelectShow: ((Programme) -> Void)? = nil
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Live Radio Quick-Tune Strip
            LiveStationsCarouselView()
                .environmentObject(viewModel)

            Divider()

            // Shows List Header
            HStack {
                Text("MY SHOWS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                if !viewModel.bookmarkedShows.isEmpty {
                    Text("(\(viewModel.bookmarkedShows.count))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if viewModel.isRefreshingBookmarks {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
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
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Shows List
            if !viewModel.bookmarkedShows.isEmpty {
                List(viewModel.bookmarkedShows) { programme in
                    ProgrammeRowView(programme: programme, onSelectShow: onSelectShow)
                        .environmentObject(viewModel)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
                .listStyle(.plain)
            } else {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
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
