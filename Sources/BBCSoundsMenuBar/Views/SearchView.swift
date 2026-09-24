import SwiftUI

struct SearchView: View {
    var onSelectShow: ((Programme) -> Void)? = nil
    @EnvironmentObject var viewModel: AppViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search input row
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))

                TextField("Search BBC shows, podcasts, artists...", text: $viewModel.searchQuery)
                    .focused($isSearchFocused)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onChange(of: viewModel.searchQuery) { _ in
                        viewModel.onSearchQueryChanged()
                    }
                
                if viewModel.isSearching {
                    ProgressView()
                        .scaleEffect(0.65)
                }
                
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.8))
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Results / empty states
            if !viewModel.searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.searchResults) { programme in
                            if programme.type == "brand" || programme.type == "series" {
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
                            } else {
                                EpisodeCardItemView(
                                    episode: programme,
                                    parentArtworkURL: programme.artworkURL
                                )
                                .environmentObject(viewModel)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
            } else if viewModel.searchQuery.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Search BBC Sounds")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Find radio stations, podcasts, and past broadcasts across the entire BBC library.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            } else {
                Spacer()
            }
        }
    }
}
