import AppKit

/// On-screen readout of what the tracker thinks you're doing.
struct DebugHUD {
    var sample = GazeSample()
    var calibration = Calibration()
    var mode = "idle"

    static let size = CGSize(width: 360, height: 320)

    static func frame(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + 20, y: bounds.maxY - 50 - size.height, width: size.width, height: size.height)
    }

    func draw(in ctx: CGContext, bounds: CGRect) {
        let f = Self.frame(in: bounds)
        let s = sample, c = calibration

        ctx.addPath(CGPath(roundedRect: f, cornerWidth: 14, cornerHeight: 14, transform: nil))
        ctx.setFillColor(CGColor(gray: 0.05, alpha: 0.82))
        ctx.fillPath()

        // Headline: the one thing that matters
        let (status, color): (String, NSColor) = {
            if !s.facePresent { return ("NO FACE", .systemGray) }
            if s.eyesClosed { return ("EYES CLOSED", .systemBlue) }
            if s.lookingAway { return ("AWAY  (\(s.awayDirection.rawValue))", .systemRed) }
            return ("LOOKING", .systemGreen)
        }()
        let pill = CGRect(x: f.minX + 14, y: f.maxY - 54, width: f.width - 28, height: 40)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.setFillColor(color.withAlphaComponent(0.85).cgColor)
        ctx.fillPath()
        text(status, at: CGPoint(x: pill.midX, y: pill.midY), size: 22, weight: .bold, centered: true)

        // Each signal against its threshold: the white ticks are the edge of "looking".
        var y = pill.minY - 26
        // head + eyes = look; only look (and pitch) decide anything.
        bar("head", value: s.headTurn, threshold: c.lookThreshold, judged: false, y: y, in: f, ctx: ctx); y -= 24
        bar("eyes", value: s.eyeTurn, threshold: c.lookThreshold, judged: false, y: y, in: f, ctx: ctx); y -= 24
        bar("look", value: s.look - c.look0, threshold: c.lookThreshold, y: y, in: f, ctx: ctx); y -= 24
        bar("pitch", value: s.pitch - c.pitch0, threshold: s.pitch >= c.pitch0 ? c.pitchHigh : -c.pitchLow, y: y, in: f, ctx: ctx); y -= 24
        let openRatio = s.openBaseline > 0 ? s.openness / s.openBaseline : 0
        meter("open", ratio: openRatio, mark: 0.6, y: y, in: f, ctx: ctx); y -= 26

        text("him: \(mode)    calib: \(c.isCustom ? "custom" : "default")",
             at: CGPoint(x: f.minX + 16, y: y), size: 12, weight: .regular)
        y -= 14

        // What Vision thinks your eyes look like (as the camera sees them)
        let box = CGRect(x: f.minX + 14, y: f.minY + 12, width: f.width - 28, height: y - f.minY - 18)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.06))
        ctx.fill(box)
        let halfW = box.width / 2
        for (i, eye) in s.eyeShapes.prefix(2).enumerated() {
            let cell = CGRect(x: box.minX + CGFloat(i) * halfW, y: box.minY, width: halfW, height: box.height).insetBy(dx: 14, dy: 10)
            drawEye(eye, in: cell, ctx: ctx)
        }
        if s.eyeShapes.isEmpty {
            text("no eye landmarks", at: CGPoint(x: box.midX, y: box.midY), size: 12, weight: .regular, centered: true, color: .gray)
        }
    }

    private func bar(_ label: String, value: Double, threshold: Double, judged: Bool = true, y: CGFloat, in f: CGRect, ctx: CGContext) {
        text(label, at: CGPoint(x: f.minX + 16, y: y), size: 12, weight: .medium)
        let track = CGRect(x: f.minX + 70, y: y - 4, width: 200, height: 8)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.15))
        ctx.fill(track)
        // Track spans ±2× threshold
        let scale = track.width / 4
        for t in [-1.0, 1.0] {
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
            ctx.fill(CGRect(x: track.midX + CGFloat(t) * scale - 1, y: track.minY - 4, width: 2, height: track.height + 8))
        }
        let n = value / threshold
        let x = track.midX + CGFloat(max(-2, min(2, n))) * scale
        let over = judged && abs(n) > 1
        ctx.setFillColor((over ? NSColor.systemRed : judged ? NSColor.systemGreen : NSColor.systemGray).cgColor)
        ctx.fillEllipse(in: CGRect(x: x - 6, y: track.midY - 6, width: 12, height: 12))
        text(String(format: "%+.2f", value), at: CGPoint(x: track.maxX + 12, y: y), size: 12, weight: .regular,
             color: over ? .systemRed : .white)
    }

    private func meter(_ label: String, ratio: Double, mark: Double, y: CGFloat, in f: CGRect, ctx: CGContext) {
        text(label, at: CGPoint(x: f.minX + 16, y: y), size: 12, weight: .medium)
        let track = CGRect(x: f.minX + 70, y: y - 4, width: 200, height: 8)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.15))
        ctx.fill(track)
        let closed = ratio < mark
        ctx.setFillColor((closed ? NSColor.systemBlue : NSColor.systemTeal).cgColor)
        ctx.fill(CGRect(x: track.minX, y: track.minY, width: track.width * CGFloat(min(1.3, ratio) / 1.3), height: track.height))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
        ctx.fill(CGRect(x: track.minX + track.width * CGFloat(mark / 1.3) - 1, y: track.minY - 4, width: 2, height: track.height + 8))
        text(String(format: "%.0f%%", ratio * 100), at: CGPoint(x: track.maxX + 12, y: y), size: 12, weight: .regular)
    }

    private func drawEye(_ eye: (contour: [CGPoint], pupil: CGPoint), in cell: CGRect, ctx: CGContext) {
        let xs = eye.contour.map(\.x), ys = eye.contour.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(), maxX > minX else { return }
        // Fit the eye's width to the cell, keep its real proportions, centre vertically.
        let k = cell.width / (maxX - minX)
        let midY = (minY + maxY) / 2
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: cell.minX + (p.x - minX) * k, y: cell.midY + (p.y - midY) * k)
        }
        let path = CGMutablePath()
        path.addLines(between: eye.contour.map(map))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.85))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
        for p in eye.contour.map(map) {
            ctx.fillEllipse(in: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
        }
        let p = map(eye.pupil)
        ctx.setFillColor(NSColor.systemOrange.cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
        // Centre line, so you can see the pupil drift off it
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.25))
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: cell.midX, y: cell.minY))
        ctx.addLine(to: CGPoint(x: cell.midX, y: cell.maxY))
        ctx.strokePath()
    }

    /// Fonts are made once: creating them every frame eventually makes CoreText hand back nil and crash.
    private static var fonts: [String: NSFont] = [:]

    private static func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let key = "\(size)-\(weight.rawValue)"
        if let f = fonts[key] { return f }
        let f = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        fonts[key] = f
        return f
    }

    private func text(_ string: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight, centered: Bool = false, color: NSColor = .white) {
        let s = NSAttributedString(string: string, attributes: [
            .font: Self.font(size, weight),
            .foregroundColor: color,
        ])
        let sz = s.size()
        s.draw(at: CGPoint(x: centered ? p.x - sz.width / 2 : p.x, y: p.y - sz.height / 2))
    }
}
