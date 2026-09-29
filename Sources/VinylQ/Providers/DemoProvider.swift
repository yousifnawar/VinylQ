import AppKit
import Foundation

/// A record that spins with nothing connected.
///
/// It exists so a first launch looks like a record player rather than an
/// error message. Main-queue confined, like the other in-process provider.
final class DemoProvider: MusicProvider, @unchecked Sendable {

    let kind: SourceKind = .demo
    var isAvailable: Bool { true }

    private let side: [Track] = [
        Track(id: "demo.1", title: "Golden Hour",   artist: "The Warm Static",
              album: "Sunset Sessions", duration: 214),
        Track(id: "demo.2", title: "Paper Lantern", artist: "Marguerite Bay",
              album: "Sunset Sessions", duration: 187),
        Track(id: "demo.3", title: "Long Way Down", artist: "Cassette Club",
              album: "Sunset Sessions", duration: 245)
    ]

    private var index = 0
    private var playing = true
    private var offset: Double = 0
    private var startedAt = Date()

    private var elapsed: Double {
        playing ? offset + Date().timeIntervalSince(startedAt) : offset
    }

    func snapshot() -> PlaybackSnapshot? {
        var position = elapsed
        let track = side[index]
        if position >= track.duration {
            // Loop the side so the demo never runs out.
            position = 0
            offset = 0
            startedAt = Date()
            index = (index + 1) % side.count
        }
        return PlaybackSnapshot(
            track: side[index], isPlaying: playing,
            position: position, source: .demo, contextID: "demo.side-a"
        )
    }

    /// A generated sleeve, so the demo has real cover art on the platter.
    func artwork(for track: Track) -> NSImage? {
        DemoArt.sleeve(for: track.id)
    }

    func play()  { if !playing { startedAt = Date(); playing = true } }
    func pause() { if playing { offset = elapsed; playing = false } }

    func next() {
        index = (index + 1) % side.count
        offset = 0; startedAt = Date()
    }

    func previous() {
        index = (index - 1 + side.count) % side.count
        offset = 0; startedAt = Date()
    }

    func seek(to seconds: Double) {
        offset = max(0, min(seconds, side[index].duration))
        startedAt = Date()
    }

    func playlists() -> [Playlist] {
        [Playlist(id: "demo.side-a", name: "Side A", source: .demo,
                  trackCount: side.count, tracks: side)]
    }

    func tracks(in playlist: Playlist) -> [Track] { side }

    func play(track: Track, in playlist: Playlist?) {
        guard let position = side.firstIndex(where: { $0.id == track.id }) else { return }
        index = position
        offset = 0; startedAt = Date(); playing = true
    }
}
