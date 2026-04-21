import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var marqueeView: MacMarqueeView!
    let viewModel = AppViewModel()
    
    // We must hold onto this so the sink doesn't instantly deallocate
    private var marqueeTextCancellable: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Setup Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem.button else { return }
        
        // 2. Setup Popover
        let contentView = ContentView()
            .environmentObject(viewModel)
            // Adjust frame here to ensure the popover is properly sized
            .frame(width: 420, height: 520)
            
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // 3. Add Custom Marquee Subview to Button
        marqueeView = MacMarqueeView(frame: NSRect(x: 0, y: 0, width: 80, height: 22))
        marqueeView.isHidden = true
        button.addSubview(marqueeView)
        
        // Set action for clicking the standard button
        button.action = #selector(togglePopover(_:))
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

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
