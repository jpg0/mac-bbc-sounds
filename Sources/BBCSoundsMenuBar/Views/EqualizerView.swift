import AppKit

@MainActor
class EqualizerAnimator {
    private(set) var isPlaying: Bool = false
    private var timer: Timer?
    private var currentFrameIndex: Int = 0
    private weak var button: NSStatusBarButton?
    
    let defaultImage: NSImage
    private(set) var frames: [NSImage] = []
    
    init() {
        let base = NSImage(systemSymbolName: "radio", accessibilityDescription: "BBC Sounds") ?? NSImage()
        let defaultImg = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            return true
        }
        defaultImg.isTemplate = true
        self.defaultImage = defaultImg
        self.frames = EqualizerAnimator.generateFrames(baseImage: base)
    }
    
    static func generateFrames(baseImage: NSImage, frameCount: Int = 16) -> [NSImage] {
        guard baseImage.size.width > 0 && baseImage.size.height > 0 else { return [] }
        
        let size = baseImage.size
        let minH: CGFloat = 2.0
        let maxH: CGFloat = 8.0
        var result: [NSImage] = []
        
        for i in 0..<frameCount {
            let t = Double(i) / Double(frameCount) * 2.0 * .pi
            let v0 = 0.5 + 0.35 * sin(t * 2.0) + 0.15 * sin(t * 4.0)
            let v1 = 0.5 + 0.40 * sin(t * 3.0 + 1.2) + 0.10 * sin(t * 5.0)
            let v2 = 0.5 + 0.35 * sin(t * 2.0 + 2.4) + 0.15 * sin(t * 3.0 + 1.0)
            
            let h0 = minH + (maxH - minH) * CGFloat(max(0.0, min(1.0, v0)))
            let h1 = minH + (maxH - minH) * CGFloat(max(0.0, min(1.0, v1)))
            let h2 = minH + (maxH - minH) * CGFloat(max(0.0, min(1.0, v2)))
            
            let img = NSImage(size: size, flipped: false) { rect in
                baseImage.draw(in: rect)
                
                // Cut out the circular speaker grille area to keep background transparent
                let speakerCutout = NSRect(x: 4.0, y: 2.0, width: 7.0, height: 9.0)
                speakerCutout.fill(using: .destinationOut)
                
                // Draw 3 equalizer bars inside the speaker area
                let barW: CGFloat = 1.5
                let gap: CGFloat = 1.0
                let startX: CGFloat = 4.5
                let heights = [h0, h1, h2]
                for (idx, h) in heights.enumerated() {
                    let x = startX + CGFloat(idx) * (barW + gap)
                    let r = NSRect(x: x, y: 2.5, width: barW, height: h)
                    let path = NSBezierPath(roundedRect: r, xRadius: 0.5, yRadius: 0.5)
                    path.fill()
                }
                return true
            }
            img.isTemplate = true
            result.append(img)
        }
        
        return result
    }
    
    func start(button: NSStatusBarButton) {
        self.button = button
        self.isPlaying = true
        
        if timer == nil && !frames.isEmpty {
            button.image = frames[currentFrameIndex]
            
            let t = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.isPlaying, let button = self.button else { return }
                    self.currentFrameIndex = (self.currentFrameIndex + 1) % self.frames.count
                    button.image = self.frames[self.currentFrameIndex]
                }
            }
            RunLoop.main.add(t, forMode: .common)
            self.timer = t
        }
    }
    
    func stop(button: NSStatusBarButton? = nil) {
        self.isPlaying = false
        timer?.invalidate()
        timer = nil
        currentFrameIndex = 0
        
        let targetButton = button ?? self.button
        targetButton?.image = defaultImage
    }
    
    deinit {
        timer?.invalidate()
    }
}
