import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showingSettings = false
    @State private var selectedTab = "shows"
    @State private var selectedShowForDetail: Programme? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Image(systemName: "radio")
                    .foregroundColor(.red)
                Text("BBC Sounds")
                    .font(.headline)
                Spacer()
                
                Button {
                    showingSettings.toggle()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingSettings) {
                    ProxySettingsView()
                        .environmentObject(viewModel)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)

            Divider()

            // Resume Prompt
            if let session = viewModel.resumeSession {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.accentColor)
                        Text("Resume playback?")
                            .font(.subheadline.bold())
                        Spacer()
                        Button {
                            viewModel.dismissResume()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Text(session.programme.name)
                        .font(.caption)
                        .lineLimit(1)
                    
                    HStack {
                        let timeStr = formatTime(session.time)
                        Text("At \(timeStr)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Resume") {
                            viewModel.resumePlayback()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
                .padding(8)
                
                Divider()
            }

            // Player (shown when stream active or loading)
            if viewModel.player.currentProgramme != nil || viewModel.isLoadingStream {
                PlayerControlsView(player: viewModel.player)
                    .environmentObject(viewModel)
            }

            // Error message
            if let err = viewModel.errorMessage {
                ScrollView {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                Divider()
            }

            // Detail view vs Tabs
            if let detailShow = selectedShowForDetail {
                ShowDetailView(
                    programme: detailShow,
                    onBack: { selectedShowForDetail = nil }
                )
                .environmentObject(viewModel)
            } else {
                Picker("", selection: $selectedTab) {
                    Text("My Shows").tag("shows")
                    Text("Search").tag("search")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                Divider()
                Spacer().frame(height: 1)

                VStack(spacing: 0) {
                    if selectedTab == "shows" {
                        BookmarksView(onSelectShow: { show in
                            selectedShowForDetail = show
                        })
                        .environmentObject(viewModel)
                    } else {
                        SearchView(onSelectShow: { show in
                            selectedShowForDetail = show
                        })
                        .environmentObject(viewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
