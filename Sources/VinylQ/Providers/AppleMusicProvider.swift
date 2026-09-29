import AppKit
import Foundation

/// Drives Music.app over Apple Events.
///
/// Unlike Spotify, Music.app exposes the whole library, so playlist browsing
/// and "play this song" work with no account linking at all. Its playlists
/// are remembered between launches, so they're in the browser even while the
/// Music app is closed; choosing one opens Music in the background.
final class AppleMusicProvider: MusicProvider, @unchecked Sendable {

    let kind: SourceKind = .appleMusic
    private let bundleID = "com.apple.Music"
    private let runner = AppleScriptRunner.shared

    let runsOffMainThread = true

    var isAvailable: Bool { runner.isRunning(bundleID: bundleID) }

    // MARK: Now playing

    // Careful with names: `st`, `nd`, `rd` and `th` are reserved ordinal
    // suffixes in AppleScript, and a script using one never compiles.
    private let nowPlayingScript = """
    set fieldSep to character id 1
    tell application id "com.apple.Music"
        try
            if player state is stopped then return ""
            set theTrack to current track
            set stateText to "paused"
            if player state is playing then set stateText to "playing"
            set durationMS to 0
            try
                set durationMS to (round ((duration of theTrack) * 1000))
            end try
            set positionMS to (round ((player position) * 1000))
            return ((database ID of theTrack) as string) & fieldSep & (name of theTrack) & fieldSep ¬
                & (artist of theTrack) & fieldSep & (album of theTrack) & fieldSep & (durationMS as string) ¬
                & fieldSep & (positionMS as string) & fieldSep & stateText
        on error
            return ""
        end try
    end tell
    """

    func snapshot() -> PlaybackSnapshot? {
        guard isAvailable, let f = runner.fields(nowPlayingScript), f.count >= 7 else { return nil }
        let track = Track(
            id: f[0], title: f[1], artist: f[2], album: f[3],
            duration: (Double(f[4]) ?? 0) / 1000
        )
        return PlaybackSnapshot(
            track: track,
            isPlaying: f[6] == "playing",
            position: (Double(f[5]) ?? 0) / 1000,
            source: .appleMusic
        )
    }

    func artwork(for track: Track) -> NSImage? {
        let script = """
        tell application id "com.apple.Music"
            try
                return (raw data of artwork 1 of current track)
            on error
                return ""
            end try
        end tell
        """
        guard let data = runner.data(script) else { return nil }
        return NSImage(data: data)
    }

    // MARK: Transport

    private func tell(_ body: String) {
        runner.command("tell application id \"\(bundleID)\" to \(body)", requiring: bundleID)
    }

    func play()     { tell("play") }
    func pause()    { tell("pause") }
    func next()     { tell("next track") }
    func previous() { tell("back track") }

    func seek(to seconds: Double) {
        let ms = Int(max(0, seconds) * 1000)
        tell("set player position to (\(ms) / 1000)")
    }

    // MARK: Volume

    func setVolume(_ level: Double) {
        tell("set sound volume to \(Int((min(max(level, 0), 1) * 100).rounded()))")
    }

    /// Blocking Apple Event — call off the main thread.
    func volume() -> Double? {
        guard isAvailable,
              let text = runner.string("tell application id \"\(bundleID)\" to return (sound volume) as string"),
              let value = Double(text) else { return nil }
        return min(max(value / 100, 0), 1)
    }

    // MARK: Library

    /// Live from Music.app when it's open (and remembered); otherwise the
    /// list from last time.
    func playlists() -> [Playlist] {
        guard isAvailable else { return Self.remembered() }
        let script = """
        set fieldSep to character id 1
        set rowSep to character id 2
        tell application id "com.apple.Music"
            try
                set thePlaylists to (every user playlist whose special kind is none)
                set theIDs to (persistent ID of thePlaylists)
                set theNames to (name of thePlaylists)
                set theCounts to (count of tracks of thePlaylists)
                set output to ""
                repeat with i from 1 to (count of theIDs)
                    set output to output & (item i of theIDs) & fieldSep & (item i of theNames) & fieldSep ¬
                        & ((item i of theCounts) as string) & rowSep
                end repeat
                return output
            on error
                return ""
            end try
        end tell
        """
        guard let raw = runner.string(script) else { return Self.remembered() }
        let lists: [Playlist] = raw.components(separatedBy: "\u{2}").compactMap { row in
            let f = row.components(separatedBy: AppleScriptRunner.sep)
            guard f.count >= 3, !f[0].isEmpty else { return nil }
            return Playlist(id: f[0], name: f[1], source: .appleMusic, trackCount: Int(f[2]) ?? 0)
        }
        Self.remember(lists)
        return lists
    }

    func tracks(in playlist: Playlist) -> [Track] {
        guard openMusicIfNeeded() else { return [] }
        let script = """
        set fieldSep to character id 1
        set rowSep to character id 2
        tell application id "com.apple.Music"
            try
                set thePlaylist to (first playlist whose persistent ID is "\(Self.sanitised(playlist.id))")
                set theTracks to (every track of thePlaylist)
                set theIDs to (database ID of theTracks)
                set theNames to (name of theTracks)
                set theArtists to (artist of theTracks)
                set theAlbums to (album of theTracks)
                set theDurations to (duration of theTracks)
                set output to ""
                repeat with i from 1 to (count of theIDs)
                    set output to output & ((item i of theIDs) as string) & fieldSep & (item i of theNames) & fieldSep ¬
                        & (item i of theArtists) & fieldSep & (item i of theAlbums) & fieldSep ¬
                        & ((round ((item i of theDurations) * 1000)) as string) & rowSep
                end repeat
                return output
            on error
                return ""
            end try
        end tell
        """
        guard let raw = runner.string(script) else { return [] }
        return raw.components(separatedBy: "\u{2}").compactMap { row in
            let f = row.components(separatedBy: AppleScriptRunner.sep)
            guard f.count >= 5, !f[0].isEmpty else { return nil }
            return Track(id: f[0], title: f[1], artist: f[2], album: f[3],
                         duration: (Double(f[4]) ?? 0) / 1000)
        }
    }

    func play(track: Track, in playlist: Playlist?) {
        let trackID = Self.sanitised(track.id)
        let source: String
        if let playlist {
            source = """
            tell application id "\(bundleID)" to play (first track of (first playlist whose persistent ID is \
            "\(Self.sanitised(playlist.id))") whose database ID is \(trackID))
            """
        } else {
            source = "tell application id \"\(bundleID)\" to play (first track of library playlist 1 whose database ID is \(trackID))"
        }
        runner.commandLaunching(source, bundleID: bundleID)
    }

    /// Deletes a user playlist from Music.app itself. The songs stay in the
    /// library; only the playlist goes. Call off the main thread.
    func deletePlaylist(id: String) -> Bool {
        guard isAvailable else { return false }
        let script = """
        tell application id "\(bundleID)"
            try
                delete (first user playlist whose persistent ID is "\(Self.sanitised(id))")
                return "ok"
            on error
                return ""
            end try
        end tell
        """
        guard runner.string(script) == "ok" else { return false }
        Self.forget(id: id)
        return true
    }

    // MARK: Helpers

    /// Opening a playlist is a clear ask for the Music app, so open it — in
    /// the background — when it isn't running. Call off the main thread.
    private func openMusicIfNeeded() -> Bool {
        if isAvailable { return true }
        runner.launch(bundleID: bundleID)
        guard runner.waitUntilRunning(bundleID: bundleID, timeout: 15) else { return false }
        Thread.sleep(forTimeInterval: 1.5)
        return true
    }

    /// Persistent IDs are hex; database IDs are numbers.
    private static func sanitised(_ id: String) -> String {
        String(id.filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    // MARK: Remembered playlists

    private struct Stored: Codable {
        var id: String
        var name: String
        var count: Int
    }

    private static let storeKey = "appleMusic.playlists"

    private static func remember(_ lists: [Playlist]) {
        guard !lists.isEmpty else { return }
        let stored = lists.map { Stored(id: $0.id, name: $0.name, count: $0.trackCount) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private static func forget(id: String) {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              var stored = try? JSONDecoder().decode([Stored].self, from: data) else { return }
        stored.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private static func remembered() -> [Playlist] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let stored = try? JSONDecoder().decode([Stored].self, from: data) else { return [] }
        return stored.map { Playlist(id: $0.id, name: $0.name, source: .appleMusic, trackCount: $0.count) }
    }
}
