import AppKit
import Foundation

/// Everything the turntable needs from a music backend.
///
/// Implementations are polled off the main thread, so `snapshot()` and
/// `playlists()` must be safe to call from a background queue.
protocol MusicProvider: AnyObject, Sendable {
    var kind: SourceKind { get }

    /// `true` when this provider could produce music right now.
    var isAvailable: Bool { get }

    /// `true` when `snapshot()` blocks (Apple Events round-trips) and must be
    /// polled off the main thread. In-process providers leave this `false` so
    /// their `AVAudioPlayer` state is only ever touched from the main queue.
    var runsOffMainThread: Bool { get }

    /// Current state, or `nil` when the provider has nothing to report.
    func snapshot() -> PlaybackSnapshot?

    /// Artwork for `track`. Called only when the track changes.
    func artwork(for track: Track) -> NSImage?

    // Transport
    func play()
    func pause()
    func next()
    func previous()

    /// The whole point of the stylus: jump to `seconds` into the track.
    func seek(to seconds: Double)

    /// Output level, `0...1`. Spotify and Music set their own app's volume;
    /// local files set the player's.
    func setVolume(_ level: Double)
    /// The level the source is at right now, if it can say.
    func volume() -> Double?

    // Library
    func playlists() -> [Playlist]
    func tracks(in playlist: Playlist) -> [Track]
    func play(track: Track, in playlist: Playlist?)
}

extension MusicProvider {
    var runsOffMainThread: Bool { false }
    func setVolume(_ level: Double) {}
    func volume() -> Double? { nil }
    func artwork(for track: Track) -> NSImage? { nil }
    func playlists() -> [Playlist] { [] }
    func tracks(in playlist: Playlist) -> [Track] { [] }
    func play(track: Track, in playlist: Playlist?) {}
}
