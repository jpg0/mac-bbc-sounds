import SwiftUI
import AppKit

class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: NSPanel!
    var marqueeView: MacMarqueeView!
    let viewModel = AppViewModel()
    
    // We must hold onto this so the sink doesn't instantly deallocate
    private var marqueeTextCancellable: Any?
    private var eventMonitor: Any?
    private var localEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Setup Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem.button else { return }
        
        // 2. Setup Panel (replacing NSPopover for right-aligned control)
        let contentView = ContentView()
            .environmentObject(viewModel)
            .frame(width: 420, height: 600)
            
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.masksToBounds = true
        
        // Optional subtle border mirroring macOS native popovers
        effectView.layer?.borderColor = NSColor.separatorColor.cgColor
        effectView.layer?.borderWidth = 1
        
        effectView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])
            
        panel = FocusablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentView = effectView
        panel.level = .popUpMenu
        panel.becomesKeyOnlyIfNeeded = false // Ensure text fields can always gain focus
        
        // 3. Add Custom Marquee Subview to Button
        marqueeView = MacMarqueeView(frame: NSRect(x: 0, y: 0, width: 80, height: 22))
        marqueeView.isHidden = true
        button.addSubview(marqueeView)
        
        // Set action for clicking the standard button
        button.action = #selector(togglePanel(_:))
        button.target = self
        
        // 4. Listen to ViewModel to show/hide the Marquee
        let radioImage = NSImage(systemSymbolName: "radio", accessibilityDescription: "BBC Sounds")
        radioImage?.isTemplate = true
        button.image = radioImage
        
        marqueeTextCancellable = viewModel.$marqueeText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self = self else { return }
                
                if let text = text {
                    self.statusItem.button?.image = nil
                    self.marqueeView.text = text
                    self.marqueeView.isHidden = false
                    self.statusItem.length = 80 // Expand
                    self.marqueeView.frame = NSRect(x: 0, y: 0, width: 80, height: 22)
                } else {
                    self.statusItem.button?.image = radioImage
                    self.marqueeView.isHidden = true
                    self.statusItem.length = NSStatusItem.variableLength // Collapse back to default width
                }
            }
    }

    @objc func togglePanel(_ sender: AnyObject?) {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }
    
    func showPanel() {
        guard let button = statusItem.button, let window = button.window else { return }
        
        let rectInWindow = button.convert(button.bounds, to: nil)
        let buttonRect = window.convertToScreen(rectInWindow)
        var panelFrame = panel.frame
        
        // Align panel's left edge exactly with the button's left edge
        // so the UI extends to the right of the icon
        panelFrame.origin.x = buttonRect.minX
        // Position immediately below the menu bar with 2.5px gap
        panelFrame.origin.y = buttonRect.minY - panelFrame.height - 2.5
        
        panel.setFrame(panelFrame, display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Monitor for clicks outside the panel to dismiss it
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.panel.isVisible else { return }
            
            // Check if the click is outside the panel's frame
            let mouseLocation = NSEvent.mouseLocation
            if !self.panel.frame.contains(mouseLocation) {
                self.hidePanel()
            }
        }
        
        // Also listen for escape key locally when panel is focused
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // escape
                self?.hidePanel()
                return nil
            }
            return event
        }
    }
    
    func hidePanel() {
        panel.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let localMonitor = localEventMonitor {
            NSEvent.removeMonitor(localMonitor)
            localEventMonitor = nil
        }
    }
}
