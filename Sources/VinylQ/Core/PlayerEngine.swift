import AppKit
import Combine
import SwiftUI

/// The single source of truth every surface reads from — the notch, the
/// ambient deck, the app and the widgets all bind to this object, so the
/// record is in the same place everywhere.
///
/// It publishes only when something you'd *see* changes: a new track, play
/// or pause, a seek. The needle creeping forward is not a change — views
/// extrapolate it from an anchor (`position(at:)`) inside their own animation
/// timelines — so the whole app doesn't re-render twice a second.
@MainActor
final class PlayerEngine: ObservableObject {

    // MARK: Published state

    @Published private(set) var snapshot: PlaybackSnapshot = .idle(.demo)
    @Published private(set) var artwork: NSImage?
    /// Tiny, pre-blurred cover for full-screen backdrops.
    @Published private(set) var backdrop: NSImage?
    /// Changes whenever the artwork does, so views can cross-fade on it.
    @Published private(set) var artworkID: String = "none"
    /// Pulled from the artwork so the deck picks up the record's colour.
    @Published private(set) var accent: Color = Theme.brass
    @Published private(set) var accentRGB: WidgetState.RGB = .brass
    @Published private(set) var activeKind: SourceKind = .demo

    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var openPlaylist: Playlist?
    @Published private(set) var openTracks: [Track] = []
    @Published private(set) var isLoadingTracks = false

    /// Non-nil while the stylus is being dragged: progress in `0...1`.
    @Published var scrubProgress: Double?

    /// Set when macOS has refused Apple Events, so the UI can say so.
    @Published private(set) var automationBlocked = false

    // MARK: Providers

    let local = LocalProvider()
    let demo = DemoProvider()
    let appleMusic = AppleMusicProvider()
    let spotifyCache = SpotifyCache()
    let spotify: SpotifyProvider
    let spotifyLibrary: SpotifyLibrary
    let spotifyWeb: SpotifyWebAPI

    private let settings = Settings.shared
    private var timer: Timer?
    private var ticks = 0
    private var remoteCache: [SourceKind: PlaybackSnapshot] = [:]
    private var appleMusicPlaylists: [Playlist] = []
    private static let hiddenDefaultsKey = "playlists.hidden"
    private var hiddenPlaylists: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: PlayerEngine.hiddenDefaultsKey) ?? [])
    private var artworkToken: String?
    private var lastRecordedSpotifyID: String?

    /// Where the needle was at `anchorDate`. Views extrapolate from here.
    private var anchorPosition: Double = 0
    private var anchorDate = Date()

    /// Priority when nothing is pinned and nothing is playing.
    private let order: [SourceKind] = [.spotify, .appleMusic, .local]

    init() {
        spotify = SpotifyProvider(cache: spotifyCache)
        spotifyLibrary = SpotifyLibrary(cache: spotifyCache)
        spotifyWeb = SpotifyWebAPI(cache: spotifyCache)
        local.onLibraryChange = { [weak self] in self?.rebuildPlaylists() }
        local.onNowPlayingChange = { [weak self] in self?.reloadArtwork() }
        spotifyLibrary.onChange = { [weak self] in self?.rebuildPlaylists() }
        spotifyWeb.onLibraryChange = { [weak self] in self?.rebuildPlaylists() }
    }

    var isPlaying: Bool { snapshot.isPlaying }

    // MARK: Lifecycle

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        // .common keeps the needle moving while a menu or a drag is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
        refreshLibrary()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Polling

    private func tick() {
        ticks += 1
        // Apple Events are comparatively expensive: once a second is plenty,
        // and we interpolate the needle position in between.
        if ticks % 2 == 0 { pollRemote() }
        resolve()
    }

    private func pollRemote() {
        let spotify = self.spotify
        let appleMusic = self.appleMusic
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let results: [(SourceKind, PlaybackSnapshot?)] = [
                (.spotify, spotify.snapshot()),
                (.appleMusic, appleMusic.snapshot())
            ]
            let blocked = AppleScriptRunner.shared.authorizationMessage != nil
            Task { @MainActor in self?.applyRemote(results, blocked: blocked) }
        }
    }

    private func applyRemote(_ results: [(SourceKind, PlaybackSnapshot?)], blocked: Bool) {
        for (kind, snapshot) in results {
            if let snapshot { remoteCache[kind] = snapshot }
            else { remoteCache.removeValue(forKey: kind) }
        }
        if automationBlocked != blocked { automationBlocked = blocked }
    }

    /// Chooses which source owns the deck right now and publishes its state.
    private func resolve() {
        var candidates = remoteCache
        if let snapshot = local.snapshot(), !snapshot.track.isSilence {
            candidates[.local] = snapshot
        }
        // The demo only competes for the deck when it's explicitly pinned;
        // otherwise it's the last resort below.
        if settings.pinnedSource == .demo, let snapshot = demo.snapshot() {
            candidates[.demo] = snapshot
        }

        let chosen: PlaybackSnapshot
        if let pinned = settings.pinnedSource, let snapshot = candidates[pinned] {
            chosen = snapshot
        } else if let playing = order.compactMap({ candidates[$0] }).first(where: { $0.isPlaying }) {
            chosen = playing
        } else if let held = candidates[activeKind] {
            chosen = held
        } else if let any = order.compactMap({ candidates[$0] }).first {
            chosen = any
        } else if let fallback = demo.snapshot() {
            chosen = fallback
        } else {
            chosen = .idle(.demo)
        }

        let now = Date()
        let visible = chosen.differsVisibly(from: snapshot)
        let drift = abs(chosen.position - position(at: now))
        // A playing needle that's within a beat of where we'd have put it is
        // left alone — re-anchoring on every poll makes the label twitch.
        let jumped = chosen.isPlaying ? drift > 0.75 : drift > 0.05

        if chosen.track.id != snapshot.track.id { loadArtwork(for: chosen) }
        if chosen.source == .spotify, chosen.track.id != lastRecordedSpotifyID, !chosen.track.isSilence {
            lastRecordedSpotifyID = chosen.track.id
            spotifyLibrary.record(chosen.track)
        }
        if chosen.source != activeKind { activeKind = chosen.source }

        if visible || jumped {
            anchorPosition = chosen.position
            anchorDate = now
            snapshot = chosen
        }
    }

    /// Moves the anchor without waiting for the next poll.
    private func rebase(to seconds: Double) {
        anchorPosition = seconds
        anchorDate = Date()
        snapshot.position = seconds
    }

    // MARK: Interpolated position

    /// Position in seconds at `date`, smoothed between polls.
    func position(at date: Date) -> Double {
        if let scrubProgress { return scrubProgress * snapshot.track.duration }
        guard snapshot.isPlaying else { return anchorPosition }
        let extrapolated = anchorPosition + date.timeIntervalSince(anchorDate)
        guard snapshot.track.duration > 0 else { return extrapolated }
        return min(extrapolated, snapshot.track.duration)
    }

    /// Progress in `0...1` at `date`.
    func progress(at date: Date) -> Double {
        if let scrubProgress { return scrubProgress }
        guard snapshot.track.duration > 0 else { return 0 }
        return min(max(position(at: date) / snapshot.track.duration, 0), 1)
    }

    /// How far the platter has turned, in degrees — tied to the music, so a
    /// seek moves the record exactly as far as it moves the needle.
    func platterAngle(at date: Date) -> Double {
        (position(at: date) * (settings.rpm / 60) * 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: Transport

    var activeProvider: MusicProvider { provider(for: activeKind) }

    private func provider(for kind: SourceKind) -> MusicProvider {
        switch kind {
        case .local:      return local
        case .demo:       return demo
        case .spotify:    return spotify
        case .appleMusic: return appleMusic
        }
    }

    func togglePlayPause() {
        let provider = activeProvider
        let now = Date()
        if snapshot.isPlaying {
            provider.pause()
            anchorPosition = position(at: now)
        } else {
            provider.play()
        }
        anchorDate = now
        // Optimistic: the UI shouldn't wait a poll to acknowledge a click.
        snapshot.isPlaying.toggle()
        snapshot.position = anchorPosition
    }

    func next() {
        activeProvider.next()
        rebase(to: 0)
    }

    func previous() {
        activeProvider.previous()
        rebase(to: 0)
    }

    // MARK: Scrubbing (the stylus)

    func beginScrub(at progress: Double) {
        scrubProgress = min(max(progress, 0), 1)
    }

    func updateScrub(to progress: Double) {
        scrubProgress = min(max(progress, 0), 1)
    }

    func endScrub() {
        guard let target = scrubProgress else { return }
        scrubProgress = nil
        guard snapshot.track.duration > 0 else { return }
        let seconds = target * snapshot.track.duration
        activeProvider.seek(to: seconds)
        rebase(to: seconds)
    }

    func seek(toProgress progress: Double) {
        guard snapshot.track.duration > 0 else { return }
        let seconds = min(max(progress, 0), 1) * snapshot.track.duration
        activeProvider.seek(to: seconds)
        rebase(to: seconds)
    }

    // MARK: Library

    /// Re-reads every source's playlists. Music.app's come over Apple Events,
    /// so they're fetched in the background; until they arrive the last ones
    /// stay on screen, so the browser never blinks empty.
    func refreshLibrary() {
        rebuildPlaylists()

        let appleMusic = self.appleMusic
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let lists = appleMusic.playlists()
            Task { @MainActor in
                self?.appleMusicPlaylists = lists
                self?.rebuildPlaylists()
            }
        }
        if spotifyWeb.isConnected {
            // Rebuilds through `onLibraryChange` when it lands.
            Task { await spotifyWeb.loadLibrary() }
        }
    }

    /// Recomposes the list from what's already known — no Apple Events, so
    /// it's cheap enough to run whenever Spotify moves on to a new song.
    func rebuildPlaylists() {
        let fresh = (local.playlists() + demo.playlists() + appleMusicPlaylists + spotify.playlists())
            .filter { !hiddenPlaylists.contains(Self.hiddenKey(for: $0)) }
        if fresh != playlists { playlists = fresh }
    }

    // MARK: Removing playlists

    enum Removal {
        /// Deleted from Music.app itself (songs stay in the library).
        case deleteFromMusic
        /// A Spotify link you added — forgotten by VinylQ.
        case removeLink
        /// Hidden in VinylQ; nothing on disk or in the service changes.
        case hide
        case none
    }

    func removal(for playlist: Playlist) -> Removal {
        switch playlist.source {
        case .appleMusic: return .deleteFromMusic
        case .spotify:
            if playlist.isCollection { return .removeLink }
            return playlist.id == SpotifyProvider.recentID ? .none : .hide
        case .local:
            return playlist.id == "local.all" ? .none : .hide
        case .demo: return .hide
        }
    }

    private static func hiddenKey(for playlist: Playlist) -> String {
        "\(playlist.source.rawValue)|\(playlist.id)"
    }

    /// Removes a playlist the way its source allows. Returns false if Music.app refused.
    @discardableResult
    func remove(_ playlist: Playlist) async -> Bool {
        if openPlaylist?.id == playlist.id { closePlaylist() }
        switch removal(for: playlist) {
        case .none:
            return false
        case .removeLink:
            if let saved = spotifyLibrary.saved.first(where: { $0.uri == playlist.id }) {
                spotifyLibrary.remove(saved)
            }
            return true
        case .hide:
            hiddenPlaylists.insert(Self.hiddenKey(for: playlist))
            UserDefaults.standard.set(Array(hiddenPlaylists), forKey: Self.hiddenDefaultsKey)
            rebuildPlaylists()
            return true
        case .deleteFromMusic:
            let music = appleMusic
            let ok = await Task.detached(priority: .userInitiated) {
                music.deletePlaylist(id: playlist.id)
            }.value
            if ok {
                appleMusicPlaylists.removeAll { $0.id == playlist.id }
                rebuildPlaylists()
            }
            return ok
        }
    }

    var hiddenPlaylistCount: Int { hiddenPlaylists.count }

    func restoreHiddenPlaylists() {
        hiddenPlaylists = []
        UserDefaults.standard.removeObject(forKey: Self.hiddenDefaultsKey)
        rebuildPlaylists()
    }

    func open(_ playlist: Playlist) {
        if playlist.isCollection {
            play(collection: playlist)
            return
        }
        openPlaylist = playlist
        openTracks = []
        isLoadingTracks = true

        switch playlist.source {
        case .local:
            openTracks = local.tracks(in: playlist)
            isLoadingTracks = false
        case .demo:
            openTracks = demo.tracks(in: playlist)
            isLoadingTracks = false
        case .appleMusic:
            let provider = appleMusic
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let tracks = provider.tracks(in: playlist)
                Task { @MainActor in self?.receive(tracks, for: playlist) }
            }
        case .spotify:
            if playlist.id == SpotifyProvider.recentID {
                openTracks = spotify.tracks(in: playlist)
                isLoadingTracks = false
                return
            }
            Task { [weak self] in
                guard let self else { return }
                await spotifyWeb.loadTracks(for: playlist.id)
                guard openPlaylist?.id == playlist.id else { return }
                openTracks = spotifyWeb.cachedTracks(for: playlist.id)
                isLoadingTracks = false
            }
        }
    }

    private func receive(_ tracks: [Track], for playlist: Playlist) {
        guard openPlaylist?.id == playlist.id else { return }
        openTracks = tracks
        isLoadingTracks = false
    }

    func closePlaylist() {
        openPlaylist = nil
        openTracks = []
    }

    func play(_ track: Track, in playlist: Playlist?) {
        let provider = self.provider(for: playlist?.source ?? activeKind)
        provider.play(track: track, in: playlist)
        activeKind = provider.kind
        anchorPosition = 0
        anchorDate = Date()
        snapshot = PlaybackSnapshot(track: track, isPlaying: true, position: 0,
                                    source: provider.kind, contextID: playlist?.id)
        loadArtwork(for: snapshot)
    }

    /// Plays a Spotify playlist, album or artist you added by link.
    func play(collection: Playlist) {
        guard collection.source == .spotify else { return }
        spotify.playCollection(uri: collection.id)
        // Follow Spotify, whatever was pinned, since that's where the music went.
        if settings.pinnedSource != nil && settings.pinnedSource != .spotify { settings.pinnedSource = nil }
    }

    // MARK: Artwork

    /// Re-asks the active provider for artwork — used when tags arrive late.
    func reloadArtwork() {
        artworkToken = nil
        loadArtwork(for: snapshot)
    }

    private func loadArtwork(for snapshot: PlaybackSnapshot) {
        let token = snapshot.track.id
        artworkToken = token
        guard !snapshot.track.isSilence else {
            apply(nil, token: token)
            return
        }
        let provider = self.provider(for: snapshot.source)
        let track = snapshot.track

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let processed = provider.artwork(for: track).flatMap { ArtworkProcessor.process($0, id: token) }
            Task { @MainActor in self?.apply(processed, token: token) }
        }
    }

    private func apply(_ set: ArtworkSet?, token: String) {
        guard artworkToken == token else { return }
        let tint = set?.tint
        let useTint = tint != nil && settings.tintFromArtwork
        withAnimation(.easeInOut(duration: 0.7)) {
            artwork = set?.image
            backdrop = set?.backdrop
            artworkID = set.map { "\($0.id)" } ?? "none"
            accent = useTint ? Color(nsColor: tint!) : Theme.brass
        }
        if useTint, let rgb = tint?.usingColorSpace(.sRGB) {
            accentRGB = WidgetState.RGB(red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
                                        blue: Double(rgb.blueComponent))
        } else {
            accentRGB = .brass
        }
    }
}
