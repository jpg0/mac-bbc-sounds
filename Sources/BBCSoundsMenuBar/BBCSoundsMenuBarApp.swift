import SwiftUI

@main
struct BBCSoundsMenuBarApp: App {
    @StateObject private var viewModel = AppViewModel()

    init() {
        // Ensure the app behaves as a menubar/accessory app even if launched from CLI
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("BBC Sounds", systemImage: "radio") {
            ContentView()
                .environmentObject(viewModel)
                .frame(width: 420, height: 520)
        }
        .menuBarExtraStyle(.window)
    }

}
