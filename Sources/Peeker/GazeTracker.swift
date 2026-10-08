import AVFoundation
import Vision

enum AwayDirection: String {
    case left, right, down, unknown
}

struct GazeSample {
    var facePresent = false
    /// Vision's head yaw, only used as a backstop for big turns.
    var yaw = 0.0
    var pitch = 0.0
    /// Head turn and eye turn in camera-image terms; positive is towards the screen's left.
    var headTurn = 0.0
    var eyeTurn = 0.0
    /// Where you're actually looking: head turn plus eye turn.
    var look = 0.0
    var openness = 0.0
    var openBaseline = 0.0
    var eyesClosed = false
    var lookingAway = false
    var awayDirection: AwayDirection = .unknown
    /// Eye outlines and pupils (face-box normalised), for the debug HUD.
    var eyeShapes: [(contour: [CGPoint], pupil: CGPoint)] = []
}

/// Watches the webcam and works out whether you're looking at the screen,
/// adding head turn to eye turn so turning your head while your eyes stay on the screen still counts as looking.
final class GazeTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onSample: ((GazeSample) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "peeker.gaze")
    private var configured = false
    private var calibration = Calibration()

    // Everything below is only touched on `queue`.
    private var yaw = 0.0
    private var pitch = 0.0
    private var headTurn = 0.0
    private var eyeTurn = 0.0
    private var hasSignal = false
    private var openBaseline = 0.0
    /// Last few seconds of eye openness; the baseline is a high percentile of it,
    /// so blinks pull it down and odd frames can't drag it up.
    private var openHistory: [Double] = []
    private var closedFrames = 0
    private var eyesClosed = false
    private var lookingAway = false
    private var awayDirection: AwayDirection = .unknown
    private var awayFrames = 0
    private var backFrames = 0

    // Rough conversions to radians so head and eye turns can be added together.
    private let headGain = 1.7  // nose offset / eye spacing
    private let eyeGain = 0.8   // pupil position across the eye (-1...1)

    func start(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.queue.async {
                if !self.configured { self.configure() }
                if self.configured { self.session.startRunning() }
                let ok = self.configured
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    func stop() {
        queue.async {
            self.session.stopRunning()
            self.hasSignal = false
            self.lookingAway = false
            self.eyesClosed = false
            self.openHistory = []
            self.closedFrames = 0
            self.awayFrames = 0
            self.backFrames = 0
        }
    }

    func update(calibration: Calibration) {
        queue.async { self.calibration = calibration }
    }

    private func configure() {
        let builtIn = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified
        ).devices.first
        guard let device = builtIn ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        // Pupils are only a few pixels wide, so give Vision as many as we reasonably can.
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        configured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let faces = VNDetectFaceRectanglesRequest()
        faces.revision = VNDetectFaceRectanglesRequestRevision3
        let marks = VNDetectFaceLandmarksRequest()
        marks.revision = VNDetectFaceLandmarksRequestRevision3
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([faces, marks])

        var s = GazeSample()
        let face = largest(faces.results)
        s.facePresent = face.map { $0.boundingBox.width > 0.06 } ?? false

        if let face, s.facePresent {
            let newYaw = face.yaw?.doubleValue ?? yaw
            let newPitch = face.pitch?.doubleValue ?? pitch
            yaw = hasSignal ? yaw + (newYaw - yaw) * 0.4 : newYaw
            pitch = hasSignal ? pitch + (newPitch - pitch) * 0.4 : newPitch
            hasSignal = true
        }

        if s.facePresent, let lm = largest(marks.results)?.landmarks,
           let l = eyeMetrics(lm.leftEye, lm.leftPupil),
           let r = eyeMetrics(lm.rightEye, lm.rightPupil) {
            let open = (l.open + r.open) / 2
            openHistory.append(open)
            if openHistory.count > 120 { openHistory.removeFirst() }
            openBaseline = openHistory.sorted()[Int(Double(openHistory.count - 1) * 0.7)]
            closedFrames = open < openBaseline * 0.6 ? closedFrames + 1 : 0
            // Blinks last a few frames. "Closed" for over a second means the reading's off, not your eyes.
            eyesClosed = openHistory.count >= 15 && closedFrames > 0 && closedFrames < 30
            if !eyesClosed {
                eyeTurn += ((l.gaze + r.gaze) / 2 * eyeGain - eyeTurn) * 0.35
            }
            // Head turn from where the nose sits between the eyes. Same image axis as the
            // pupils, so an eye swinging back to the screen cancels a turned head.
            if let el = centroid(lm.leftEye), let er = centroid(lm.rightEye), let nose = centroid(lm.nose),
               abs(er.x - el.x) > 0.01 {
                let turn = (nose.x - (el.x + er.x) / 2) / abs(er.x - el.x) * headGain
                headTurn += (turn - headTurn) * 0.4
            }
            s.openness = open
            for (eye, pupil) in [(lm.leftEye, lm.leftPupil), (lm.rightEye, lm.rightPupil)] {
                if let contour = eye?.normalizedPoints, let p = pupil?.normalizedPoints.first {
                    s.eyeShapes.append((contour, p))
                }
            }
        } else {
            eyesClosed = false
        }

        let c = calibration
        let look = headTurn + eyeTurn
        let dl = look - c.look0
        let dp = pitch - c.pitch0

        var rawAway = !s.facePresent
            || abs(dl) > c.lookThreshold
            || dp > c.pitchHigh || dp < c.pitchLow
            || abs(yaw - c.yaw0) > 0.9  // turned so far the eyes can't be on the screen
        // A blink isn't looking away.
        if eyesClosed { rawAway = lookingAway }

        if rawAway {
            awayFrames += 1
            backFrames = 0
        } else {
            backFrames += 1
            awayFrames = 0
        }
        // Needs half a second of definitely-away; notices you looking back almost instantly.
        if !lookingAway && awayFrames >= 15 { lookingAway = true }
        if lookingAway && backFrames >= 2 { lookingAway = false }

        if !s.facePresent {
            awayDirection = .unknown
        } else if rawAway {
            let h = dl / c.lookThreshold
            let v = dp >= 0 ? dp / c.pitchHigh : dp / c.pitchLow
            awayDirection = v > abs(h) ? .down : (h > 0 ? .left : .right)
        }

        s.yaw = yaw
        s.pitch = pitch
        s.headTurn = headTurn
        s.eyeTurn = eyeTurn
        s.look = look
        s.openBaseline = openBaseline
        s.eyesClosed = eyesClosed
        s.lookingAway = lookingAway
        s.awayDirection = awayDirection
        DispatchQueue.main.async { self.onSample?(s) }
    }

    /// Pupil position across the eye (-1...1) and how open the eye is (height / width).
    private func eyeMetrics(_ eye: VNFaceLandmarkRegion2D?, _ pupil: VNFaceLandmarkRegion2D?) -> (gaze: Double, open: Double)? {
        guard let points = eye?.normalizedPoints, points.count >= 4,
              let p = pupil?.normalizedPoints.first else { return nil }
        let xs = points.map { Double($0.x) }
        let ys = points.map { Double($0.y) }
        let minX = xs.min()!, maxX = xs.max()!
        let width = maxX - minX
        guard width > 0 else { return nil }
        let height = ys.max()! - ys.min()!
        return (((Double(p.x) - minX) / width - 0.5) * 2, height / width)
    }

    private func centroid(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
        guard let points = region?.normalizedPoints, !points.isEmpty else { return nil }
        let n = CGFloat(points.count)
        return CGPoint(x: points.map(\.x).reduce(0, +) / n, y: points.map(\.y).reduce(0, +) / n)
    }

    private func largest(_ faces: [VNFaceObservation]?) -> VNFaceObservation? {
        faces?.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
    }
}
