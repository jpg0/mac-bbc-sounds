import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var player: PlayerService
    @Environment(\.colorScheme) var colorScheme
    @State private var showingSpeakerPicker = false
    @State private var isTracklistExpanded = false
    @State private var preMuteVolume: Float = 0.5
    @State private var isDraggingScrubber = false
    @State private var scrubPosition: Double = 0

    private var nowPlayingTrack: Segment? {
        player.currentTracks.first(where: { $0.isNowPlaying })
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header: Artwork, Metadata, Action Buttons
            HStack(alignment: .center, spacing: 10) {
                // Square Artwork
                if let image = player.currentArtwork {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 52, height: 52)
                        .overlay {
                            if player.isLoading {
                                ProgressView().scaleEffect(0.6)
                            } else {
                                Image(systemName: "music.note")
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                            }
                        }
                }

                // Title & Channel
                VStack(alignment: .leading, spacing: 2) {
                    if let programme = player.currentProgramme {
                        HStack(alignment: .center, spacing: 4) {
                            Text(programme.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            
                            if programme.isLive {
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 4, height: 4)
                                    Text("LIVE")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundColor(.red)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(3)
                            }
                        }
                        
                        Text(programme.channel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        // Sonos Output Status Indicator
                        if case .sonos(let device) = player.outputTarget {
                            HStack(spacing: 4) {
                                Image(systemName: "hifispeaker.fill")
                                    .font(.system(size: 9))
                                Text(player.isPlaying ? "Playing to \(device.displayName)" : ((player.isLoading || player.sonosController?.transportState == .transitioning) ? "Connecting to \(device.displayName)..." : "Connected to \(device.displayName)"))
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(4)
                            .padding(.top, 1)
                        }
                        
                        if let track = nowPlayingTrack {
                            HStack(spacing: 4) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 9))
                                Text("\(track.title) — \(track.artist)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.accentColor)
                                    .lineLimit(1)
                            }
                            .padding(.top, 1)
                        }
                    } else if player.isLoading {
                        Text("Loading...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)

                        if case .sonos(let device) = player.outputTarget {
                            HStack(spacing: 4) {
                                Image(systemName: "hifispeaker.fill")
                                    .font(.system(size: 9))
                                Text("Connecting to \(device.displayName)...")
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(4)
                            .padding(.top, 1)
                        }
                    }
                }
                
                Spacer()
                
                // Actions: Spotify, Tracklist Toggle & Speaker Picker
                HStack(spacing: 10) {
                    if let track = nowPlayingTrack {
                        Button {
                            player.openInSpotify(track: track)
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 15))
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        .help("Search on Spotify")
                    }

                    // Tracklist Drawer Toggle Button
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isTracklistExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 14))
                            .foregroundColor(isTracklistExpanded ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Tracklist & Chapters")

                    // Speaker Route Button
                    Button {
                        showingSpeakerPicker.toggle()
                    } label: {
                        Image(systemName: player.outputTarget.isSonos ? "hifispeaker.2.fill" : "airplayaudio")
                            .font(.system(size: 14))
                            .foregroundColor(player.outputTarget.isSonos ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(player.outputTarget.isSonos ? "Streaming to \(player.outputTarget.displayName)" : "Audio Output")
                    .popover(isPresented: $showingSpeakerPicker, arrowEdge: .bottom) {
                        SpeakerPickerPopover(player: player)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            // Timeline / Scrubber
            VStack(spacing: 3) {
                Slider(
                    value: Binding(
                        get: { isDraggingScrubber ? scrubPosition : player.currentTime },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            isDraggingScrubber = true
                            scrubPosition = player.currentTime
                        } else {
                            isDraggingScrubber = false
                            player.seek(to: scrubPosition)
                        }
                    }
                )
                .accentColor(.accentColor)
                .controlSize(.small)
                .disabled(player.currentProgramme?.isLive == true || player.duration <= 0)
                
                HStack {
                    Text(formatTime(isDraggingScrubber ? scrubPosition : player.currentTime))
                    Spacer()
                    if let prog = player.currentProgramme, prog.isLive {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 4, height: 4)
                            Text("LIVE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.red)
                        }
                    } else if player.duration > 0 {
                        Text(formatTime(player.duration))
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            // Transport Row: Centered 5-Button Controls + Squeezed Right-Aligned Volume
            ZStack(alignment: .trailing) {
                // True-Centered Transport Cluster
                HStack(spacing: 16) {
                    // Skip Back / Previous Track
                    Button {
                        player.skipToPreviousTrack()
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .disabled(player.currentTracks.isEmpty)
                    .help("Previous Track (Cmd+Left)")

                    // Rewind 15s
                    Button {
                        player.seek(by: -15)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(player.currentProgramme?.isLive == true ? .secondary.opacity(0.4) : .primary)
                    .disabled(player.currentProgramme?.isLive == true)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .help(player.currentProgramme?.isLive == true ? "Seeking unavailable on live radio" : "Rewind 15 seconds")

                    // Centered Play / Pause Hero Button
                    Button {
                        player.isPlaying ? player.pause() : player.resume()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                    .keyboardShortcut(.space, modifiers: [])
                    .help(player.isPlaying ? "Pause" : "Play")

                    // Forward 15s
                    Button {
                        player.seek(by: 15)
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(player.currentProgramme?.isLive == true ? .secondary.opacity(0.4) : .primary)
                    .disabled(player.currentProgramme?.isLive == true)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help(player.currentProgramme?.isLive == true ? "Seeking unavailable on live radio" : "Forward 15 seconds")

                    // Skip Forward / Next Track
                    Button {
                        player.skipToNextTrack()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .disabled(player.currentTracks.isEmpty)
                    .help("Next Track (Cmd+Right)")
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Squeezed Volume Slider on the Right
                HStack(spacing: 4) {
                    Button {
                        if player.volume > 0 {
                            preMuteVolume = player.volume
                            player.setVolume(0)
                        } else {
                            player.setVolume(preMuteVolume > 0 ? preMuteVolume : 0.5)
                        }
                    } label: {
                        Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.1.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Slider(
                        value: Binding(
                            get: { Double(player.volume) },
                            set: { player.setVolume(Float($0)) }
                        ),
                        in: 0...1
                    )
                    .frame(width: 58)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .padding(.bottom, 2)

            // Contextual Tracklist Drawer
            if isTracklistExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                        .padding(.vertical, 4)

                    HStack {
                        Text("TRACKLIST")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(player.currentTracks.count) tracks")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)

                    if player.currentTracks.isEmpty {
                        Text("No track segments reported for this broadcast.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(player.currentTracks) { segment in
                                    TrackRow(
                                        segment: segment,
                                        onSelect: { player.skipToTrack(segment) },
                                        onSpotify: { player.openInSpotify(track: segment) }
                                    )
                                    if segment != player.currentTracks.last {
                                        Divider().padding(.leading, 40)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 140)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}
