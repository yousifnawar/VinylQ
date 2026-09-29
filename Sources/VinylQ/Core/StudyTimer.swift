import AppKit
import Combine
import Foundation
import SwiftUI

/// The focus timer behind Study mode.
///
/// Deliberately quiet: it never steals focus, never shows an alert and never
/// pauses your music. A phase change is marked by one optional soft chime.
///
/// It publishes once a second — when the digits change — rather than on every
/// internal tick, so the notch, the ambient deck and the widgets that show it
/// redraw no more often than they must.
@MainActor
final class StudyTimer: ObservableObject {

    enum Phase: String, Equatable {
        case idle
        case focus
        case shortBreak
        case longBreak

        var title: String {
            switch self {
            case .idle:       return "Ready"
            case .focus:      return "Focus"
            case .shortBreak: return "Break"
            case .longBreak:  return "Long break"
            }
        }

        var isBreak: Bool { self == .shortBreak || self == .longBreak }

        var tint: Color {
            switch self {
            case .idle, .focus: return Theme.moss
            case .shortBreak:   return Theme.brass
            case .longBreak:    return Theme.rust
            }
        }
    }

    /// Focus / break pairs offered as one-tap presets.
    struct Preset: Identifiable, Equatable {
        var focus: Int
        var rest: Int
        var id: String { "\(focus)/\(rest)" }
        var label: String { "\(focus) · \(rest)" }

        static let all = [Preset(focus: 25, rest: 5), Preset(focus: 50, rest: 10), Preset(focus: 90, rest: 20)]
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isRunning = false
    @Published private(set) var blocksDone = 0
    /// Total length of the current phase, for the progress ring.
    @Published private(set) var phaseLength: TimeInterval = 0
    /// When the running block ends. `nil` while paused or idle.
    @Published private(set) var endDate: Date?
    /// Whole seconds left — changes once a second, which is what drives redraws.
    @Published private(set) var secondsLeft: Int = 0

    private let settings = Settings.shared
    /// Time left in a paused block.
    private var pausedRemaining: TimeInterval = 0
    private var timer: Timer?

    var remaining: TimeInterval {
        if isRunning, let endDate { return max(0, endDate.timeIntervalSinceNow) }
        return phase == .idle ? Double(settings.focusMinutes * 60) : pausedRemaining
    }

    var progress: Double { progress(at: Date()) }

    func progress(at date: Date) -> Double {
        guard phase != .idle, phaseLength > 0 else { return 0 }
        let left: TimeInterval
        if isRunning, let endDate { left = max(0, endDate.timeIntervalSince(date)) } else { left = pausedRemaining }
        return min(max(1 - left / phaseLength, 0), 1)
    }

    var remainingLabel: String {
        phase == .idle ? "\(settings.focusMinutes):00" : remaining.countdownString
    }

    /// "Block 2 of 4", "3 of 4 done"…
    var cycleCaption: String {
        let cycle = max(1, settings.cyclesUntilLongBreak)
        switch phase {
        case .idle:       return "\(settings.focusMinutes) min focus · \(settings.breakMinutes) min break"
        case .focus:      return "Block \(blocksDone % cycle + 1) of \(cycle)"
        case .shortBreak: return "\(blocksDone % cycle) of \(cycle) done"
        case .longBreak:  return "Cycle complete"
        }
    }

    var primaryActionTitle: String {
        switch (phase, isRunning) {
        case (.idle, _): return "Start focus"
        case (_, true):  return "Pause"
        case (_, false): return "Resume"
        }
    }

    var currentPreset: Preset? {
        Preset.all.first { $0.focus == settings.focusMinutes && $0.rest == settings.breakMinutes }
    }

    // MARK: Control

    /// Start, pause or resume — whichever makes sense right now.
    func start() {
        switch phase {
        case .idle:
            begin(.focus)
        default:
            if isRunning { pause() } else { resume() }
        }
    }

    func pause() {
        guard isRunning, let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        isRunning = false
        stopTicking()
        publishSeconds()
    }

    func resume() {
        guard !isRunning, phase != .idle else { return }
        endDate = Date().addingTimeInterval(pausedRemaining)
        isRunning = true
        startTicking()
        publishSeconds()
    }

    func reset() {
        stopTicking()
        phase = .idle
        isRunning = false
        pausedRemaining = 0
        phaseLength = 0
        blocksDone = 0
        endDate = nil
        publishSeconds()
    }

    /// Jump to whatever comes next without waiting it out.
    func skip() {
        guard phase != .idle else { return }
        advance(chime: false)
    }

    /// Applies a preset. A block already under way keeps its length; the new
    /// lengths take over from the next one.
    func apply(_ preset: Preset) {
        settings.focusMinutes = preset.focus
        settings.breakMinutes = preset.rest
        if phase == .idle { publishSeconds() }
    }

    // MARK: Phases

    private func begin(_ next: Phase) {
        let minutes: Int
        switch next {
        case .focus:      minutes = settings.focusMinutes
        case .shortBreak: minutes = settings.breakMinutes
        case .longBreak:  minutes = settings.longBreakMinutes
        case .idle:       minutes = 0
        }
        phase = next
        phaseLength = Double(max(1, minutes) * 60)
        pausedRemaining = phaseLength
        endDate = Date().addingTimeInterval(phaseLength)
        isRunning = true
        startTicking()
        publishSeconds()
    }

    private func advance(chime: Bool) {
        if chime, settings.chimeEnabled {
            Chime.play(named: settings.chimeName, volume: settings.chimeVolume)
        }

        let wasFocus = phase == .focus
        if wasFocus { blocksDone += 1 }

        let next: Phase
        if wasFocus {
            next = blocksDone % max(1, settings.cyclesUntilLongBreak) == 0 ? .longBreak : .shortBreak
        } else {
            next = .focus
        }

        begin(next)
        if !settings.autoContinue {
            // Wait for the user rather than rolling straight into the next block.
            pause()
        }
    }

    // MARK: Ticking

    private func startTicking() {
        stopTicking()
        // Ticks often enough to land on each second boundary; publishes only
        // when the displayed second actually changes.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        if endDate.timeIntervalSinceNow <= 0 {
            advance(chime: true)
            return
        }
        publishSeconds()
    }

    private func publishSeconds() {
        let seconds = Int(ceil(remaining - 0.001))
        if seconds != secondsLeft { secondsLeft = seconds }
    }

    /// Lets the settings pane preview the chime at the current volume.
    func previewChime() {
        Chime.play(named: settings.chimeName, volume: settings.chimeVolume)
    }
}
