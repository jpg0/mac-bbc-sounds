import Cocoa

class MacMarqueeView: NSView {
    var text: String = "" {
        didSet {
            setupMarquee()
        }
    }
    var speed: CGFloat = 40
    
    private var offset: CGFloat = 80
    private var textWidth: CGFloat = 0
    private var timer: Timer?
    
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor.controlTextColor
    ]
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // IMPORTANT: Make this view completely transparent to clicks
    // so the NSStatusItem's NSButton intercepts everything.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
    
    private func setupMarquee() {
        timer?.invalidate()
        
        let size = (text as NSString).size(withAttributes: attributes)
        textWidth = size.width
        offset = bounds.width > 0 ? bounds.width : 80
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.offset -= (self.speed / 60.0)
            if self.offset < -self.textWidth {
                self.offset = self.bounds.width
            }
            self.needsDisplay = true
        }
        
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
            timer.fireDate = Date().addingTimeInterval(0.3)
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let textHeight = (text as NSString).size(withAttributes: attributes).height
        let yPos = (bounds.height - textHeight) / 2.0
        
        let string = text as NSString
        let point = NSPoint(x: offset, y: yPos)
        
        // Draw the text
        string.draw(at: point, withAttributes: attributes)
    }
    
    deinit {
        timer?.invalidate()
    }
}
