import SwiftUI

struct SearchView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search input row
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search BBC Radio...", text: $viewModel.searchQuery)
                    .focused($isSearchFocused)
                    .onChange(of: viewModel.searchQuery) { _ in
                        viewModel.onSearchQueryChanged()
                    }
                
                if viewModel.isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .contentShape(Rectangle())
            .onTapGesture {
                isSearchFocused = true
            }
            .cornerRadius(8)
            .padding(8)

            Divider()

            // Results / empty states
            if !viewModel.searchResults.isEmpty {
                List(viewModel.searchResults) { programme in
                    ProgrammeRowView(programme: programme)
                        .environmentObject(viewModel)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
                .listStyle(.plain)
            } else if viewModel.searchQuery.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "radio")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Search for BBC Radio shows")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                // If we are searching or have a query but no results yet, 
                // stay empty to keep the search bar at the top.
                Spacer()
            }
        }
    }
}
