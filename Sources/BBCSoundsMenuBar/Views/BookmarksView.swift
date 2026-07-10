import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.bookmarkedShows.isEmpty {
                List(viewModel.bookmarkedShows) { programme in
                    ProgrammeRowView(programme: programme)
                        .environmentObject(viewModel)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
                .listStyle(.plain)
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bookmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No bookmarked shows")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Search for a show and tap the bookmark icon to save it here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                Spacer()
            }
        }
    }
}
