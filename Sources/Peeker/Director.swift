import AppKit

/// One creepy guy. All lengths are in units of his head radius.
final class Creep {
    enum Edge: CaseIterable {
        case left, right, bottom, top
    }

    let edge: Edge
    var along: CGFloat
    var scale: CGFloat
    var tilt: CGFloat

    /// How far the top of his head has come past the screen edge.
    var reveal: CGFloat = 0
    var targetReveal: CGFloat = 0
    var fingers: CGFloat = 0
    var targetFingers: CGFloat = 0
    var grin: CGFloat = 0
    var targetGrin: CGFloat = 0
    var speedIn: CGFloat = 1.8
    var speedOut: CGFloat = 14

    var lid: CGFloat = 0
    var neverBlinks = false
    private var blinkStart = -10.0
    private var nextBlink: Double

    let seed: [CGFloat] = (0..<32).map { _ in .random(in: 0...1) }

    init(edge: Edge, along: CGFloat, scale: CGFloat, tilt: CGFloat, now: Double) {
        self.edge = edge
        self.along = along
        self.scale = scale
        self.tilt = tilt
        nextBlink = now + .random(in: 1.5...4)
    }

    var gone: Bool { targetReveal <= 0 && reveal < 0.02 && fingers < 0.02 }

    func geometry(in size: CGSize) -> (anchor: CGPoint, angle: CGFloat, radius: CGFloat) {
        let r = min(size.width, size.height) * 0.075 * scale
        switch edge {
        case .bottom: return (CGPoint(x: along * size.width, y: 0), 0, r)
        case .top: return (CGPoint(x: along * size.width, y: size.height), .pi, r)
        case .left: return (CGPoint(x: 0, y: along * size.height), -.pi / 2, r)
        case .right: return (CGPoint(x: size.width, y: along * size.height), .pi / 2, r)
        }
    }

    /// Creep along the edge towards where you are, trying to get into your line of sight.
    func edgeTowards(_ viewer: CGPoint?, in size: CGSize, dt: Double) {
        guard let viewer, size.width > 0, size.height > 0 else { return }
        let target: CGFloat
        switch edge {
        case .top, .bottom: target = viewer.x / size.width
        case .left, .right: target = viewer.y / size.height
        }
        along += (min(0.85, max(0.15, target)) - along) * (1 - exp(-0.12 * CGFloat(dt)))
    }

    func step(dt: Double, now: Double) {
        func approach(_ value: inout CGFloat, _ target: CGFloat, _ rateIn: CGFloat, _ rateOut: CGFloat) {
            let rate = target > value ? rateIn : rateOut
            value += (target - value) * (1 - exp(-rate * CGFloat(dt)))
        }
        approach(&reveal, targetReveal, speedIn, speedOut)
        approach(&fingers, targetFingers, 2.5, speedOut * 1.2)
        approach(&grin, targetGrin, 1.0, speedOut * 0.7)

        if neverBlinks {
            lid = 0
            return
        }
        if now >= nextBlink {
            blinkStart = now
            nextBlink = now + .random(in: 2.5...6)
        }
        let t = now - blinkStart
        lid = t < 0.18 ? CGFloat(sin(t / 0.18 * .pi)) : 0
    }
}

struct Handprint {
    let point: CGPoint
    let angle: CGFloat
    let size: CGFloat
    let born: Double
}

/// Decides when he peeks, how bold he gets, and which rare stunt he pulls.
final class Director {
    enum Mode {
        case idle
        case waiting(until: Double)
        case peeking(since: Double)
        case retreating
    }

    private(set) var creeps: [Creep] = []
    private(set) var handprints: [Handprint] = []
    private(set) var flash: Creep?
    private(set) var mode: Mode = .idle
    var canvas: CGSize = .zero
    /// Your head, projected onto the screen. He looks here, and edges towards it.
    private(set) var viewer: CGPoint?
    var viewerDepth: CGFloat { canvas.width * 0.45 }
    var suspended = false
    var onStatsChanged: (() -> Void)?

    private let settings = Settings.shared
    private var lookingAway = false
    private var eyesClosed = false
    private var awayDirection: AwayDirection = .unknown
    private var testUntil: Double?
    private var lastFlash = -100.0

    private var boldness: Boldness { settings.boldness }

    var modeName: String {
        switch mode {
        case .idle: "idle"
        case .waiting: "waiting"
        case .peeking: testUntil == nil ? "peeking" : "peeking (test)"
        case .retreating: "retreating"
        }
    }

    func ingest(_ s: GazeSample, now: Double) {
        if let f = s.faceCenter, canvas.width > 0 {
            // The camera sits top-centre and doesn't mirror, so you moving right shows up as image-left.
            let target = CGPoint(x: canvas.width * (0.5 + (0.5 - f.x) * 1.2),
                                 y: canvas.height * (0.65 + (f.y - 0.5) * 0.8))
            viewer = viewer.map { CGPoint(x: $0.x + (target.x - $0.x) * 0.3, y: $0.y + (target.y - $0.y) * 0.3) } ?? target
        }
        guard !suspended else { return }
        if s.lookingAway { awayDirection = s.awayDirection }
        if s.lookingAway != lookingAway {
            lookingAway = s.lookingAway
            lookingAway ? lookedAway(now) : lookedBack(now)
        }
        if s.eyesClosed != eyesClosed {
            eyesClosed = s.eyesClosed
            eyesClosed ? blinkStarted(now) : (flash = nil)
        }
    }

    func reset() {
        creeps.removeAll()
        handprints.removeAll()
        flash = nil
        mode = .idle
        lookingAway = false
        eyesClosed = false
        testUntil = nil
    }

    func summon(now: Double) {
        guard case .idle = mode else { return }
        startPeek(now: now, counts: false)
        // Start him part-way so the test doesn't take ages to get good.
        mode = .peeking(since: now - boldness.growthTime * 0.45)
        testUntil = now + 7
    }

    // MARK: - Events

    private func lookedAway(_ now: Double) {
        flash = nil
        switch mode {
        case .idle:
            mode = .waiting(until: now + .random(in: boldness.peekDelay))
        default:
            break
        }
    }

    private func lookedBack(_ now: Double) {
        switch mode {
        case .waiting:
            mode = .idle
        case .peeking(let since):
            let counts = testUntil == nil
            testUntil = nil
            let visible = creeps.contains { $0.reveal > 1.0 }
            if visible && counts {
                settings.caught += 1
                onStatsChanged?()
            }
            // The moment you look, he's gone.
            if visible, now - since > 5, Double.random(in: 0..<1) < 0.3 * boldness.rareMultiplier, let c = creeps.first {
                leaveHandprint(from: c, now: now)
            }
            retreat(speed: 22)
        default:
            break
        }
    }

    private func blinkStarted(_ now: Double) {
        guard !lookingAway else { return }
        switch mode {
        case .idle:
            let chance = 0.2 * boldness.rareMultiplier
            guard settings.blinkFlashes, now - lastFlash > 20, Double.random(in: 0..<1) < chance else { return }
            let c = Creep(edge: .bottom, along: .random(in: 0.3...0.7), scale: 2.3, tilt: .random(in: -0.1...0.1), now: now)
            c.reveal = 2.7
            c.targetReveal = 2.7
            c.fingers = 1
            c.targetFingers = 1
            c.grin = 1
            c.targetGrin = 1
            c.neverBlinks = true
            flash = c
            lastFlash = now
        default:
            break
        }
    }

    // MARK: - Frame

    func tick(now: Double, dt: Double) {
        if let t = testUntil, now >= t {
            lookedBack(now)
        }

        switch mode {
        case .waiting(let until) where now >= until && !suspended:
            startPeek(now: now, counts: true)
            mode = .peeking(since: now)
        case .peeking(let since):
            let b = min(1, (now - since) / boldness.growthTime)
            let eased = CGFloat(b * b * (3 - 2 * b))
            for c in creeps {
                c.edgeTowards(viewer, in: canvas, dt: dt)
                // 1.45 is just the eyes over the edge; 2.8 is the whole face and a bit of neck.
                c.targetReveal = 1.45 + eased * 1.35
                c.targetFingers = b > 0.18 ? 1 : 0
                c.targetGrin = max(0, CGFloat(b - 0.55) / 0.45)
            }
        case .retreating where creeps.allSatisfy(\.gone):
            creeps.removeAll()
            mode = lookingAway ? .waiting(until: now + .random(in: boldness.peekDelay)) : .idle
        default:
            break
        }

        for c in creeps { c.step(dt: dt, now: now) }
        handprints.removeAll { now - $0.born > 6 }
    }

    /// Screen regions that need repainting this frame.
    func paintRects() -> [CGRect] {
        var rects: [CGRect] = []
        for c in creeps + [flash].compactMap({ $0 }) where c.reveal > 0.002 || c.fingers > 0.002 {
            let g = c.geometry(in: canvas)
            let r = g.radius * 4.2
            rects.append(CGRect(x: g.anchor.x - r, y: g.anchor.y - r, width: 2 * r, height: 2 * r))
        }
        for h in handprints {
            let r = h.size * 2.6
            rects.append(CGRect(x: h.point.x - r, y: h.point.y - r, width: 2 * r, height: 2 * r))
        }
        return rects
    }

    // MARK: - Helpers

    private func startPeek(now: Double, counts: Bool) {
        let edge = pickEdge()
        creeps = [makeCreep(edge: edge, now: now)]
        if counts {
            settings.peeks += 1
            onStatsChanged?()
        }
    }

    private func makeCreep(edge: Creep.Edge, now: Double) -> Creep {
        let tilt: CGFloat
        switch edge {
        case .left, .right: tilt = (Bool.random() ? 1 : -1) * .random(in: 0.25...0.55)
        case .top, .bottom: tilt = .random(in: -0.15...0.15)
        }
        return Creep(edge: edge, along: .random(in: 0.18...0.82), scale: .random(in: 0.85...1.2), tilt: tilt, now: now)
    }

    /// He comes from wherever you're not looking.
    private func pickEdge() -> Creep.Edge {
        let r = Double.random(in: 0..<1)
        switch awayDirection {
        case .left where r < 0.7: return .right
        case .right where r < 0.7: return .left
        case .down where r < 0.6: return .top
        default:
            let w = Double.random(in: 0..<1)
            return w < 0.3 ? .left : w < 0.6 ? .right : w < 0.85 ? .bottom : .top
        }
    }

    private func retreat(speed: CGFloat) {
        for c in creeps {
            c.targetReveal = 0
            c.targetFingers = 0
            c.targetGrin = 0
            c.speedOut = speed
        }
        mode = .retreating
    }

    private func leaveHandprint(from c: Creep, now: Double) {
        let g = c.geometry(in: canvas)
        let side: CGFloat = Bool.random() ? 1 : -1
        let local = CGPoint(x: side * 1.5, y: 1.3 + .random(in: 0...0.6))
        let a = g.angle
        let p = CGPoint(
            x: g.anchor.x + (local.x * cos(a) - local.y * sin(a)) * g.radius,
            y: g.anchor.y + (local.x * sin(a) + local.y * cos(a)) * g.radius
        )
        handprints.append(Handprint(point: p, angle: a + .random(in: -0.4...0.4), size: g.radius * 1.1, born: now))
    }
}
