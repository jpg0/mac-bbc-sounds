import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showingSettings = false

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
                .padding(.trailing, 8)
                .popover(isPresented: $showingSettings) {
                    ProxySettingsView()
                        .environmentObject(viewModel)
                }

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Player (shown when stream active or loading)
            if viewModel.player.currentProgramme != nil || viewModel.isLoadingStream {
                PlayerControlsView(player: viewModel.player)
                    .environmentObject(viewModel)
                Divider()
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
                .frame(maxHeight: 120) // Limit the space used by the error log
                Divider()
            }

            SearchView()
                .environmentObject(viewModel)
        }
    }
}
