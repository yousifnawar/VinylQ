import AppKit
import Foundation

/// Drives the Spotify desktop app over Apple Events.
///
/// This is the whole Spotify connection, and it needs no login: the Spotify
/// app is already signed in, and its scripting dictionary gives the turntable
/// everything — now playing, transport, `set player position` for the stylus,
/// and `play track` for any song, playlist or album URI. Playlist *listing*
/// is the one thing it can't do; `SpotifyLibrary` fills that gap without a
/// key, and `SpotifyWebAPI` can when a developer Client ID is built in.
final class SpotifyProvider: MusicProvider, @unchecked Sendable {

    let kind: SourceKind = .spotify
    static let bundleID = "com.spotify.client"
    /// The synthetic playlist of songs you've played in Spotify.
    static let recentID = "spotify.recent"
    /// Liked Songs, once you're signed in.
    static let likedID = "spotify.liked"

    private let runner = AppleScriptRunner.shared
    private let cache: SpotifyCache

    init(cache: SpotifyCache) {
        self.cache = cache
    }

    let runsOffMainThread = true

    var isAvailable: Bool { runner.isRunning(bundleID: Self.bundleID) }

    // MARK: Now playing

    // Variable names matter here: AppleScript reserves some short words —
    // `st`, `nd`, `rd` and `th` are ordinal suffixes ("1st") — and a script
    // that uses one doesn't compile at all, so every read silently fails.
    private let nowPlayingScript = """
    set fieldSep to character id 1
    tell application id "com.spotify.client"
        try
            if player state is stopped then return ""
            set theTrack to current track
            set stateText to "paused"
            if player state is playing then set stateText to "playing"
            set durationMS to 0
            try
                set durationMS to (duration of theTrack)
            end try
            set positionMS to (round ((player position) * 1000))
            set artworkText to ""
            try
                set artworkText to (artwork url of theTrack)
            end try
            return ((id of theTrack) as string) & fieldSep & (name of theTrack) & fieldSep & (artist of theTrack) & fieldSep ¬
                & (album of theTrack) & fieldSep & (durationMS as string) & fieldSep & (positionMS as string) & fieldSep ¬
                & stateText & fieldSep & artworkText
        on error
            return ""
        end try
    end tell
    """

    func snapshot() -> PlaybackSnapshot? {
        guard isAvailable, let f = runner.fields(nowPlayingScript), f.count >= 7 else { return nil }
        let track = Track(
            id: f[0],
            title: f[1],
            artist: f[2],
            album: f[3],
            duration: (Double(f[4]) ?? 0) / 1000,
            artworkURL: f.count > 7 ? URL(string: f[7]) : nil
        )
        return PlaybackSnapshot(
            track: track,
            isPlaying: f[6] == "playing",
            position: (Double(f[5]) ?? 0) / 1000,
            source: .spotify,
            contextID: nil
        )
    }

    func artwork(for track: Track) -> NSImage? {
        guard let url = track.artworkURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    // MARK: Transport

    private func tell(_ body: String) {
        runner.command("tell application id \"\(Self.bundleID)\" to \(body)", requiring: Self.bundleID)
    }

    func play()     { tell("play") }
    func pause()    { tell("pause") }
    func next()     { tell("next track") }
    func previous() { tell("previous track") }

    func seek(to seconds: Double) {
        // Integer milliseconds keep us clear of locale decimal separators.
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
              let text = runner.string("tell application id \"\(Self.bundleID)\" to return (sound volume) as string"),
              let value = Double(text) else { return nil }
        return min(max(value / 100, 0), 1)
    }

    // MARK: Library

    /// Liked Songs, Recently Played, your playlists (once signed in), and any
    /// playlist or album you've added by link.
    func playlists() -> [Playlist] {
        let web = cache.allPlaylists
        var lists: [Playlist] = web.filter { $0.id == SpotifyProvider.likedID }

        let recent = recentTracks()
        if !recent.isEmpty {
            lists.append(Playlist(id: Self.recentID, name: "Recently Played", source: .spotify,
                                  trackCount: recent.count))
        }
        lists += web.filter { $0.id != SpotifyProvider.likedID }

        // Links you dropped in, unless signing in already brought them.
        let known = Set(web.map { "spotify:playlist:\($0.id)" })
        lists += cache.savedCollections.filter { !known.contains($0.uri) }.map {
            Playlist(id: $0.uri, name: $0.name, source: .spotify, trackCount: 0,
                     isCollection: true, artworkURL: $0.imageURL)
        }
        return lists
    }

    func tracks(in playlist: Playlist) -> [Track] {
        playlist.id == Self.recentID ? recentTracks() : cache.tracks(for: playlist.id)
    }

    /// What you played here, then what Spotify remembers from elsewhere.
    private func recentTracks() -> [Track] {
        var seen = Set<String>()
        return (cache.recentTracks + cache.webRecentTracks)
            .filter { seen.insert($0.id).inserted }
            .prefix(50)
            .map { $0 }
    }

    /// Plays a song — inside its playlist when there is one, so Spotify
    /// carries on through the rest of it afterwards.
    func play(track: Track, in playlist: Playlist?) {
        let uri = Self.sanitised(track.id)
        let context: String?
        switch playlist {
        case let playlist? where playlist.id == SpotifyProvider.likedID:
            context = cache.userID.map { "spotify:user:\($0):collection" }
        case let playlist? where !playlist.isCollection && playlist.id != Self.recentID:
            context = "spotify:playlist:\(playlist.id)"
        default:
            context = nil
        }
        if let context {
            runner.commandLaunching(
                "tell application id \"\(Self.bundleID)\" to play track \"\(uri)\" in context \"\(Self.sanitised(context))\"",
                bundleID: Self.bundleID)
        } else {
            runner.commandLaunching("tell application id \"\(Self.bundleID)\" to play track \"\(uri)\"",
                                    bundleID: Self.bundleID)
        }
    }

    /// Plays a whole playlist, album or artist — by URI, or by the bare ID
    /// the Web API uses for playlists.
    func playCollection(uri: String) {
        let full = uri.hasPrefix("spotify:") ? uri : "spotify:playlist:\(uri)"
        runner.commandLaunching("tell application id \"\(Self.bundleID)\" to play track \"\(Self.sanitised(full))\"",
                                bundleID: Self.bundleID)
    }

    /// URIs are base62 and colons; anything else has no business in a script.
    private static func sanitised(_ uri: String) -> String {
        String(uri.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ":" || $0 == "-" || $0 == "_") })
    }
}
