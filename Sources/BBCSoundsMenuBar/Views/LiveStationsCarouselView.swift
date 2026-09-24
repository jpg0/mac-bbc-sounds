import SwiftUI

struct LiveStation: Identifiable {
    let id: String
    let badge: String
    let name: String
    let badgeColor: Color
}

struct LiveStationsCarouselView: View {
    @EnvironmentObject var viewModel: AppViewModel

    private let stations: [LiveStation] = [
        LiveStation(id: "bbc_radio_one", badge: "1", name: "Radio 1", badgeColor: Color(red: 0.85, green: 0.05, blue: 0.45)),
        LiveStation(id: "bbc_radio_two", badge: "2", name: "Radio 2", badgeColor: Color(red: 0.88, green: 0.48, blue: 0.05)),
        LiveStation(id: "bbc_radio_fourfm", badge: "4", name: "Radio 4", badgeColor: Color(red: 0.12, green: 0.35, blue: 0.85)),
        LiveStation(id: "bbc_6music", badge: "6M", name: "6 Music", badgeColor: Color(red: 0.05, green: 0.58, blue: 0.55)),
        LiveStation(id: "bbc_radio_five_live", badge: "5L", name: "5 Live", badgeColor: Color(red: 0.75, green: 0.12, blue: 0.12)),
        LiveStation(id: "bbc_world_service", badge: "WS", name: "World Service", badgeColor: Color(red: 0.65, green: 0.10, blue: 0.10)),
        LiveStation(id: "bbc_1xtra", badge: "1X", name: "1Xtra", badgeColor: Color(red: 0.92, green: 0.38, blue: 0.05))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row: Live Radio • Quick Tune
            HStack {
                HStack(spacing: 5) {
                    Text("LIVE RADIO")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                }

                Spacer()

                Text("Quick Tune")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 2)

            // Stations Horizontal Carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(stations) { station in
                        stationButton(station)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 2)
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
            HStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(station.badgeColor)
                        .frame(width: 20, height: 20)

                    if isPlayingThisStation {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text(station.badge)
                            .font(.system(size: 9.5, weight: .black))
                            .foregroundColor(.white)
                    }
                }

                Text(station.name)
                    .font(.system(size: 10.5, weight: isPlayingThisStation ? .semibold : .medium))
                    .foregroundColor(isPlayingThisStation ? .primary : .secondary)
            }
            .padding(.leading, 3)
            .padding(.trailing, 7)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isPlayingThisStation ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isPlayingThisStation ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
