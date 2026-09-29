import AppKit
import Foundation

/// Where the music is coming from.
enum SourceKind: String, CaseIterable, Identifiable, Codable {
    case local      = "Local Library"
    case appleMusic = "Apple Music"
    case spotify    = "Spotify"
    case demo       = "Demo Record"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .local:      return "folder.fill"
        case .appleMusic: return "music.note"
        case .spotify:    return "waveform"
        case .demo:       return "sparkles"
        }
    }

    /// Bundle id of the app we drive, when the source is another app.
    var hostBundleID: String? {
        switch self {
        case .appleMusic:   return "com.apple.Music"
        case .spotify:      return "com.spotify.client"
        case .local, .demo: return nil
        }
    }
}

/// One song, normalised across every source.
struct Track: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var artist: String
    var album: String
    /// Seconds. `0` when the source won't tell us.
    var duration: Double
    /// Set by Spotify (remote image) — local/Music.app artwork is loaded from data.
    var artworkURL: URL?
    var fileURL: URL?

    static func == (a: Track, b: Track) -> Bool {
        a.id == b.id && a.title == b.title && a.artist == b.artist
            && a.album == b.album && a.duration == b.duration
    }

    static let silence = Track(
        id: "wax.silence", title: "Nothing spinning",
        artist: "Drop the needle to begin", album: "", duration: 0
    )

    var isSilence: Bool { id == Track.silence.id }
}

/// A playlist as presented in the playlist browser.
struct Playlist: Identifiable, Equatable {
    var id: String
    var name: String
    var source: SourceKind
    var trackCount: Int
    /// Filled in lazily — we ask for tracks only when a playlist is opened.
    var tracks: [Track] = []
    /// Plays as a whole rather than opening into a track list — a Spotify
    /// playlist or album you've added by link, whose tracks only Spotify knows.
    var isCollection: Bool = false
    /// A small cover, when the source offers one.
    var artworkURL: URL?

    static func == (a: Playlist, b: Playlist) -> Bool {
        a.id == b.id && a.source == b.source && a.name == b.name
            && a.trackCount == b.trackCount && a.tracks.count == b.tracks.count
            && a.isCollection == b.isCollection
    }
}

/// What a source reports on each poll.
struct PlaybackSnapshot: Equatable {
    var track: Track
    var isPlaying: Bool
    /// Seconds into the track.
    var position: Double
    var source: SourceKind
    /// Identifier of the playlist currently playing, when known.
    var contextID: String?

    var progress: Double {
        guard track.duration > 0 else { return 0 }
        return min(max(position / track.duration, 0), 1)
    }

    static func idle(_ source: SourceKind) -> PlaybackSnapshot {
        PlaybackSnapshot(track: .silence, isPlaying: false, position: 0, source: source)
    }

    /// Whether `other` differs in a way anyone would see — ignoring the
    /// position creeping forward, which views extrapolate for themselves.
    func differsVisibly(from other: PlaybackSnapshot) -> Bool {
        track != other.track || isPlaying != other.isPlaying
            || source != other.source || contextID != other.contextID
    }
}
