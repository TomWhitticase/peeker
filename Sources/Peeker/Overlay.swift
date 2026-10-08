import AppKit

/// Transparent, click-through, above everything, on every Space.
final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class CreepView: NSView {
    let director: Director
    var calibrator: Calibrator?
    var hud: DebugHUD?
    private var lastRects: [CGRect] = []

    init(director: Director) {
        self.director = director
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    /// Only repaint where he is (and was), so a full-screen overlay stays cheap.
    func refresh() {
        var rects = director.paintRects()
        if calibrator != nil { rects.append(bounds) }
        if hud != nil { rects.append(DebugHUD.frame(in: bounds)) }
        for r in rects + lastRects {
            let clipped = r.intersection(bounds)
            if !clipped.isEmpty { setNeedsDisplay(clipped) }
        }
        lastRects = rects
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)
        let now = CACurrentMediaTime()

        for h in director.handprints {
            CreepArt.drawHandprint(h, in: ctx, now: now)
        }
        for c in director.creeps + [director.flash].compactMap({ $0 }) {
            CreepArt.draw(c, in: ctx, size: bounds.size, viewer: director.viewer, depth: director.viewerDepth)
        }
        if let hud {
            hud.draw(in: ctx, bounds: bounds)
        }
        if let calibrator {
            drawCalibration(calibrator, in: ctx, now: now)
        }
    }

    private static let promptFont = NSFont.systemFont(ofSize: 26, weight: .medium)

    private func drawCalibration(_ cal: Calibrator, in ctx: CGContext, now: Double) {
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.55))
        ctx.fill(bounds)

        let dot: CGPoint
        switch cal.target {
        case .center: dot = CGPoint(x: bounds.midX, y: bounds.midY)
        case .left: dot = CGPoint(x: 60, y: bounds.midY)
        case .right: dot = CGPoint(x: bounds.maxX - 60, y: bounds.midY)
        case .top: dot = CGPoint(x: bounds.midX, y: bounds.maxY - 60)
        case .bottom: dot = CGPoint(x: bounds.midX, y: 60)
        }

        let r = 10 + 3 * CGFloat(sin(now * 6))
        ctx.setFillColor(.white)
        ctx.fillEllipse(in: CGRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r))
        ctx.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8))

        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.8))
        ctx.setLineWidth(3)
        ctx.addArc(center: dot, radius: 24, startAngle: .pi / 2, endAngle: .pi / 2 - cal.progress(now: now) * 2 * .pi, clockwise: true)
        ctx.strokePath()

        let text = NSAttributedString(string: cal.prompt, attributes: [
            .font: Self.promptFont,
            .foregroundColor: NSColor.white,
        ])
        let size = text.size()
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - 90))
    }
}

enum CalibrationError: Error {
    case noCamera
    case noFace(frames: Int, faces: Int)
}

/// Three dots: centre, left edge, right edge. Learns what "looking at the screen" means for your face.
final class Calibrator {
    enum Target { case center, left, right, top, bottom }

    private struct Reading {
        var yaw = 0.0, pitch = 0.0, look = 0.0
    }

    private let targets: [Target] = [.center, .left, .right, .top, .bottom]
    private let settle = 1.0
    private let length = 3.2
    private var index = 0
    private var stepStart: Double
    private var current: [Reading] = []
    private var results: [Reading] = []
    private var finished = false
    private let base: Calibration
    /// Result, or why it failed.
    var onFinish: ((Result<Calibration, CalibrationError>) -> Void)?
    private var framesSeen = 0
    private var facesSeen = 0

    init(now: Double, base: Calibration) {
        stepStart = now
        self.base = base
    }

    var target: Target { targets[min(index, targets.count - 1)] }

    var prompt: String {
        switch target {
        case .center: "Look at the dot. Just… look at it."
        case .left: "Now the dot on the left edge"
        case .right: "And the right edge. He's not there. Probably."
        case .top: "Now the top"
        case .bottom: "And the bottom. Don't look behind you."
        }
    }

    func progress(now: Double) -> CGFloat {
        CGFloat(min(1, (now - stepStart) / length))
    }

    func ingest(_ s: GazeSample, now: Double) {
        guard now - stepStart > settle else { return }
        framesSeen += 1
        guard s.facePresent else { return }
        facesSeen += 1
        current.append(Reading(yaw: s.yaw, pitch: s.pitch, look: s.look))
    }

    func tick(now: Double) {
        guard !finished, now - stepStart >= length else { return }
        guard current.count >= 8 else {
            finished = true
            onFinish?(.failure(framesSeen == 0 ? .noCamera : .noFace(frames: framesSeen, faces: facesSeen)))
            return
        }
        framesSeen = 0
        facesSeen = 0
        let n = Double(current.count)
        results.append(Reading(
            yaw: current.map(\.yaw).reduce(0, +) / n,
            pitch: current.map(\.pitch).reduce(0, +) / n,
            look: current.map(\.look).reduce(0, +) / n
        ))
        current = []
        index += 1
        stepStart = now
        if index == targets.count {
            finished = true
            onFinish?(.success(build()))
        }
    }

    private func build() -> Calibration {
        let (c, l, r, t, b) = (results[0], results[1], results[2], results[3], results[4])
        var cal = base
        cal.look0 = c.look
        cal.pitch0 = c.pitch
        cal.yaw0 = c.yaw
        // Looking at the very edge still counts as looking, so leave headroom past it.
        let span = max(abs(l.look - c.look), abs(r.look - c.look))
        cal.lookThreshold = min(0.9, max(0.25, span * 1.35 + 0.08))
        let high = max(t.pitch - c.pitch, b.pitch - c.pitch)
        let low = min(t.pitch - c.pitch, b.pitch - c.pitch)
        cal.pitchHigh = min(0.9, max(0.2, high * 1.35 + 0.08))
        cal.pitchLow = max(-0.9, min(-0.2, low * 1.35 - 0.08))
        cal.isCustom = true
        return cal
    }
}
