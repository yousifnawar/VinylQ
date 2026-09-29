import AVFoundation
import AppKit
import Foundation

/// Plays audio files from folders the user adds.
///
/// This is the source that works with nothing installed and no account, and
/// it is the one where the stylus feels best: seeking an `AVAudioPlayer` is
/// instant, so dragging the needle scrubs in real time rather than firing a
/// round-trip at another app.
final class LocalProvider: NSObject, MusicProvider, AVAudioPlayerDelegate, @unchecked Sendable {

    let kind: SourceKind = .local

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "alac", "m4b", "caf", "ogg"
    ]

    /// Folders the user has added, remembered between launches.
    private(set) var roots: [URL] {
        didSet {
            UserDefaults.standard.set(roots.map(\.path), forKey: "local.roots")
        }
    }

    private var player: AVAudioPlayer?
    private var queue: [Track] = []
    private var index: Int = 0
    private var current: Track?
    /// Read from the engine's background artwork queue, written by the tag
    /// loader, so it needs a lock of its own.
    private let artworkLock = NSLock()
    private var artworkCache: [String: NSImage] = [:]
    private var folders: [Playlist] = []
    private var tracksByFolder: [String: [Track]] = [:]

    /// Called when the library finishes scanning, so the UI can refresh.
    var onLibraryChange: (() -> Void)?

    /// Called when tags for the playing track arrive, which happens a beat
    /// after playback starts.
    var onNowPlayingChange: (() -> Void)?

    override init() {
        let saved = UserDefaults.standard.stringArray(forKey: "local.roots") ?? []
        roots = saved.map { URL(fileURLWithPath: $0) }
        super.init()
        if !roots.isEmpty { rescan() }
    }

    // MARK: Availability

    var isAvailable: Bool { !queue.isEmpty }

    // MARK: Library management

    func addRoot(_ url: URL) {
        guard !roots.contains(url) else { return }
        roots.append(url)
        rescan()
    }

    func removeRoot(_ url: URL) {
        roots.removeAll { $0 == url }
        rescan()
    }

    /// Walks every root on a background queue and rebuilds the folder playlists.
    func rescan() {
        let roots = self.roots
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var byFolder: [String: [Track]] = [:]
            var everything: [Track] = []

            for root in roots {
                let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                while let url = enumerator?.nextObject() as? URL {
                    guard Self.audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
                    let track = Self.quickTrack(for: url)
                    everything.append(track)
                    let folder = url.deletingLastPathComponent()
                    byFolder[folder.path, default: []].append(track)
                }
            }

            let sortedFolders = byFolder.keys.sorted {
                URL(fileURLWithPath: $0).lastPathComponent
                    .localizedCaseInsensitiveCompare(URL(fileURLWithPath: $1).lastPathComponent) == .orderedAscending
            }
            var playlists: [Playlist] = [
                Playlist(id: "local.all", name: "All Songs", source: .local,
                         trackCount: everything.count)
            ]
            playlists += sortedFolders.map { path in
                Playlist(id: path, name: URL(fileURLWithPath: path).lastPathComponent,
                         source: .local, trackCount: byFolder[path]?.count ?? 0)
            }

            let sortedAll = everything.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            byFolder["local.all"] = sortedAll

            DispatchQueue.main.async {
                self.tracksByFolder = byFolder
                self.folders = playlists
                if self.queue.isEmpty { self.queue = sortedAll }
                self.onLibraryChange?()
            }
        }
    }

    /// Cheap track built from the file name and container duration only —
    /// tag reading is deferred until the song actually plays.
    private static func quickTrack(for url: URL) -> Track {
        let name = url.deletingPathExtension().lastPathComponent
        let parent = url.deletingLastPathComponent()
        return Track(
            id: url.path,
            title: name,
            artist: parent.deletingLastPathComponent().lastPathComponent,
            album: parent.lastPathComponent,
            duration: 0,
            fileURL: url
        )
    }

    // MARK: Now playing

    func snapshot() -> PlaybackSnapshot? {
        guard let current, let player else {
            guard !queue.isEmpty else { return nil }
            return PlaybackSnapshot(track: .silence, isPlaying: false, position: 0, source: .local)
        }
        var track = current
        track.duration = player.duration
        return PlaybackSnapshot(
            track: track,
            isPlaying: player.isPlaying,
            position: player.currentTime,
            source: .local
        )
    }

    private func cache(_ image: NSImage, for trackID: String) {
        artworkLock.lock()
        artworkCache[trackID] = image
        artworkLock.unlock()
    }

    /// Artwork is only ever served from the cache the tag loader fills, so this
    /// never blocks whichever queue asks for it.
    func artwork(for track: Track) -> NSImage? {
        artworkLock.lock(); defer { artworkLock.unlock() }
        return artworkCache[track.id]
    }

    // MARK: Transport

    func play() {
        if let player {
            player.play()
        } else if !queue.isEmpty {
            start(at: index)
        }
    }

    func pause() { player?.pause() }

    func next() {
        guard !queue.isEmpty else { return }
        start(at: (index + 1) % queue.count)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        // Match the physical convention: restart the track before skipping back.
        if let player, player.currentTime > 3 {
            player.currentTime = 0
        } else {
            start(at: (index - 1 + queue.count) % queue.count)
        }
    }

    private var level: Double = 1

    func setVolume(_ level: Double) {
        self.level = min(max(level, 0), 1)
        player?.volume = Float(self.level)
    }

    func volume() -> Double? { level }

    func seek(to seconds: Double) {
        guard let player else { return }
        player.currentTime = min(max(0, seconds), player.duration)
    }

    private func start(at newIndex: Int) {
        guard queue.indices.contains(newIndex) else { return }
        index = newIndex
        let track = queue[newIndex]
        guard let url = track.fileURL else { return }
        player?.stop()
        guard let fresh = try? AVAudioPlayer(contentsOf: url) else {
            // Unreadable file — step over it rather than stalling the deck.
            if queue.count > 1 { next() }
            return
        }
        fresh.delegate = self
        fresh.volume = Float(level)
        fresh.prepareToPlay()
        fresh.play()
        player = fresh
        current = track
        loadTags(for: track, at: url)
    }

    /// Reads real title/artist/album/artwork tags a beat after playback starts.
    /// Playback never waits on this — the file name stands in until it lands.
    private func loadTags(for track: Track, at url: URL) {
        Task { [weak self] in
            let asset = AVURLAsset(url: url)
            guard let items = try? await asset.load(.commonMetadata) else { return }

            var title: String?, artist: String?, album: String?
            var image: NSImage?
            for item in items {
                guard let key = item.commonKey?.rawValue else { continue }
                switch key {
                case "title":     title  = try? await item.load(.stringValue)
                case "artist":    artist = try? await item.load(.stringValue)
                case "albumName": album  = try? await item.load(.stringValue)
                case "artwork":
                    if let data = try? await item.load(.dataValue) { image = NSImage(data: data) }
                default: break
                }
            }

            guard let self else { return }
            if let image { self.cache(image, for: track.id) }
            await MainActor.run {
                guard self.current?.id == track.id else { return }
                if let title, !title.isEmpty  { self.current?.title = title }
                if let artist, !artist.isEmpty { self.current?.artist = artist }
                if let album, !album.isEmpty   { self.current?.album = album }
                self.onNowPlayingChange?()
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        next()
    }

    // MARK: Library browsing

    func playlists() -> [Playlist] { folders }

    func tracks(in playlist: Playlist) -> [Track] { tracksByFolder[playlist.id] ?? [] }

    func play(track: Track, in playlist: Playlist?) {
        let list = playlist.flatMap { tracksByFolder[$0.id] } ?? tracksByFolder["local.all"] ?? []
        guard let position = list.firstIndex(where: { $0.id == track.id }) else { return }
        queue = list
        start(at: position)
    }
}
