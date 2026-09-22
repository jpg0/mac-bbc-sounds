import SwiftUI

struct ProxySettingsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("HTTPS Proxy Settings")
                .font(.headline)
            
            Toggle("Enable Proxy", isOn: $viewModel.proxyEnabled)
                .toggleStyle(.switch)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Host:").frame(width: 80, alignment: .trailing)
                    TextField("gb822.nordvpn.com", text: $viewModel.proxyHost)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("Port:").frame(width: 80, alignment: .trailing)
                    TextField("89", text: $viewModel.proxyPort)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("Username:").frame(width: 80, alignment: .trailing)
                    TextField("Service Username", text: $viewModel.proxyUser)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("Password:").frame(width: 80, alignment: .trailing)
                    SecureField("Service Password", text: $viewModel.proxyPass)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Spacer().frame(width: 80)
                        Toggle("Skip SSL Verification", isOn: $viewModel.proxySkipVerify)
                            .font(.caption)
                    }
                    HStack {
                        Spacer().frame(width: 80)
                        Toggle("Use Proxy for Discovery", isOn: $viewModel.proxyForDiscovery)
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sonos Cross-VLAN Streaming")
                        .font(.system(size: 10, weight: .semibold))
                    Text("If Sonos is on an IoT VLAN, allow incoming TCP from IoT to port 52800 on your LAN.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(6)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(4)
            }
            .disabled(!viewModel.proxyEnabled)
            
            Divider().padding(.vertical, 8)
            
            Button {
                Task { await viewModel.refreshCache() }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh BBC Programme Cache")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isSearching)

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 320)
    }
}
