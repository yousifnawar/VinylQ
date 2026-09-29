import AppKit
import Foundation

/// The "tiny sound" that marks a break.
///
/// These are the sounds already on every Mac, so nothing ships with the app and
/// they blend in with the rest of the system instead of announcing themselves.
enum Chime: String, CaseIterable, Identifiable {
    case tink = "Tink"
    case glass = "Glass"
    case bottle = "Bottle"
    case pop = "Pop"
    case submarine = "Submarine"
    case purr = "Purr"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tink:      return "Tink — barely there"
        case .glass:     return "Glass — soft bell"
        case .bottle:    return "Bottle — hollow tap"
        case .pop:       return "Pop — dry click"
        case .submarine: return "Submarine — low ping"
        case .purr:      return "Purr — warm hum"
        }
    }

    /// Plays at `volume` (0–1). Silently does nothing if the sound is missing.
    func play(volume: Double) {
        guard let sound = NSSound(named: rawValue) else { return }
        sound.volume = Float(max(0, min(1, volume)))
        sound.play()
    }

    static func play(named name: String, volume: Double) {
        (Chime(rawValue: name) ?? .tink).play(volume: volume)
    }
}
