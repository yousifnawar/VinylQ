import Foundation

/// Thread-safe mirror of everything VinylQ knows about your Spotify library.
///
/// `SpotifyLibrary` and `SpotifyWebAPI` live on the main actor (they publish
/// to SwiftUI), but `SpotifyProvider` is polled from a background queue
/// alongside the other Apple Events providers. This is the small shared box
/// between them.
final class SpotifyCache: @unchecked Sendable {

    private let lock = NSLock()
    private var playlists: [Playlist] = []
    private var tracks: [String: [Track]] = [:]
    private var recent: [Track] = []
    private var webRecent: [Track] = []
    private var saved: [SpotifyCollection] = []
    private var signedInUser: String?

    // MARK: Web API

    /// The signed-in Spotify user, for Liked Songs' play context.
    var userID: String? {
        lock.lock(); defer { lock.unlock() }
        return signedInUser
    }

    func setUserID(_ value: String?) {
        lock.lock(); signedInUser = value; lock.unlock()
    }

    /// Spotify's own play history — includes what you played on your phone.
    var webRecentTracks: [Track] {
        lock.lock(); defer { lock.unlock() }
        return webRecent
    }

    func setWebRecent(_ value: [Track]) {
        lock.lock(); webRecent = value; lock.unlock()
    }

    var allPlaylists: [Playlist] {
        lock.lock(); defer { lock.unlock() }
        return playlists
    }

    func tracks(for playlistID: String) -> [Track] {
        lock.lock(); defer { lock.unlock() }
        return tracks[playlistID] ?? []
    }

    func hasTracks(for playlistID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return tracks[playlistID] != nil
    }

    func setPlaylists(_ value: [Playlist]) {
        lock.lock(); playlists = value; lock.unlock()
    }

    func setTracks(_ value: [Track], for playlistID: String) {
        lock.lock(); tracks[playlistID] = value; lock.unlock()
    }

    func clearWebLibrary() {
        lock.lock(); playlists = []; tracks = [:]; webRecent = []; lock.unlock()
    }

    // MARK: No-login library

    var recentTracks: [Track] {
        lock.lock(); defer { lock.unlock() }
        return recent
    }

    var savedCollections: [SpotifyCollection] {
        lock.lock(); defer { lock.unlock() }
        return saved
    }

    func setRecent(_ value: [Track]) {
        lock.lock(); recent = value; lock.unlock()
    }

    func setSaved(_ value: [SpotifyCollection]) {
        lock.lock(); saved = value; lock.unlock()
    }
}
