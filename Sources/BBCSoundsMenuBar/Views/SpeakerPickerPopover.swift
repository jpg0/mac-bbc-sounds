import SwiftUI

/// Item representing an audio destination in the speaker picker.
struct SpeakerPickerItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let groupBadge: String?
    let subtitle: String?
    let isActive: Bool
    let isOnline: Bool
    let volume: Int?
    let target: AudioOutputTarget
}

/// Popover interface for selecting audio output targets (This Mac vs discovered Sonos speakers/groups).
struct SpeakerPickerPopover: View {
    @ObservedObject var player: PlayerService
    @State private var deviceVolumes: [String: Int] = [:]
    @State private var hoveredTargetId: String? = nil
    @State private var volumeLoadTask: Task<Void, Never>?
    @State private var isShowingAddIP: Bool = false
    @State private var manualIP: String = ""

    init(player: PlayerService) {
        self.player = player
    }

    private var macItem: SpeakerPickerItem {
        let macVol: Int = {
            if player.outputTarget.isMac {
                return Int(round(player.volume * 100))
            }
            let saved = UserDefaults.app.value(forKey: "PlayerVolume") as? Float ?? 0.7
            return Int(round(saved * 100))
        }()

        return SpeakerPickerItem(
            id: "thisMac",
            icon: "laptopcomputer",
            title: "This Mac",
            groupBadge: nil,
            subtitle: "Built-in Speakers",
            isActive: player.outputTarget.isMac,
            isOnline: true,
            volume: macVol,
            target: .thisMac
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Label("Audio Output", systemImage: "speaker.wave.2")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button {
                    player.scanForDevices()
                } label: {
                    if player.discoveryService.isScanning {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(player.discoveryService.isScanning)
                .help("Scan for Sonos speakers")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingAddIP.toggle()
                    }
                } label: {
                    Image(systemName: isShowingAddIP ? "xmark" : "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Connect to Sonos speaker by IP (useful across VLANs/subnets)")
            }
            .padding(.bottom, 2)

            if isShowingAddIP {
                HStack(spacing: 6) {
                    TextField("Speaker IP (e.g. 192.168.11.181)", text: $manualIP)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit {
                            submitManualIP()
                        }
                    Button("Connect") {
                        submitManualIP()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(manualIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.vertical, 2)
            }

            Divider()

            // This Mac Option
            deviceRow(item: macItem)

            Divider()

            // Sonos Speakers Section
            HStack {
                Text("SONOS SPEAKERS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()

                if player.discoveryService.isScanning {
                    Text("Searching...")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            if player.discoveryService.discoveredDevices.isEmpty {
                VStack(spacing: 8) {
                    if player.discoveryService.isScanning {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Searching for speakers...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        Text("No Sonos speakers found on network.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)

                        HStack(spacing: 8) {
                            Button {
                                player.scanForDevices()
                            } label: {
                                Text("Scan Network")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                withAnimation {
                                    isShowingAddIP = true
                                }
                            } label: {
                                Text("Connect by IP…")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 4) {
                    ForEach(player.discoveryService.discoveredDevices) { device in
                        let isActive = player.outputTarget.sonosDevice?.id == device.id
                        let currentVol: Int? = {
                            if isActive {
                                return Int(round(player.volume * 100))
                            }
                            return deviceVolumes[device.id]
                        }()

                        let item = SpeakerPickerItem(
                            id: device.id,
                            icon: device.groupBadge != nil ? "hifispeaker.2.fill" : "hifispeaker.fill",
                            title: device.name,
                            groupBadge: device.groupBadge,
                            subtitle: device.modelName,
                            isActive: isActive,
                            isOnline: true,
                            volume: currentVol,
                            target: .sonos(device)
                        )

                        deviceRow(item: item)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 270)
        .task {
            triggerVolumeRefresh()
        }
        .onChange(of: player.discoveryService.discoveredDevices) { _ in
            triggerVolumeRefresh()
        }
    }

    @ViewBuilder
    private func deviceRow(item: SpeakerPickerItem) -> some View {
        Button {
            Task {
                try? await player.setOutputTarget(item.target)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 16))
                    .foregroundColor(item.isActive ? .blue : .primary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 12, weight: item.isActive ? .semibold : .regular))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let badge = item.groupBadge {
                            Text(badge)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 4) {
                        // Online indicator dot
                        Circle()
                            .fill(item.isOnline ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 5, height: 5)

                        Text(item.isOnline ? "Online" : "Offline")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)

                        if let subtitle = item.subtitle {
                            Text("• \(subtitle)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Volume Level
                if let vol = item.volume {
                    HStack(spacing: 3) {
                        Image(systemName: vol == 0 ? "speaker.slash.fill" : "speaker.wave.1.fill")
                            .font(.system(size: 9))
                        Text("\(vol)%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(item.isActive ? .blue : .secondary)
                }

                // Active checkmark
                if item.isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                        .frame(width: 14)
                } else {
                    Spacer().frame(width: 14)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(item.isActive ? Color.blue.opacity(0.1) : (hoveredTargetId == item.id ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            if isHovered {
                hoveredTargetId = item.id
            } else if hoveredTargetId == item.id {
                hoveredTargetId = nil
            }
        }
    }

    private func triggerVolumeRefresh() {
        volumeLoadTask?.cancel()
        volumeLoadTask = Task {
            for device in player.discoveryService.discoveredDevices {
                guard !Task.isCancelled else { return }
                if player.outputTarget.sonosDevice?.id == device.id {
                    continue
                }
                if let vol = await player.fetchVolume(for: device) {
                    guard !Task.isCancelled else { return }
                    deviceVolumes[device.id] = vol
                }
            }
        }
    }

    private func submitManualIP() {
        let trimmed = manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        player.addKnownSonosHost(trimmed)
        manualIP = ""
        withAnimation {
            isShowingAddIP = false
        }
    }
}
