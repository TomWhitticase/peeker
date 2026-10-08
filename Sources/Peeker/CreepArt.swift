import AppKit

/// Draws him procedurally in a soft, painted style: no outlines, everything is
/// shading. All lengths are in head-radius units, with the screen edge along
/// y = 0 and "into the screen" pointing up.
enum CreepArt {
    private static let space = CGColorSpaceCreateDeviceRGB()

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }

    private static func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
        let locs = locations ?? colors.indices.map { CGFloat($0) / CGFloat(colors.count - 1) }
        return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs)!
    }

    // Ashen, slightly yellow-grey, never sees the sun
    private static let skinLight = rgb(0.84, 0.82, 0.76)
    private static let skinBase = rgb(0.66, 0.64, 0.59)
    private static let skinShadow = rgb(0.27, 0.26, 0.26)
    private static let skull = gradient([skinLight, skinBase, skinShadow], [0, 0.45, 1])
    private static let cylinder = gradient([skinShadow, skinBase, skinLight, skinBase, skinShadow], [0, 0.25, 0.45, 0.7, 1])
    private static let edgeOcclusion = gradient([rgb(0.1, 0.08, 0.09, 0), rgb(0.1, 0.08, 0.09, 0.6)])
    private static let darkSoft = gradient([rgb(0.08, 0.05, 0.07, 0.55), rgb(0.08, 0.05, 0.07, 0)])
    private static let deepSocket = gradient([rgb(0.03, 0.02, 0.03, 0.97), rgb(0.06, 0.04, 0.05, 0.7), rgb(0.1, 0.06, 0.08, 0)], [0, 0.45, 1])
    private static let lightSoft = gradient([rgb(1, 0.98, 0.92, 0.3), rgb(1, 0.98, 0.92, 0)])
    private static let bruise = gradient([rgb(0.35, 0.22, 0.32, 0.4), rgb(0.35, 0.22, 0.32, 0)])
    private static let blotch = gradient([rgb(0.42, 0.33, 0.30, 0.22), rgb(0.42, 0.33, 0.30, 0)])
    private static let crownDark = gradient([rgb(0, 0, 0, 0), rgb(0.02, 0.02, 0.02, 0.6)])
    private static let sclera = gradient([rgb(0.88, 0.85, 0.76), rgb(0.74, 0.68, 0.6), rgb(0.42, 0.34, 0.32)], [0, 0.6, 1])
    private static let iris = gradient([rgb(0, 0, 0), rgb(0, 0, 0), rgb(0.5, 0.52, 0.47), rgb(0.33, 0.36, 0.33), rgb(0.08, 0.08, 0.08)],
                                       [0, 0.3, 0.36, 0.82, 1])
    private static let lidShadow = gradient([rgb(0.05, 0.03, 0.03, 0.75), rgb(0.05, 0.03, 0.03, 0)])
    private static let mouthInside = gradient([rgb(0.02, 0, 0), rgb(0.22, 0.04, 0.05)])
    private static let toothShade = gradient([rgb(0.42, 0.33, 0.2), rgb(0.74, 0.68, 0.5), rgb(0.82, 0.78, 0.64)], [0, 0.55, 1])
    private static let nailShade = gradient([rgb(0.48, 0.42, 0.32), rgb(0.70, 0.64, 0.50), rgb(0.40, 0.33, 0.22)], [0, 0.5, 1])
    /// He's coming up out of the dark behind the screen edge.
    private static let edgeDark = gradient([rgb(0, 0, 0, 0.8), rgb(0, 0, 0, 0)])

    /// Film grain, tiled over him so he reads as a photo rather than a drawing.
    private static let grain: CGImage = {
        let n = 256
        var bytes = [UInt8](repeating: 0, count: n * n)
        for i in bytes.indices { bytes[i] = .random(in: 0...255) }
        let ctx = CGContext(data: &bytes, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        return ctx.makeImage()!
    }()

    private static let headRY: CGFloat = 1.3
    private static let eyeLift: CGFloat = 0.12
    private static let eyeSpread: CGFloat = 0.36

    /// `viewer` is where your head is, projected onto the screen; `depth` is how far in front of it you sit.
    static func draw(_ c: Creep, in ctx: CGContext, size: CGSize, viewer: CGPoint?, depth: CGFloat) {
        guard c.reveal > 0.002 || c.fingers > 0.002 else { return }
        let g = c.geometry(in: size)
        let cy = c.reveal - headRY

        ctx.saveGState()
        ctx.translateBy(x: g.anchor.x, y: g.anchor.y)
        ctx.rotate(by: g.angle)
        ctx.scaleBy(x: g.radius, y: g.radius)
        ctx.setLineCap(.round)
        // Everything below composites as one group, so the grain and the edge
        // darkness only land on him, and he casts one soft shadow.
        ctx.setShadow(offset: .zero, blur: g.radius * 0.5, color: rgb(0, 0, 0, 0.75))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        ctx.saveGState()
        ctx.rotate(by: c.tilt)
        let pupils = [CGFloat(-1), 1].map { side in
            towardViewer(from: CGPoint(x: side * eyeSpread, y: cy + eyeLift), creep: c, geometry: g, viewer: viewer, depth: depth)
        }
        let facing = towardViewer(from: CGPoint(x: 0, y: cy), creep: c, geometry: g, viewer: viewer, depth: depth)
        drawHead(c, ctx, cy: cy, pupils: pupils.map { CGPoint(x: $0.x * 0.13, y: $0.y * 0.08) },
                 turn: CGPoint(x: facing.x * 0.16, y: facing.y * 0.08))
        ctx.restoreGState()

        drawHands(c, ctx)

        let bounds = CGRect(x: -3.2, y: -0.6, width: 6.4, height: 4.4)
        ctx.clip(to: bounds)
        ctx.setBlendMode(.sourceAtop)
        ctx.drawLinearGradient(edgeDark, start: .zero, end: CGPoint(x: 0, y: 0.75), options: [.drawsBeforeStartLocation])
        ctx.setAlpha(0.13)
        let tile = 200 / g.radius
        ctx.draw(grain, in: CGRect(x: 0, y: 0, width: tile, height: tile), byTiling: true)

        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Direction from a point on his face out to your head, in his own (tilted) frame.
    /// Only the on-screen part is returned: (0, 0) means you're dead ahead, and it
    /// grows towards 1 the further off to the side you are. That's what makes it eye contact
    /// rather than "looking at something on the screen".
    private static func towardViewer(from point: CGPoint, creep c: Creep, geometry g: (anchor: CGPoint, angle: CGFloat, radius: CGFloat),
                                     viewer: CGPoint?, depth: CGFloat) -> CGPoint {
        guard let viewer else { return .zero }
        let eye = point
        let a = g.angle + c.tilt
        let world = CGPoint(
            x: g.anchor.x + (eye.x * cos(a) - eye.y * sin(a)) * g.radius,
            y: g.anchor.y + (eye.x * sin(a) + eye.y * cos(a)) * g.radius
        )
        let dx = viewer.x - world.x, dy = viewer.y - world.y
        let len = max(1, sqrt(dx * dx + dy * dy + depth * depth))
        return CGPoint(x: (dx * cos(-a) - dy * sin(-a)) / len, y: (dx * sin(-a) + dy * cos(-a)) / len)
    }

    /// A soft round blob of `g`, stretched to (sx, sy).
    private static func blob(_ ctx: CGContext, _ g: CGGradient, at p: CGPoint, radius r: CGFloat, sx: CGFloat = 1, sy: CGFloat = 1) {
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.scaleBy(x: sx, y: sy)
        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: [])
        ctx.restoreGState()
    }

    // MARK: - Head

    /// Tall cranium, hollow cheeks, narrow chin.
    private static func skullPath(cy: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: cy + 1.3))
        p.addCurve(to: CGPoint(x: 0.93, y: cy + 0.35), control1: CGPoint(x: 0.6, y: cy + 1.3), control2: CGPoint(x: 0.95, y: cy + 0.9))
        p.addCurve(to: CGPoint(x: 0.64, y: cy - 0.72), control1: CGPoint(x: 0.92, y: cy - 0.05), control2: CGPoint(x: 0.7, y: cy - 0.3))
        p.addCurve(to: CGPoint(x: 0, y: cy - 1.28), control1: CGPoint(x: 0.56, y: cy - 1.08), control2: CGPoint(x: 0.28, y: cy - 1.28))
        p.addCurve(to: CGPoint(x: -0.64, y: cy - 0.72), control1: CGPoint(x: -0.28, y: cy - 1.28), control2: CGPoint(x: -0.56, y: cy - 1.08))
        p.addCurve(to: CGPoint(x: -0.93, y: cy + 0.35), control1: CGPoint(x: -0.7, y: cy - 0.3), control2: CGPoint(x: -0.92, y: cy - 0.05))
        p.addCurve(to: CGPoint(x: 0, y: cy + 1.3), control1: CGPoint(x: -0.95, y: cy + 0.9), control2: CGPoint(x: -0.6, y: cy + 1.3))
        p.closeSubpath()
        return p
    }

    /// `turn` slides the features across the skull, so his face reads as turned towards you.
    private static func drawHead(_ c: Creep, _ ctx: CGContext, cy: CGFloat, pupils: [CGPoint], turn: CGPoint) {
        // Neck, shaded like a cylinder, in the shadow of the jaw
        ctx.saveGState()
        ctx.clip(to: CGRect(x: -0.34, y: cy - 3.4, width: 0.68, height: 2.4))
        ctx.drawLinearGradient(cylinder, start: CGPoint(x: -0.34, y: 0), end: CGPoint(x: 0.34, y: 0), options: [])
        blob(ctx, darkSoft, at: CGPoint(x: 0, y: cy - 1.15), radius: 0.5, sx: 1.2, sy: 0.9)
        ctx.setStrokeColor(rgb(0.15, 0.13, 0.13, 0.25))
        ctx.setLineWidth(0.035)
        for s: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: s * 0.22, y: cy - 3.4))
            ctx.addQuadCurve(to: CGPoint(x: s * 0.06, y: cy - 1.1), control: CGPoint(x: s * 0.22, y: cy - 1.7))
            ctx.strokePath()
        }
        ctx.restoreGState()

        let head = skullPath(cy: cy)
        ctx.saveGState()
        ctx.addPath(head)
        ctx.clip()

        // Lit from low and slightly to one side, like a phone torch from below.
        ctx.drawRadialGradient(skull, startCenter: CGPoint(x: 0.12, y: cy - 0.35), startRadius: 0,
                               endCenter: CGPoint(x: 0.05, y: cy - 0.1), endRadius: 1.75, options: [.drawsAfterEndLocation])
        // Roundness: darken towards the silhouette
        ctx.saveGState()
        ctx.translateBy(x: 0, y: cy)
        ctx.scaleBy(x: 1, y: 1.38)
        ctx.drawRadialGradient(edgeOcclusion, startCenter: .zero, startRadius: 0.62, endCenter: .zero, endRadius: 1.0,
                               options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        ctx.drawLinearGradient(crownDark, start: CGPoint(x: 0, y: cy + 0.35), end: CGPoint(x: 0, y: cy + 1.3),
                               options: [.drawsAfterEndLocation])

        // Blotchy, unwell skin
        for i in 0..<10 {
            let p = CGPoint(x: (c.seed[i] - 0.5) * 1.5, y: cy + (c.seed[i + 10] - 0.5) * 2.0)
            blob(ctx, blotch, at: p, radius: 0.1 + c.seed[i + 20] * 0.18, sx: 1.2, sy: 0.9)
        }
        ctx.setStrokeColor(rgb(0.3, 0.36, 0.5, 0.16))
        ctx.setLineWidth(0.016)
        for s: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: s * 0.84, y: cy + 0.85))
            ctx.addCurve(to: CGPoint(x: s * 0.62, y: cy + 0.3), control1: CGPoint(x: s * 0.68, y: cy + 0.7), control2: CGPoint(x: s * 0.78, y: cy + 0.45))
            ctx.move(to: CGPoint(x: s * 0.72, y: cy + 0.62))
            ctx.addQuadCurve(to: CGPoint(x: s * 0.52, y: cy + 0.75), control: CGPoint(x: s * 0.58, y: cy + 0.6))
            ctx.strokePath()
        }

        ctx.translateBy(x: turn.x, y: turn.y)
        // Bone structure: brow ridge and cheekbones catch light, everything under them falls away.
        blob(ctx, lightSoft, at: CGPoint(x: 0, y: cy + 0.44), radius: 0.4, sx: 1.9, sy: 0.35)
        for s: CGFloat in [-1, 1] {
            blob(ctx, lightSoft, at: CGPoint(x: s * 0.52, y: cy - 0.12), radius: 0.24, sx: 1.4, sy: 0.7)
            blob(ctx, darkSoft, at: CGPoint(x: s * 0.52, y: cy - 0.5), radius: 0.3, sx: 0.9, sy: 1.4)
            blob(ctx, darkSoft, at: CGPoint(x: s * 0.82, y: cy + 0.45), radius: 0.25, sx: 0.7, sy: 1.3)
            blob(ctx, deepSocket, at: CGPoint(x: s * eyeSpread, y: cy + eyeLift + 0.02), radius: 0.4, sx: 1.1, sy: 0.8)
            blob(ctx, bruise, at: CGPoint(x: s * eyeSpread, y: cy + eyeLift - 0.2), radius: 0.22, sx: 1.2, sy: 0.6)
        }

        // Nose: just light on the bridge and shadow under the tip
        blob(ctx, lightSoft, at: CGPoint(x: 0.03, y: cy - 0.05), radius: 0.3, sx: 0.22, sy: 1)
        blob(ctx, darkSoft, at: CGPoint(x: -0.1, y: cy - 0.08), radius: 0.24, sx: 0.3, sy: 1)
        blob(ctx, lightSoft, at: CGPoint(x: 0.02, y: cy - 0.26), radius: 0.11, sx: 1.2, sy: 0.9)
        blob(ctx, darkSoft, at: CGPoint(x: 0, y: cy - 0.37), radius: 0.22, sx: 1.4, sy: 0.4)
        for s: CGFloat in [-1, 1] {
            blob(ctx, darkSoft, at: CGPoint(x: s * 0.13, y: cy - 0.29), radius: 0.08, sx: 0.8, sy: 1.2)
        }
        for s: CGFloat in [-1, 1] {
            blob(ctx, deepSocket, at: CGPoint(x: s * 0.075, y: cy - 0.33), radius: 0.05, sx: 1.4, sy: 0.7)
        }
        // Philtrum and chin
        blob(ctx, darkSoft, at: CGPoint(x: 0, y: cy - 0.5), radius: 0.1, sx: 0.5, sy: 1)
        blob(ctx, lightSoft, at: CGPoint(x: 0, y: cy - 1.05), radius: 0.22, sx: 1.3, sy: 0.7)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: turn.x, y: turn.y)
        // Slightly mismatched eyes: the right one is bigger and sits lower.
        for (i, s) in [CGFloat(-1), 1].enumerated() {
            let e = CGPoint(x: s * eyeSpread, y: cy + eyeLift - (s > 0 ? 0.025 : 0))
            drawEye(ctx, at: e, size: s > 0 ? 1.1 : 1, pupil: pupils[i], lid: c.lid, seed: c.seed, side: s)
        }
        drawMouth(c, ctx, cy: cy)
        ctx.restoreGState()
        drawHair(c, ctx, cy: cy)
    }

    /// Thin greasy strands off the crown: short over the forehead, long down the sides.
    private static func drawHair(_ c: Creep, _ ctx: CGContext, cy: CGFloat) {
        for i in 0..<44 {
            let r = c.seed[i % 32], r2 = c.seed[(i * 7 + 3) % 32]
            let sx = (CGFloat(i) / 43 - 0.5) * 1.35 + (r2 - 0.5) * 0.04
            let side: CGFloat = sx < 0 ? -1 : 1
            let startY = cy + 1.27 - sx * sx * 0.55
            let fall = abs(sx) < 0.28 ? 0.25 + r * 0.4 : 0.9 + r * 1.0
            let endX = sx * 1.08 + side * 0.1 + (r2 - 0.5) * 0.2
            let endY = startY - fall - abs(sx) * 0.3
            let shine = i % 6 == 0
            ctx.setStrokeColor(shine ? rgb(0.45, 0.43, 0.4, 0.3) : rgb(0.06, 0.05, 0.05, 0.35 + r2 * 0.45))
            ctx.setLineWidth(0.006 + r * 0.01)
            ctx.move(to: CGPoint(x: sx, y: startY))
            ctx.addCurve(to: CGPoint(x: endX, y: endY),
                         control1: CGPoint(x: sx * 1.25 + side * 0.08, y: startY + 0.05),
                         control2: CGPoint(x: endX + side * 0.04, y: endY + fall * 0.5))
            ctx.strokePath()
        }
    }

    private static func drawEye(_ ctx: CGContext, at e: CGPoint, size k: CGFloat, pupil: CGPoint, lid: CGFloat, seed: [CGFloat], side: CGFloat) {
        let rx = 0.19 * k, ry = 0.12 * k
        // Almond: a tall upper arc and a flatter lower one, inner corner a touch lower.
        let inner = CGPoint(x: e.x - side * rx, y: e.y - ry * 0.12)
        let outer = CGPoint(x: e.x + side * rx, y: e.y + ry * 0.05)
        let upperCtrl = CGPoint(x: e.x - side * rx * 0.1, y: e.y + ry * 2.0)
        let lowerCtrl = CGPoint(x: e.x + side * rx * 0.05, y: e.y - ry * 1.6)
        let shape = CGMutablePath()
        shape.move(to: inner)
        shape.addQuadCurve(to: outer, control: upperCtrl)
        shape.addQuadCurve(to: inner, control: lowerCtrl)
        func upper(_ t: CGFloat) -> CGPoint {
            CGPoint(x: (1 - t) * (1 - t) * inner.x + 2 * t * (1 - t) * upperCtrl.x + t * t * outer.x,
                    y: (1 - t) * (1 - t) * inner.y + 2 * t * (1 - t) * upperCtrl.y + t * t * outer.y)
        }

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.drawRadialGradient(sclera, startCenter: CGPoint(x: e.x, y: e.y + 0.01), startRadius: 0,
                               endCenter: e, endRadius: rx * 1.05, options: [.drawsAfterEndLocation])

        // Fine red vessels creeping in from the corners
        ctx.setStrokeColor(rgb(0.62, 0.12, 0.12, 0.45))
        ctx.setLineWidth(0.006)
        for i in 0..<7 {
            let corner: CGFloat = i % 2 == 0 ? 1 : -1
            let d = (seed[i + 3] - 0.5) * 0.16
            ctx.move(to: CGPoint(x: e.x + corner * rx, y: e.y + d * 0.4))
            ctx.addQuadCurve(to: CGPoint(x: e.x + corner * rx * (0.3 + seed[i + 11] * 0.2), y: e.y + d),
                             control: CGPoint(x: e.x + corner * rx * 0.7, y: e.y - d * 0.5))
            ctx.strokePath()
        }

        // Iris: pale and clouded, dark limbal ring, pinprick pupil
        let ic = CGPoint(x: e.x + pupil.x, y: e.y + pupil.y)
        let ir = 0.068 * k
        ctx.drawRadialGradient(iris, startCenter: ic, startRadius: 0, endCenter: ic, endRadius: ir, options: [])
        ctx.setStrokeColor(rgb(0.15, 0.15, 0.13, 0.25))
        ctx.setLineWidth(0.004)
        for i in 0..<18 {
            let a = CGFloat(i) / 18 * 2 * .pi
            ctx.move(to: CGPoint(x: ic.x + cos(a) * ir * 0.38, y: ic.y + sin(a) * ir * 0.38))
            ctx.addLine(to: CGPoint(x: ic.x + cos(a) * ir * 0.85, y: ic.y + sin(a) * ir * 0.85))
        }
        ctx.strokePath()

        // The upper lid shades the top of the eyeball
        ctx.drawLinearGradient(lidShadow, start: CGPoint(x: e.x, y: e.y + ry), end: CGPoint(x: e.x, y: e.y + ry * 0.1), options: [])

        // Wet highlight, so it's alive
        ctx.setFillColor(rgb(1, 1, 1, 0.75))
        ctx.fillEllipse(in: CGRect(x: ic.x - ir * 0.55, y: ic.y + ir * 0.2, width: ir * 0.32, height: ir * 0.26))
        ctx.setFillColor(rgb(1, 1, 1, 0.3))
        ctx.fillEllipse(in: CGRect(x: ic.x + ir * 0.35, y: ic.y - ir * 0.5, width: ir * 0.14, height: ir * 0.12))

        // Wide open. The lid only comes down when he blinks.
        if lid > 0.01 {
            let lidY = e.y + ry * 1.1 - min(1.15, lid * 1.15) * 2.2 * ry
            ctx.clip(to: CGRect(x: e.x - rx, y: lidY, width: 2 * rx, height: e.y + ry * 1.1 - lidY + 0.02))
            ctx.drawLinearGradient(gradient([skinBase, skinShadow]), start: CGPoint(x: e.x, y: e.y + ry),
                                   end: CGPoint(x: e.x, y: lidY), options: [.drawsAfterEndLocation])
        }
        ctx.restoreGState()

        // Raw pink waterline along the bottom, a dark crease above
        ctx.setStrokeColor(rgb(0.62, 0.3, 0.3, 0.45))
        ctx.setLineWidth(0.02)
        ctx.move(to: inner)
        ctx.addQuadCurve(to: outer, control: lowerCtrl)
        ctx.strokePath()
        ctx.setStrokeColor(rgb(0.05, 0.03, 0.03, 0.55))
        ctx.setLineWidth(0.022)
        ctx.move(to: inner)
        ctx.addQuadCurve(to: outer, control: upperCtrl)
        ctx.strokePath()
        ctx.setStrokeColor(rgb(0.05, 0.03, 0.03, 0.3))
        ctx.setLineWidth(0.025)
        ctx.move(to: CGPoint(x: inner.x - side * 0.02, y: inner.y + ry * 0.6))
        ctx.addQuadCurve(to: CGPoint(x: outer.x + side * 0.03, y: outer.y + ry * 0.5),
                         control: CGPoint(x: upperCtrl.x, y: upperCtrl.y + ry * 0.6))
        ctx.strokePath()
        // A few sparse lashes
        ctx.setStrokeColor(rgb(0.05, 0.04, 0.04, 0.55))
        ctx.setLineWidth(0.006)
        for i in 1..<8 {
            let p = upper(CGFloat(i) / 8)
            ctx.move(to: p)
            ctx.addLine(to: CGPoint(x: p.x + (p.x - e.x) * 0.15, y: p.y + 0.03 + seed[i] * 0.02))
        }
        ctx.strokePath()
    }

    private static func drawMouth(_ c: Creep, _ ctx: CGContext, cy: CGFloat) {
        let my = cy - 0.66
        let gr = c.grin
        let w = 0.3 + 0.3 * gr
        let cornerY = my + 0.03 + 0.12 * gr
        let topCtrl = my - 0.02 - 0.02 * gr
        let botCtrl = my - 0.07 - 0.34 * gr
        func curveY(_ x: CGFloat, _ ctrl: CGFloat) -> CGFloat {
            let t = (x / w + 1) / 2
            return (1 - t) * (1 - t) * cornerY + 2 * t * (1 - t) * ctrl + t * t * cornerY
        }

        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: -w, y: cornerY))
        mouth.addQuadCurve(to: CGPoint(x: w, y: cornerY), control: CGPoint(x: 0, y: topCtrl))
        mouth.addQuadCurve(to: CGPoint(x: -w, y: cornerY), control: CGPoint(x: 0, y: botCtrl))
        mouth.closeSubpath()

        // Thin, bloodless lips stretched around it
        ctx.setStrokeColor(rgb(0.48, 0.38, 0.38, 0.75))
        ctx.setLineWidth(0.045)
        ctx.addPath(mouth)
        ctx.strokePath()

        ctx.saveGState()
        ctx.addPath(mouth)
        ctx.clip()
        ctx.drawLinearGradient(mouthInside, start: CGPoint(x: 0, y: (cornerY + botCtrl) / 2), end: CGPoint(x: 0, y: botCtrl),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        if gr > 0.04 {
            // Gums
            ctx.setStrokeColor(rgb(0.45, 0.16, 0.17))
            ctx.setLineWidth(0.06)
            ctx.move(to: CGPoint(x: -w, y: cornerY))
            ctx.addQuadCurve(to: CGPoint(x: w, y: cornerY), control: CGPoint(x: 0, y: topCtrl))
            ctx.strokePath()

            // Too many teeth, long and stained, a few gone
            func tooth(at x: CGFloat, root: CGFloat, length: CGFloat, down: Bool) {
                let d: CGFloat = down ? -1 : 1
                let p = CGMutablePath()
                p.move(to: CGPoint(x: x - w / 19, y: root - d * 0.02))
                p.addLine(to: CGPoint(x: x + w / 19, y: root - d * 0.02))
                p.addQuadCurve(to: CGPoint(x: x, y: root + d * length), control: CGPoint(x: x + w / 22, y: root + d * length * 0.9))
                p.addQuadCurve(to: CGPoint(x: x - w / 19, y: root - d * 0.02), control: CGPoint(x: x - w / 22, y: root + d * length * 0.9))
                ctx.saveGState()
                ctx.addPath(p)
                ctx.clip()
                ctx.drawLinearGradient(toothShade, start: CGPoint(x: x, y: root), end: CGPoint(x: x, y: root + d * length), options: [])
                ctx.restoreGState()
            }
            for i in -8...8 where c.seed[(i + 8) % 32] > 0.12 {
                let x = CGFloat(i) / 8.6 * w
                tooth(at: x, root: curveY(x, topCtrl) - 0.02, length: (0.07 + 0.1 * gr) * (0.75 + 0.5 * c.seed[(i + 20) % 32]), down: true)
            }
            for i in -6...6 where c.seed[(i + 14) % 32] > 0.15 {
                let x = CGFloat(i) / 6.8 * w * 0.85
                tooth(at: x, root: curveY(x, botCtrl) + 0.02, length: (0.04 + 0.05 * gr) * (0.75 + 0.5 * c.seed[(i + 6) % 32]), down: false)
            }
            // Shadow at the back of the mouth swallows the far teeth
            for s: CGFloat in [-1, 1] {
                blob(ctx, darkSoft, at: CGPoint(x: s * w, y: cornerY - 0.02), radius: 0.18, sx: 1, sy: 0.8)
            }
        }
        ctx.restoreGState()

        // Creases pulling the grin up into his cheeks
        ctx.setStrokeColor(rgb(0.12, 0.09, 0.09, 0.15 + 0.3 * gr))
        ctx.setLineWidth(0.03)
        for s: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: s * (w + 0.01), y: cornerY))
            ctx.addQuadCurve(to: CGPoint(x: s * (w + 0.03), y: cornerY + 0.14), control: CGPoint(x: s * (w + 0.07), y: cornerY + 0.04))
            ctx.strokePath()
        }
    }

    // MARK: - Hands

    private static func drawHands(_ c: Creep, _ ctx: CGContext) {
        guard c.fingers > 0.01 else { return }
        let lengths: [CGFloat] = [0.78, 0.98, 0.92, 0.7]
        let w: CGFloat = 0.11
        for (h, s) in [CGFloat(-1), 1].enumerated() {
            for i in 0..<4 {
                let len = (lengths[i] + 0.12 * c.seed[16 + h * 4 + i]) * c.fingers
                ctx.saveGState()
                ctx.translateBy(x: s * (0.95 + CGFloat(i) * 0.145), y: -0.25)
                ctx.rotate(by: -s * (CGFloat(i) - 1) * 0.08 + (c.seed[i + 4] - 0.5) * 0.06)
                let top = len + 0.25

                // Bony finger: slightly fatter at the knuckles, shaded round
                let finger = CGMutablePath()
                let k1 = top * 0.38, k2 = top * 0.7
                finger.move(to: CGPoint(x: -w / 2, y: 0))
                finger.addCurve(to: CGPoint(x: -w * 0.42, y: k2), control1: CGPoint(x: -w * 0.68, y: k1), control2: CGPoint(x: -w * 0.4, y: k1 + 0.1))
                finger.addCurve(to: CGPoint(x: 0, y: top), control1: CGPoint(x: -w * 0.62, y: k2 + 0.05), control2: CGPoint(x: -w * 0.5, y: top))
                finger.addCurve(to: CGPoint(x: w * 0.42, y: k2), control1: CGPoint(x: w * 0.5, y: top), control2: CGPoint(x: w * 0.62, y: k2 + 0.05))
                finger.addCurve(to: CGPoint(x: w / 2, y: 0), control1: CGPoint(x: w * 0.4, y: k1 + 0.1), control2: CGPoint(x: w * 0.68, y: k1))
                finger.closeSubpath()
                ctx.saveGState()
                ctx.addPath(finger)
                ctx.clip()
                ctx.drawLinearGradient(cylinder, start: CGPoint(x: -w * 0.7, y: 0), end: CGPoint(x: w * 0.7, y: 0), options: [])
                // Wrinkled, reddened knuckles and a bruised tip
                for ky in [k1, k2] where ky > 0.25 {
                    blob(ctx, blotch, at: CGPoint(x: 0, y: ky), radius: 0.08, sx: 1, sy: 0.8)
                    ctx.setStrokeColor(rgb(0.2, 0.16, 0.15, 0.35))
                    ctx.setLineWidth(0.006)
                    for j in -1...1 {
                        let y = ky + CGFloat(j) * 0.018
                        ctx.move(to: CGPoint(x: -w * 0.3, y: y))
                        ctx.addQuadCurve(to: CGPoint(x: w * 0.3, y: y), control: CGPoint(x: 0, y: y - 0.012))
                    }
                    ctx.strokePath()
                }
                blob(ctx, bruise, at: CGPoint(x: 0, y: top - 0.08), radius: 0.09)
                ctx.restoreGState()

                // Long, thick, yellowed nail
                let nail = CGMutablePath()
                nail.move(to: CGPoint(x: -w * 0.34, y: top - 0.13))
                nail.addLine(to: CGPoint(x: w * 0.34, y: top - 0.13))
                nail.addQuadCurve(to: CGPoint(x: w * 0.05, y: top + 0.08), control: CGPoint(x: w * 0.45, y: top + 0.02))
                nail.addQuadCurve(to: CGPoint(x: -w * 0.34, y: top - 0.13), control: CGPoint(x: -w * 0.45, y: top))
                ctx.saveGState()
                ctx.addPath(nail)
                ctx.clip()
                ctx.drawLinearGradient(nailShade, start: CGPoint(x: -w * 0.35, y: 0), end: CGPoint(x: w * 0.35, y: 0), options: [])
                ctx.setFillColor(rgb(0.15, 0.1, 0.05, 0.55))
                ctx.fill(CGRect(x: -w, y: top + 0.02, width: 2 * w, height: 0.1))
                ctx.restoreGState()
                ctx.restoreGState()
            }
        }
    }

    // MARK: - Handprint

    static func drawHandprint(_ h: Handprint, in ctx: CGContext, now: Double) {
        let age = now - h.born
        let alpha = CGFloat(age < 1.5 ? 1 : max(0, 1 - (age - 1.5) / 4.5))
        guard alpha > 0 else { return }
        ctx.saveGState()
        ctx.translateBy(x: h.point.x, y: h.point.y)
        ctx.rotate(by: h.angle)
        ctx.scaleBy(x: h.size, y: h.size)

        let lengths: [CGFloat] = [0.5, 0.62, 0.58, 0.42]
        ctx.setFillColor(rgb(0.45, 0.42, 0.38, 0.12 * alpha))
        for (ox, oy) in [(0, 0), (0.03, -0.02), (-0.02, 0.03)] as [(CGFloat, CGFloat)] {
            ctx.fillEllipse(in: CGRect(x: -0.42 + ox, y: -0.5 + oy, width: 0.84, height: 1.0))
            for i in 0..<4 {
                let x = -0.33 + CGFloat(i) * 0.22
                ctx.fillEllipse(in: CGRect(x: x - 0.08 + ox, y: 0.35 + oy, width: 0.16, height: lengths[i] + 0.15))
            }
            ctx.saveGState()
            ctx.translateBy(x: -0.42 + ox, y: -0.05 + oy)
            ctx.rotate(by: 0.7)
            ctx.fillEllipse(in: CGRect(x: -0.08, y: 0, width: 0.16, height: 0.5))
            ctx.restoreGState()
        }

        // Where it slid down the glass
        ctx.setStrokeColor(rgb(0.45, 0.42, 0.38, 0.09 * alpha))
        ctx.setLineWidth(0.06)
        ctx.setLineCap(.round)
        for i in 0..<4 {
            let x = -0.3 + CGFloat(i) * 0.2
            ctx.move(to: CGPoint(x: x, y: -0.4))
            ctx.addLine(to: CGPoint(x: x + 0.02, y: -0.9 - CGFloat(i) * 0.12))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}
