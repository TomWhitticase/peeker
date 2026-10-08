import Foundation

enum Boldness: Int, CaseIterable {
    case shy, normal, livesHere

    var title: String {
        switch self {
        case .shy: "Shy"
        case .normal: "Normal"
        case .livesHere: "He Lives Here Now"
        }
    }

    /// How long you have to be looking away before he starts creeping out.
    var peekDelay: ClosedRange<Double> {
        switch self {
        case .shy: 2.5...4.5
        case .normal: 1.2...2.5
        case .livesHere: 0.5...1.2
        }
    }

    /// Seconds of looking away until he's fully out (whole face, fingers, grin).
    var growthTime: Double {
        switch self {
        case .shy: 16
        case .normal: 9
        case .livesHere: 4
        }
    }

    var rareMultiplier: Double {
        switch self {
        case .shy: 0.6
        case .normal: 1
        case .livesHere: 2
        }
    }
}

/// Where "looking at the screen" sits for this face, and how far off counts as away.
struct Calibration: Codable {
    /// Combined head + eye direction (radians, roughly) when looking at the screen centre.
    var look0 = 0.0
    var pitch0 = 0.0
    var yaw0 = 0.0
    var lookThreshold = 0.45
    /// Head tilt limits either side of pitch0; the up and down sides differ, so they're separate.
    var pitchHigh = 0.45
    var pitchLow = -0.45
    var isCustom = false
}

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    var boldness: Boldness {
        get { Boldness(rawValue: defaults.object(forKey: "boldness") as? Int ?? 1) ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: "boldness") }
    }

    var blinkFlashes: Bool {
        get { defaults.object(forKey: "blinkFlashes") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "blinkFlashes") }
    }

    var debugHUD: Bool {
        get { defaults.bool(forKey: "debugHUD") }
        set { defaults.set(newValue, forKey: "debugHUD") }
    }

    var paused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused") }
    }

    var peeks: Int {
        get { defaults.integer(forKey: "peeks") }
        set { defaults.set(newValue, forKey: "peeks") }
    }

    var caught: Int {
        get { defaults.integer(forKey: "caught") }
        set { defaults.set(newValue, forKey: "caught") }
    }

    var calibration: Calibration {
        get {
            guard let data = defaults.data(forKey: "calibration"),
                  let c = try? JSONDecoder().decode(Calibration.self, from: data) else { return Calibration() }
            return c
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "calibration") }
    }
}
