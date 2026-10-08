import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let tracker = GazeTracker()
    private let director = Director()
    private var overlay: OverlayWindow!
    private var creepView: CreepView!
    private var statusItem: NSStatusItem!
    private var statsItem: NSMenuItem!
    private var boldnessItems: [NSMenuItem] = []
    private var blinkItem: NSMenuItem!
    private var debugItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var calibrateItem: NSMenuItem!
    private var lastSample = GazeSample()
    private var lastTick = CACurrentMediaTime()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpOverlay()
        setUpMenu()

        tracker.update(calibration: settings.calibration)
        tracker.onSample = { [weak self] s in self?.handle(s) }
        director.onStatsChanged = { [weak self] in self?.updateStats() }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self, let screen = NSScreen.screens.first else { return }
            self.overlay.setFrame(screen.frame, display: true)
        }

        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        if settings.debugHUD { creepView.hud = DebugHUD(calibration: settings.calibration) }
        if !settings.paused { startTracking() }
    }

    // MARK: - Setup

    private func setUpOverlay() {
        let screen = NSScreen.screens.first ?? NSScreen.main!
        overlay = OverlayWindow(screen: screen)
        creepView = CreepView(director: director)
        overlay.contentView = creepView
        overlay.orderFrontRegardless()
    }

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()

        let menu = NSMenu()
        menu.delegate = self

        statsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        menu.addItem(.separator())

        let boldness = NSMenuItem(title: "Boldness", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for b in Boldness.allCases {
            let item = NSMenuItem(title: b.title, action: #selector(setBoldness(_:)), keyEquivalent: "")
            item.tag = b.rawValue
            item.target = self
            sub.addItem(item)
            boldnessItems.append(item)
        }
        boldness.submenu = sub
        menu.addItem(boldness)

        blinkItem = item("Blink Flashes", #selector(toggleBlink))
        menu.addItem(blinkItem)
        menu.addItem(.separator())
        calibrateItem = item("Calibrate Eyes…", #selector(calibrate))
        menu.addItem(calibrateItem)
        menu.addItem(item("Summon Him (Test)", #selector(summon)))
        debugItem = item("Show Tracking Debug", #selector(toggleDebug))
        menu.addItem(debugItem)
        menu.addItem(.separator())
        pauseItem = item("Leave Me Alone", #selector(togglePause))
        menu.addItem(pauseItem)
        menu.addItem(item("Quit Peeker", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))

        statusItem.menu = menu
        updateStats()
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateStats()
        for item in boldnessItems { item.state = item.tag == settings.boldness.rawValue ? .on : .off }
        blinkItem.state = settings.blinkFlashes ? .on : .off
        debugItem.state = settings.debugHUD ? .on : .off
        pauseItem.state = settings.paused ? .on : .off
        calibrateItem.isEnabled = !settings.paused && creepView.calibrator == nil
    }

    private func updateStats() {
        let peeks = settings.peeks, caught = settings.caught
        statsItem?.title = "He's peeked \(peeks) time\(peeks == 1 ? "" : "s") · You caught him \(caught)"
    }

    private func updateIcon() {
        let name = settings.paused ? "eye.slash" : "eye"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Peeker")
    }

    // MARK: - Tracking

    private func startTracking() {
        tracker.start { [weak self] ok in
            guard let self, !ok else { return }
            self.settings.paused = true
            self.updateIcon()
            self.cameraProblem()
        }
    }

    private func cameraProblem() {
        let denied = AVCaptureDevice.authorizationStatus(for: .video) == .denied
        let alert = NSAlert()
        alert.messageText = denied ? "He can't see you" : "No camera found"
        alert.informativeText = denied
            ? "Peeker needs camera access to know when you've looked away. Turn it on in System Settings → Privacy & Security → Camera, then unpause Peeker."
            : "Peeker couldn't open a camera."
        if denied { alert.addButton(withTitle: "Open Settings") }
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, denied,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private func handle(_ s: GazeSample) {
        let now = CACurrentMediaTime()
        lastSample = s
        creepView.calibrator?.ingest(s, now: now)
        director.ingest(s, now: now)
        if creepView.hud != nil {
            creepView.hud = DebugHUD(sample: s, calibration: settings.calibration, mode: director.modeName)
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastTick)
        lastTick = now
        director.canvas = creepView.bounds.size
        creepView.calibrator?.tick(now: now)
        director.tick(now: now, dt: dt)
        creepView.refresh()
    }

    // MARK: - Actions

    @objc private func setBoldness(_ sender: NSMenuItem) {
        settings.boldness = Boldness(rawValue: sender.tag) ?? .normal
    }

    @objc private func toggleBlink() {
        settings.blinkFlashes.toggle()
    }

    @objc private func summon() {
        director.summon(now: CACurrentMediaTime())
    }

    @objc private func togglePause() {
        settings.paused.toggle()
        updateIcon()
        if settings.paused {
            tracker.stop()
            director.reset()
        } else {
            startTracking()
        }
    }

    @objc private func toggleDebug() {
        settings.debugHUD.toggle()
        creepView.hud = settings.debugHUD
            ? DebugHUD(sample: lastSample, calibration: settings.calibration, mode: director.modeName)
            : nil
    }

    @objc private func calibrate() {
        director.reset()
        director.suspended = true
        let cal = Calibrator(now: CACurrentMediaTime(), base: settings.calibration)
        cal.onFinish = { [weak self] result in
            guard let self else { return }
            // Defer so we're not tearing down the calibrator from inside its own tick.
            DispatchQueue.main.async {
                self.creepView.calibrator = nil
                self.creepView.needsDisplay = true
                self.director.suspended = false
                switch result {
                case .success(let calibration):
                    self.settings.calibration = calibration
                    self.tracker.update(calibration: calibration)
                case .failure(let error):
                    let alert = NSAlert()
                    switch error {
                    case .noCamera:
                        alert.messageText = "The camera isn't sending anything"
                        alert.informativeText = "Peeker got no camera frames. Check it has camera access in System Settings → Privacy & Security → Camera, and that no other app is hogging the camera, then click Leave Me Alone twice to restart it."
                    case .noFace(let frames, let faces):
                        alert.messageText = "Couldn't see your face"
                        alert.informativeText = "Found a face in \(faces) of \(frames) camera frames. Try again facing the camera with a bit more light."
                    }
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            }
        }
        creepView.calibrator = cal
    }
}
