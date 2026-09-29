import AppKit
import Combine
import Foundation

/// Raw `UserDefaults` access, kept outside the main-actor model so it can be
/// used in stored-property default values.
enum Pref {
    static func bool(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }
    static func int(_ key: String, _ fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }
    static func double(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }
    static func string(_ key: String, _ fallback: String) -> String {
        UserDefaults.standard.object(forKey: key) as? String ?? fallback
    }
    static func put(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

/// Every user-facing preference, persisted as it changes.
@MainActor
final class Settings: ObservableObject {

    static let shared = Settings()

    // MARK: Deck

    /// Empty string means "follow whatever is playing".
    @Published var pinnedSourceRaw: String = Pref.string("deck.pinnedSource", "") {
        didSet { Pref.put("deck.pinnedSource", pinnedSourceRaw) }
    }
    @Published var rpm: Double = Pref.double("deck.rpm", 33.333) {
        didSet { Pref.put("deck.rpm", rpm) }
    }
    @Published var showGrain: Bool = Pref.bool("deck.showGrain", true) {
        didSet { Pref.put("deck.showGrain", showGrain) }
    }
    @Published var tintFromArtwork: Bool = Pref.bool("deck.tintFromArt", true) {
        didSet { Pref.put("deck.tintFromArt", tintFromArtwork) }
    }

    var pinnedSource: SourceKind? {
        get { SourceKind(rawValue: pinnedSourceRaw) }
        set { pinnedSourceRaw = newValue?.rawValue ?? "" }
    }

    // MARK: Notch

    @Published var notchEnabled: Bool = Pref.bool("notch.enabled", true) {
        didSet { Pref.put("notch.enabled", notchEnabled) }
    }
    @Published var notchOnAllSpaces: Bool = Pref.bool("notch.allSpaces", true) {
        didSet { Pref.put("notch.allSpaces", notchOnAllSpaces) }
    }
    /// The pill carries the countdown while a focus block runs.
    @Published var notchShowsTimer: Bool = Pref.bool("notch.showsTimer", true) {
        didSet { Pref.put("notch.showsTimer", notchShowsTimer) }
    }
    /// A new song briefly drops down from the notch with its name.
    @Published var notchPeekOnNewSong: Bool = Pref.bool("notch.peek", true) {
        didSet { Pref.put("notch.peek", notchPeekOnNewSong) }
    }

    // MARK: Ambient (full-screen) mode

    @Published var ambientShowClock: Bool = Pref.bool("ambient.clock", true) {
        didSet { Pref.put("ambient.clock", ambientShowClock) }
    }
    /// The focus timer, tucked under the clock.
    @Published var ambientShowTimer: Bool = Pref.bool("ambient.timer", true) {
        didSet { Pref.put("ambient.timer", ambientShowTimer) }
    }
    @Published var ambientTwentyFourHour: Bool = Pref.bool("ambient.24h", false) {
        didSet { Pref.put("ambient.24h", ambientTwentyFourHour) }
    }
    @Published var ambientShowSeconds: Bool = Pref.bool("ambient.seconds", false) {
        didSet { Pref.put("ambient.seconds", ambientShowSeconds) }
    }
    @Published var ambientDim: Double = Pref.double("ambient.dim", 0.82) {
        didSet { Pref.put("ambient.dim", ambientDim) }
    }

    // MARK: Study mode

    @Published var focusMinutes: Int = Pref.int("study.focus", 25) {
        didSet { Pref.put("study.focus", focusMinutes) }
    }
    @Published var breakMinutes: Int = Pref.int("study.break", 5) {
        didSet { Pref.put("study.break", breakMinutes) }
    }
    @Published var longBreakMinutes: Int = Pref.int("study.longBreak", 20) {
        didSet { Pref.put("study.longBreak", longBreakMinutes) }
    }
    @Published var cyclesUntilLongBreak: Int = Pref.int("study.cycles", 4) {
        didSet { Pref.put("study.cycles", cyclesUntilLongBreak) }
    }
    @Published var chimeEnabled: Bool = Pref.bool("study.chimeOn", true) {
        didSet { Pref.put("study.chimeOn", chimeEnabled) }
    }
    @Published var chimeName: String = Pref.string("study.chimeName", "Tink") {
        didSet { Pref.put("study.chimeName", chimeName) }
    }
    @Published var chimeVolume: Double = Pref.double("study.chimeVolume", 0.35) {
        didSet { Pref.put("study.chimeVolume", chimeVolume) }
    }
    @Published var autoContinue: Bool = Pref.bool("study.autoContinue", true) {
        didSet { Pref.put("study.autoContinue", autoContinue) }
    }

    private init() {}
}
