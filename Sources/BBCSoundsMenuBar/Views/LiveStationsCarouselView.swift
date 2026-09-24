import SwiftUI

struct LiveStation: Identifiable {
    let id: String
    let badge: String
    let name: String
}

struct LiveStationsCarouselView: View {
    @EnvironmentObject var viewModel: AppViewModel

    private let stations: [LiveStation] = [
        LiveStation(id: "bbc_radio_one", badge: "1", name: "Radio 1"),
        LiveStation(id: "bbc_radio_two", badge: "2", name: "Radio 2"),
        LiveStation(id: "bbc_radio_fourfm", badge: "4", name: "Radio 4"),
        LiveStation(id: "bbc_6music", badge: "6M", name: "6 Music"),
        LiveStation(id: "bbc_radio_five_live", badge: "5L", name: "5 Live"),
        LiveStation(id: "bbc_world_service", badge: "WS", name: "World Service"),
        LiveStation(id: "bbc_1xtra", badge: "1X", name: "1Xtra")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("LIVE RADIO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)

                Spacer()
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stations) { station in
                        stationButton(station)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func stationButton(_ station: LiveStation) -> some View {
        let activePID = viewModel.player.currentProgramme?.resolvedPID ?? viewModel.player.currentProgramme?.id
        let isPlayingThisStation = activePID == station.id

        Button {
            let prog = Programme(
                id: station.id,
                index: 0,
                name: station.name,
                channel: "BBC Radio",
                duration: nil,
                description: "Live BBC Broadcast",
                firstBroadcast: nil,
                artworkURL: nil,
                isLive: true,
                resolvedPID: station.id,
                type: "live"
            )
            Task {
                await viewModel.playProgramme(prog)
            }
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isPlayingThisStation ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(width: 24, height: 24)

                    if isPlayingThisStation {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    } else {
                        Text(station.badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.primary)
                    }
                }

                Text(station.name)
                    .font(.system(size: 11, weight: isPlayingThisStation ? .semibold : .regular))
                    .foregroundColor(isPlayingThisStation ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isPlayingThisStation ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isPlayingThisStation ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
