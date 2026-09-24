import AppKit

extension AppDelegate {
    func setupStatusItemInteractions() {
        guard let button = statusItem.button else { return }
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Monitor right clicks when outside key focus
        rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self = self,
                  let button = self.statusItem.button,
                  let window = button.window else { return }
            let mouseLocation = NSEvent.mouseLocation
            let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonRect.contains(mouseLocation) {
                self.showContextMenu(event: event)
            }
        }

        // Global scroll wheel monitor (adjust volume on hover scroll)
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self,
                  let button = self.statusItem.button,
                  let window = button.window else { return }
            let mouseLocation = NSEvent.mouseLocation
            let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonRect.contains(mouseLocation) {
                self.handleScrollWheel(deltaY: event.deltaY)
            }
        }

        // Local scroll wheel monitor (when app panel is key)
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self,
                  let button = self.statusItem.button,
                  let window = button.window else { return event }
            let mouseLocation = NSEvent.mouseLocation
            let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonRect.contains(mouseLocation) {
                self.handleScrollWheel(deltaY: event.deltaY)
                return nil
            }
            return event
        }
    }

    func handleScrollWheel(deltaY: CGFloat) {
        guard deltaY != 0 else { return }
        let step: Float = deltaY > 0 ? 0.04 : -0.04
        let currentVol = viewModel.player.volume
        let newVol = max(0.0, min(1.0, currentVol + step))
        viewModel.player.setVolume(newVol)
    }

    func showContextMenu(event: NSEvent? = nil) {
        if panel.isVisible {
            hidePanel()
        }
        guard let button = statusItem.button else { return }

        let menu = buildContextMenu()
        statusItem.menu = menu
        button.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: "BBC Sounds")

        // 1. Now Playing Summary Header
        if let prog = viewModel.player.currentProgramme {
            let progItem = NSMenuItem(title: prog.name, action: nil, keyEquivalent: "")
            progItem.isEnabled = false
            menu.addItem(progItem)

            if let track = viewModel.player.activeTrack {
                let trackItem = NSMenuItem(title: "♫ \(track.title) — \(track.artist)", action: nil, keyEquivalent: "")
                trackItem.isEnabled = false
                menu.addItem(trackItem)
            }
            menu.addItem(NSMenuItem.separator())
        }

        // 2. Play / Pause
        let playTitle = viewModel.player.isPlaying ? "Pause" : "Play"
        let playItem = NSMenuItem(title: playTitle, action: #selector(togglePlaybackFromMenu), keyEquivalent: "")
        playItem.target = self
        menu.addItem(playItem)

        // 3. Scrub Controls
        let rewindItem = NSMenuItem(title: "Rewind 15 Seconds", action: #selector(rewind15FromMenu), keyEquivalent: "")
        rewindItem.target = self
        rewindItem.image = NSImage(systemSymbolName: "gobackward.15", accessibilityDescription: "Rewind 15s")
        menu.addItem(rewindItem)

        let forwardItem = NSMenuItem(title: "Forward 15 Seconds", action: #selector(forward15FromMenu), keyEquivalent: "")
        forwardItem.target = self
        forwardItem.image = NSImage(systemSymbolName: "goforward.15", accessibilityDescription: "Forward 15s")
        menu.addItem(forwardItem)

        if !viewModel.player.currentTracks.isEmpty {
            let nextTrackItem = NSMenuItem(title: "Next Track", action: #selector(nextTrackFromMenu), keyEquivalent: "")
            nextTrackItem.target = self
            menu.addItem(nextTrackItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 4. Audio Output Submenu
        let outputSubmenu = NSMenu(title: "Audio Output")
        let macItem = NSMenuItem(title: "This Mac", action: #selector(selectOutputThisMac), keyEquivalent: "")
        macItem.target = self
        macItem.state = viewModel.player.outputTarget.isMac ? .on : .off
        outputSubmenu.addItem(macItem)

        let devices = viewModel.player.discoveryService.discoveredDevices
        if !devices.isEmpty {
            outputSubmenu.addItem(NSMenuItem.separator())
            for device in devices {
                let devItem = NSMenuItem(title: device.displayName, action: #selector(selectOutputSonos(_:)), keyEquivalent: "")
                devItem.target = self
                devItem.representedObject = device
                if case .sonos(let active) = viewModel.player.outputTarget, active.id == device.id {
                    devItem.state = .on
                } else {
                    devItem.state = .off
                }
                outputSubmenu.addItem(devItem)
            }
        }
        let outputItem = NSMenuItem(title: "Audio Output", action: nil, keyEquivalent: "")
        outputItem.submenu = outputSubmenu
        menu.addItem(outputItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Open BBC Sounds UI
        let openItem = NSMenuItem(title: "Open BBC Sounds", action: #selector(openPanelFromMenu), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Quit Application
        let quitItem = NSMenuItem(title: "Quit BBC Sounds", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Context Menu Action Handlers

    @objc func togglePlaybackFromMenu() {
        if viewModel.player.isPlaying {
            viewModel.player.pause()
        } else {
            viewModel.player.resume()
        }
    }

    @objc func rewind15FromMenu() {
        viewModel.player.seek(by: -15)
    }

    @objc func forward15FromMenu() {
        viewModel.player.seek(by: 15)
    }

    @objc func nextTrackFromMenu() {
        viewModel.player.skipToNextTrack()
    }

    @objc func selectOutputThisMac() {
        Task {
            try? await viewModel.player.setOutputTarget(.thisMac)
        }
    }

    @objc func selectOutputSonos(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? SonosDevice else { return }
        Task {
            try? await viewModel.player.setOutputTarget(.sonos(device))
        }
    }

    @objc func openPanelFromMenu() {
        if !panel.isVisible {
            showPanel()
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
