import AppKit
import Combine
import WidgetKit

/// Keeps VinylQ's desktop widgets in step with the deck.
///
/// Outbound, it writes a `WidgetState` snapshot (plus a small copy of the
/// cover) to the folder the widgets may read, and asks WidgetKit to redraw —
/// only when something visible changed, and only the widgets that show it,
/// because macOS gives each widget a limited daily budget of redraws.
///
/// Inbound, it listens for the commands widget buttons send.
@MainActor
final class WidgetBridge: NSObject {

    private let engine: PlayerEngine
    private let study: StudyTimer
    private let settings: Settings

    private var cancellables = Set<AnyCancellable>()
    private var lastWritten: WidgetState?
    private var lastArtworkID: String?
    private var lastArtworkFile: String?
    private var pendingReload: Set<String> = []
    private var reloadWork: DispatchWorkItem?
    private var lastReload: Date = .distantPast
    private var installedKinds: Set<String>?
    private var installedCheckedAt: Date = .distantPast

    init(engine: PlayerEngine, study: StudyTimer, settings: Settings) {
        self.engine = engine
        self.study = study
        self.settings = settings
        super.init()

        // Coalesce bursts (a new track changes title, art and accent in quick
        // succession) into one write.
        engine.objectWillChange
            .merge(with: study.objectWillChange, settings.objectWillChange)
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)

        // Before the rename the widgets' folder was called Wax; it's only a
        // cache, so it can simply go.
        let oldFolder = WidgetStore.home.appendingPathComponent("Library/Application Support/Wax")
        try? FileManager.default.removeItem(at: oldFolder)

        for command in VinylQCommand.allCases {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(received(_:)), name: command.notificationName,
                object: nil, suspensionBehavior: .deliverImmediately
            )
        }
        sync()
    }

    // MARK: Commands

    @objc private func received(_ notification: Notification) {
        guard let command = VinylQCommand.allCases.first(where: { $0.notificationName == notification.name }) else { return }
        perform(command)
    }

    func perform(_ command: VinylQCommand) {
        Self.performDirectly(command, engine: engine, study: study)
        // Answer quickly: the widget redraws right after its button returns.
        sync(force: true)
    }

    static func performDirectly(_ command: VinylQCommand, engine: PlayerEngine, study: StudyTimer) {
        switch command {
        case .togglePlayback: engine.togglePlayPause()
        case .nextTrack:      engine.next()
        case .previousTrack:  engine.previous()
        case .toggleFocus:    study.start()
        case .skipFocus:      study.skip()
        case .resetFocus:     study.reset()
        }
    }

    // MARK: Writing

    func sync(force: Bool = false) {
        let state = makeState(appRunning: true)
        let kinds = changedKinds(from: lastWritten, to: state)
        guard force || !kinds.isEmpty else { return }
        WidgetStore.save(state)
        lastWritten = state
        scheduleReload(kinds.isEmpty ? Set(VinylQWidgetKind.all) : kinds)
    }

    /// Called as VinylQ quits, so widgets can offer to open it again.
    func writeFinalState() {
        WidgetStore.save(makeState(appRunning: false))
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func makeState(appRunning: Bool) -> WidgetState {
        WidgetState.live(engine: engine, study: study, settings: settings,
                         appRunning: appRunning, artworkFile: artworkFile())
    }

    /// Writes the cover once per track, small, and returns its file name.
    private func artworkFile() -> String? {
        guard engine.artworkID != lastArtworkID else { return lastArtworkFile }
        lastArtworkID = engine.artworkID

        let folder = WidgetStore.folder
        let files = FileManager.default
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        // Clear out earlier covers, including any a previous launch left.
        for name in (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
        where name.hasPrefix("cover-") {
            try? files.removeItem(at: folder.appendingPathComponent(name))
        }

        guard let image = engine.artwork,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let small = ArtworkProcessor.downsample(cg, maxSide: 360) else {
            lastArtworkFile = nil
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: small)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86]) else {
            lastArtworkFile = nil
            return nil
        }
        let name = "cover-\(DemoArt.stableHash(engine.artworkID) % 1_000_000_007).jpg"
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
        lastArtworkFile = name
        return name
    }

    /// Which widgets would look different — ignoring the needle's steady march,
    /// which they draw for themselves.
    private func changedKinds(from old: WidgetState?, to new: WidgetState) -> Set<String> {
        guard let old else { return Set(VinylQWidgetKind.all) }
        var kinds = Set<String>()

        let a = old.nowPlaying, b = new.nowPlaying
        let seeked = abs(old.trackStart.timeIntervalSince(new.trackStart)) > 2
            || (!b.isPlaying && abs(a.position - b.position) > 1)
        if a.track != b.track || a.isPlaying != b.isPlaying || a.artworkFile != b.artworkFile
            || a.accent != b.accent || seeked {
            kinds.insert(VinylQWidgetKind.nowPlaying)
        }

        let f = old.focus, g = new.focus
        let endMoved: Bool = {
            switch (f.endDate, g.endDate) {
            case let (x?, y?): return abs(x.timeIntervalSince(y)) > 1.5
            case (nil, nil):   return false
            default:           return true
            }
        }()
        if f.phase != g.phase || f.isRunning != g.isRunning || f.blocksDone != g.blocksDone || endMoved
            || f.focusMinutes != g.focusMinutes || f.breakMinutes != g.breakMinutes
            || f.longBreakMinutes != g.longBreakMinutes || f.blocksPerLongBreak != g.blocksPerLongBreak
            || (!g.isRunning && abs(f.remaining - g.remaining) > 1.5) {
            kinds.insert(VinylQWidgetKind.focus)
            // The large Now Playing widget shows the timer too.
            kinds.insert(VinylQWidgetKind.nowPlaying)
        }
        return kinds
    }

    // MARK: Reloading

    private func scheduleReload(_ kinds: Set<String>) {
        pendingReload.formUnion(kinds)
        reloadWork?.cancel()
        // At most one reload every couple of seconds; the last change wins.
        let wait = max(0.05, 2 - Date().timeIntervalSince(lastReload))
        let work = DispatchWorkItem { [weak self] in self?.flushReload() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    private func flushReload() {
        let kinds = pendingReload
        pendingReload = []
        lastReload = Date()
        refreshInstalledKinds()
        // Don't spend the budget on widgets nobody has placed.
        let targets = installedKinds.map { kinds.intersection($0) } ?? kinds
        for kind in targets {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    private func refreshInstalledKinds() {
        guard Date().timeIntervalSince(installedCheckedAt) > 60 else { return }
        installedCheckedAt = Date()
        WidgetCenter.shared.getCurrentConfigurations { [weak self] result in
            let kinds = (try? result.get()).map { Set($0.map(\.kind)) }
            Task { @MainActor in self?.installedKinds = kinds }
        }
    }

    /// For the Widgets room: how many VinylQ widgets are on the desktop.
    func countInstalled(_ completion: @escaping (Int?) -> Void) {
        WidgetCenter.shared.getCurrentConfigurations { result in
            let count = (try? result.get())?.filter { VinylQWidgetKind.all.contains($0.kind) }.count
            Task { @MainActor in completion(count) }
        }
    }

    func reloadAll() {
        installedCheckedAt = .distantPast
        sync(force: true)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
