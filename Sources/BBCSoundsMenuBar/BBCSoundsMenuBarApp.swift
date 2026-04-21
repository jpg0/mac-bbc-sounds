import SwiftUI

@main
struct BBCSoundsMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        // Ensure the app behaves as a menubar/accessory app even if launched from CLI
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
