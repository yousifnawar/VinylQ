import AppKit
import Foundation
import SwiftUI

/// Everything a widget needs in order to draw VinylQ.
///
/// The app writes this whenever something you'd see changes — a new record, a
/// pause, a timer starting — and the widget extension reads it when WidgetKit
/// asks for a timeline. It's a snapshot rather than a stream: positions are
/// stored with the moment they were true, so a widget can count forward on its
/// own (`Text(timerInterval:)`, `ProgressView(timerInterval:)`) without VinylQ
/// having to wake it every second.
struct WidgetState: Codable, Equatable {

    struct Track: Codable, Equatable {
        var id: String
        var title: String
        var artist: String
        var album: String
        /// Display name of where it's playing from ("Spotify").
        var source: String
        var sourceSymbol: String
        var duration: Double
        var isSilence: Bool
    }

    struct NowPlaying: Codable, Equatable {
        var track: Track
        var isPlaying: Bool
        /// Seconds into the track at `WidgetState.writtenAt`.
        var position: Double
        var accent: RGB
        /// File name inside `WidgetStore.folder`, when there's cover art.
        var artworkFile: String?
    }

    enum Phase: String, Codable {
        case idle, focus, shortBreak, longBreak

        var title: String {
            switch self {
            case .idle:       return "Ready"
            case .focus:      return "Focus"
            case .shortBreak: return "Break"
            case .longBreak:  return "Long break"
            }
        }

        var tint: Color {
            switch self {
            case .idle, .focus: return Theme.moss
            case .shortBreak:   return Theme.brass
            case .longBreak:    return Theme.rust
            }
        }
    }

    struct Focus: Codable, Equatable {
        var phase: Phase
        var isRunning: Bool
        /// When the current block ends, while it's running.
        var endDate: Date?
        /// Seconds left, when paused or idle.
        var remaining: Double
        var phaseLength: Double
        var blocksDone: Int
        var blocksPerLongBreak: Int
        var focusMinutes: Int
        var breakMinutes: Int
        var longBreakMinutes: Int
    }

    struct RGB: Codable, Equatable {
        var red: Double
        var green: Double
        var blue: Double

        var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

        static let brass = RGB(red: 0xE0 / 255, green: 0xA4 / 255, blue: 0x58 / 255)
    }

    var writtenAt: Date
    var appRunning: Bool
    var nowPlaying: NowPlaying
    var focus: Focus
}

// MARK: - Reading the snapshot forward in time

extension WidgetState {

    var accent: Color { nowPlaying.accent.color }

    /// The wall-clock moment the current track would have started, had it
    /// played straight through — what `ProgressView(timerInterval:)` wants.
    var trackStart: Date { writtenAt.addingTimeInterval(-nowPlaying.position) }

    var trackEnd: Date? {
        let duration = nowPlaying.track.duration
        return duration > 0 ? trackStart.addingTimeInterval(duration) : nil
    }

    func elapsed(at date: Date) -> Double {
        let duration = nowPlaying.track.duration
        guard nowPlaying.isPlaying else { return nowPlaying.position }
        let elapsed = nowPlaying.position + date.timeIntervalSince(writtenAt)
        return duration > 0 ? min(max(elapsed, 0), duration) : max(elapsed, 0)
    }

    func progress(at date: Date) -> Double {
        let duration = nowPlaying.track.duration
        guard duration > 0 else { return 0 }
        return min(max(elapsed(at: date) / duration, 0), 1)
    }

    func focusRemaining(at date: Date) -> Double {
        guard focus.isRunning, let end = focus.endDate else {
            return focus.phase == .idle ? Double(focus.focusMinutes * 60) : focus.remaining
        }
        return max(0, end.timeIntervalSince(date))
    }

    func focusProgress(at date: Date) -> Double {
        guard focus.phase != .idle, focus.phaseLength > 0 else { return 0 }
        return min(max(1 - focusRemaining(at: date) / focus.phaseLength, 0), 1)
    }

    /// The block after this one, for "then a 5 min break".
    var nextPhase: Phase {
        switch focus.phase {
        case .idle:
            return .focus
        case .focus:
            let upcoming = focus.blocksDone + 1
            return upcoming % max(1, focus.blocksPerLongBreak) == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }

    func minutes(for phase: Phase) -> Int {
        switch phase {
        case .idle, .focus: return focus.focusMinutes
        case .shortBreak:   return focus.breakMinutes
        case .longBreak:    return focus.longBreakMinutes
        }
    }

    /// Where you are in the cycle: "Block 2 of 4", "3 of 4 done".
    var cycleCaption: String {
        let cycle = max(1, focus.blocksPerLongBreak)
        switch focus.phase {
        case .idle:       return "\(focus.focusMinutes) min focus · \(focus.breakMinutes) min break"
        case .focus:      return "Block \(focus.blocksDone % cycle + 1) of \(cycle)"
        case .shortBreak: return "\(focus.blocksDone % cycle) of \(cycle) done"
        case .longBreak:  return "Cycle complete"
        }
    }
}

// MARK: - A record to show before VinylQ has said anything

extension WidgetState {

    /// Shown in the widget gallery and before the app has run once.
    static func preview(at date: Date = Date()) -> WidgetState {
        WidgetState(
            writtenAt: date,
            appRunning: true,
            nowPlaying: NowPlaying(
                track: Track(id: "demo.1", title: "Golden Hour", artist: "The Warm Static",
                             album: "Sunset Sessions", source: "Demo Record", sourceSymbol: "sparkles",
                             duration: 214, isSilence: false),
                isPlaying: true,
                position: 71,
                accent: .brass,
                artworkFile: nil
            ),
            focus: Focus(
                phase: .focus, isRunning: true, endDate: date.addingTimeInterval(13 * 60 + 24),
                remaining: 13 * 60 + 24, phaseLength: 25 * 60, blocksDone: 1, blocksPerLongBreak: 4,
                focusMinutes: 25, breakMinutes: 5, longBreakMinutes: 20
            )
        )
    }
}

// MARK: - Where it lives

/// The folder VinylQ shares with its widgets.
///
/// Widgets are sandboxed. Their entitlements grant read access to exactly one
/// folder in your real home — this one — so the app (which isn't sandboxed)
/// can hand them what's playing without any other channel.
enum WidgetStore {

    /// Your real home, even from inside the widget's sandbox container.
    static var home: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var folder: URL {
        home.appendingPathComponent("Library/Application Support/VinylQ/Widgets", isDirectory: true)
    }

    static var stateURL: URL { folder.appendingPathComponent("state.json") }

    static func load() -> WidgetState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetState.self, from: data)
    }

    static func save(_ state: WidgetState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: stateURL, options: .atomic)
    }

    static func artwork(named name: String?) -> NSImage? {
        guard let name, !name.isEmpty else { return nil }
        return NSImage(contentsOf: folder.appendingPathComponent(name))
    }
}

// MARK: - Talking back to the app

/// What a widget's buttons can ask VinylQ to do.
///
/// Widgets run in their own sandboxed process, so a tap arrives at VinylQ as a
/// distributed notification — no payload, just the name. If VinylQ isn't running,
/// the same command travels as a `vinylq://command/…` link, which launches it.
enum VinylQCommand: String, CaseIterable {
    case togglePlayback
    case nextTrack
    case previousTrack
    case toggleFocus
    case skipFocus
    case resetFocus

    var notificationName: Notification.Name {
        Notification.Name("app.wax.deck.command.\(rawValue)")
    }

    var url: URL { URL(string: "vinylq://command/\(rawValue)")! }

    func post() {
        DistributedNotificationCenter.default().postNotificationName(
            notificationName, object: nil, userInfo: nil, deliverImmediately: true
        )
    }
}

/// Widget kinds, shared so the app can reload exactly the ones that changed.
enum VinylQWidgetKind {
    static let nowPlaying = "app.wax.deck.nowPlaying"
    static let focus = "app.wax.deck.focus"
    static let all = [nowPlaying, focus]
}

/// Whether VinylQ itself is running, as far as a widget can tell. Buttons use
/// it to choose between a silent intent and a link that opens the app.
private struct VinylQAppRunningKey: EnvironmentKey {
    static let defaultValue = true
}

/// Set by the app's previews, which redraw every second and can draw their
/// own bar; real widgets rely on `ProgressView(timerInterval:)` instead.
private struct VinylQDrawsOwnProgressKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var vinylqAppRunning: Bool {
        get { self[VinylQAppRunningKey.self] }
        set { self[VinylQAppRunningKey.self] = newValue }
    }

    var vinylqDrawsOwnProgress: Bool {
        get { self[VinylQDrawsOwnProgressKey.self] }
        set { self[VinylQDrawsOwnProgressKey.self] = newValue }
    }
}

// MARK: - Generated sleeves

/// Cover art for records that don't come with any — the demo side, and the
/// widget gallery's preview. Seeded from the track, so it's the same every time.
enum DemoArt {

    static func sleeve(for id: String, side: CGFloat = 600) -> NSImage {
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size)
        image.lockFocus()
        // Kept to the warm end of the wheel — rust through amber — so the
        // demo record matches the deck's brass rather than fighting it.
        let seed = 0.015 + Double(stableHash(id) % 1000) / 1000 * 0.10
        NSGradient(
            starting: NSColor(calibratedHue: seed, saturation: 0.55, brightness: 0.72, alpha: 1),
            ending:   NSColor(calibratedHue: fmod(seed + 0.04, 1), saturation: 0.62, brightness: 0.24, alpha: 1)
        )?.draw(in: NSRect(origin: .zero, size: size), angle: 55)

        // A few concentric rings, like a printed sleeve.
        NSColor(white: 1, alpha: 0.10).setStroke()
        let middle = side / 2
        for ring in stride(from: side * 0.15, to: side * 0.5, by: side * 0.07) {
            let path = NSBezierPath(ovalIn: NSRect(x: middle - ring, y: middle - ring,
                                                   width: ring * 2, height: ring * 2))
            path.lineWidth = side * 0.013
            path.stroke()
        }
        image.unlockFocus()
        return image
    }

    /// FNV-1a. `hashValue` is reseeded every launch, which would repaint the
    /// demo sleeve a different colour each time.
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
