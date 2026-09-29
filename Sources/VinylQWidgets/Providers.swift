import AppKit
import WidgetKit

/// One moment of VinylQ, as a widget sees it.
struct VinylQEntry: TimelineEntry {
    let date: Date
    let state: WidgetState
    let artwork: NSImage?
    let appRunning: Bool
}

/// Reads what VinylQ last wrote and checks it's still running.
enum VinylQSnapshotReader {

    static func current(at date: Date = Date()) -> VinylQEntry {
        guard let state = WidgetStore.load() else {
            // VinylQ has never run: show the demo record rather than a blank.
            let preview = WidgetState.preview(at: date)
            return VinylQEntry(date: date, state: preview, artwork: previewArtwork, appRunning: isAppRunning)
        }
        return VinylQEntry(
            date: date,
            state: state,
            artwork: WidgetStore.artwork(named: state.nowPlaying.artworkFile)
                ?? (state.nowPlaying.track.id.hasPrefix("demo.") ? DemoArt.sleeve(for: state.nowPlaying.track.id, side: 360) : nil),
            appRunning: state.appRunning && isAppRunning
        )
    }

    /// For the widget gallery: the real record if one's playing, else the demo.
    static func gallery(at date: Date = Date()) -> VinylQEntry {
        let entry = current(at: date)
        if entry.state.nowPlaying.track.isSilence {
            return VinylQEntry(date: date, state: .preview(at: date), artwork: previewArtwork, appRunning: true)
        }
        return entry
    }

    static var previewArtwork: NSImage { DemoArt.sleeve(for: "demo.1", side: 360) }

    /// A crashed VinylQ can't clear its own "running" flag, so ask the system.
    static var isAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "app.wax.deck").isEmpty
    }
}

struct NowPlayingProvider: TimelineProvider {

    func placeholder(in context: Context) -> VinylQEntry {
        VinylQEntry(date: Date(), state: .preview(), artwork: VinylQSnapshotReader.previewArtwork, appRunning: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (VinylQEntry) -> Void) {
        completion(context.isPreview ? VinylQSnapshotReader.gallery() : VinylQSnapshotReader.current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VinylQEntry>) -> Void) {
        let entry = VinylQSnapshotReader.current()
        // The bar and the clock count by themselves. We only need waking when
        // the song should have ended — by then VinylQ will have written the next.
        let policy: TimelineReloadPolicy
        if entry.appRunning, entry.state.nowPlaying.isPlaying, let end = entry.state.trackEnd, end > entry.date {
            policy = .after(end.addingTimeInterval(1.5))
        } else {
            policy = .never
        }
        completion(Timeline(entries: [entry], policy: policy))
    }
}

struct FocusProvider: TimelineProvider {

    func placeholder(in context: Context) -> VinylQEntry {
        VinylQEntry(date: Date(), state: .preview(), artwork: nil, appRunning: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (VinylQEntry) -> Void) {
        let entry = VinylQSnapshotReader.current()
        if context.isPreview, entry.state.focus.phase == .idle {
            completion(VinylQEntry(date: Date(), state: .preview(), artwork: nil, appRunning: true))
        } else {
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VinylQEntry>) -> Void) {
        let now = Date()
        let entry = VinylQSnapshotReader.current(at: now)
        let focus = entry.state.focus

        guard entry.appRunning, focus.isRunning, let end = focus.endDate, end > now else {
            completion(Timeline(entries: [entry], policy: .never))
            return
        }

        // The digits tick by themselves; the ring needs a fresh frame now and
        // then. Every 20 seconds is smooth enough for a 25-minute sweep.
        var entries: [VinylQEntry] = []
        var moment = now
        while moment < end, entries.count < 240 {
            entries.append(VinylQEntry(date: moment, state: entry.state, artwork: nil, appRunning: true))
            moment = moment.addingTimeInterval(20)
        }
        completion(Timeline(entries: entries, policy: .after(end.addingTimeInterval(1))))
    }
}
