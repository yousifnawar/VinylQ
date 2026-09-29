import AppKit
import Combine
import OSLog
import SwiftUI

/// A panel that is allowed to sit in the notch.
///
/// AppKit normally pushes a window down so it clears the menu bar, which for
/// this one lands it exactly one menu-bar height too low. Declining to be
/// constrained is what lets the pill occupy the notch itself.
private final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Owns the panel that lives in the notch, and decides when it opens.
///
/// Why it feels smooth: the window is created once at the size of the largest
/// thing it will ever show and never resized. Opening and closing is purely a
/// SwiftUI spring on one shape, so there's no window resize fighting the
/// animation mid-flight. The window is transparent to the mouse everywhere the
/// black shape isn't — `ignoresMouseEvents` follows the pointer — so it never
/// swallows a click meant for the menu bar or the app underneath.
///
/// Hover is tracked here rather than with SwiftUI's `onHover`, which misfires
/// while the thing being hovered is itself changing shape.
@MainActor
final class NotchWindowController {

    private let engine: PlayerEngine
    private let settings: Settings
    private let study: StudyTimer
    let state = NotchState()

    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private var pointerInside = false
    private var dragBeganInside = false
    /// Opened from a menu or a link: stays open until the pointer has been
    /// in and out, you click elsewhere, or a few seconds pass untouched.
    private var heldOpen = false

    var onOpenAmbient: () -> Void = {}
    var onOpenApp: () -> Void = {}

    /// A touch of overshoot on the way out of the notch, like the Dynamic
    /// Island; a firmer, quicker spring on the way back in.
    static let openSpring = Animation.spring(response: 0.44, dampingFraction: 0.78)
    static let closeSpring = Animation.spring(response: 0.36, dampingFraction: 0.94)
    static let tabSpring = Animation.spring(response: 0.38, dampingFraction: 0.86)

    init(engine: PlayerEngine, settings: Settings, study: StudyTimer) {
        self.engine = engine
        self.settings = settings
        self.study = study

        settings.$notchEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                Task { @MainActor in enabled ? self?.show() : self?.hide() }
            }
            .store(in: &cancellables)

        settings.$notchOnAllSpaces
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyCollectionBehavior() }
            }
            .store(in: &cancellables)

        // The pill carries the countdown while a block runs.
        Publishers.CombineLatest3(study.$phase, settings.$notchShowsTimer, study.$secondsLeft)
            .map { phase, shows, seconds in (shows && phase != .idle, seconds >= 3600) }
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] shows, hours in
                guard let self else { return }
                withAnimation(Self.openSpring) {
                    self.state.showsTimerInPill = shows
                    self.state.timerNeedsHours = hours
                }
            }
            .store(in: &cancellables)

        // A new song drops down from the notch for a moment.
        engine.$snapshot
            .map(\.track)
            .removeDuplicates { $0.id == $1.id }
            .sink { [weak self] track in
                // After the change has landed, so the peek shows the new title.
                DispatchQueue.main.async { self?.songChanged(to: track) }
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.measureScreen()
                    self?.placeWindow()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Presentation

    func show() {
        guard settings.notchEnabled else { return }
        if panel == nil { build() }
        measureScreen()
        placeWindow()
        panel?.orderFrontRegardless()
        startTracking()
    }

    func hide() {
        stopTracking()
        close()
        panel?.orderOut(nil)
    }

    /// Pops the panel open from anywhere else in the app. Asking for it counts
    /// as switching it on.
    func reveal(_ tab: NotchState.Tab = .player) {
        settings.notchEnabled = true
        show()
        heldOpen = true
        open(tab: tab)
        scheduleClose(after: 6)
    }

    func select(_ tab: NotchState.Tab) {
        guard tab != state.tab else { return }
        withAnimation(Self.tabSpring) { state.tab = tab }
        if tab == .playlist { engine.refreshLibrary() }
    }

    // MARK: New-song peek

    private let launchedAt = Date()
    private var peekWork: DispatchWorkItem?

    private func songChanged(to track: Track) {
        guard settings.notchPeekOnNewSong, panel?.isVisible == true,
              !state.isOpen, !track.isSilence, !track.id.hasPrefix("demo."),
              // Not for whatever happened to be playing when the app opened.
              Date().timeIntervalSince(launchedAt) > 4 else { return }
        peekWork?.cancel()
        withAnimation(Self.openSpring) { state.isPeeking = true }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state.isPeeking, !self.state.isOpen else { return }
            withAnimation(Self.closeSpring) { self.state.isPeeking = false }
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6, execute: work)
    }

    // MARK: Opening and closing

    private func open(tab: NotchState.Tab? = nil) {
        openWork?.cancel()
        closeWork?.cancel()
        closeWork = nil
        peekWork?.cancel()
        withAnimation(Self.openSpring) {
            if let tab { state.tab = tab }
            state.isPeeking = false
            state.isOpen = true
        }
        if state.tab == .playlist { engine.refreshLibrary() }
        startPolling()
        updateCapture()
    }

    func close() {
        openWork?.cancel()
        closeWork?.cancel()
        closeWork = nil
        heldOpen = false
        guard state.isOpen else { return }
        withAnimation(Self.closeSpring) { state.isOpen = false }
        // Next time, open where you were — unless that was the playlist,
        // which is a detour rather than a place.
        if state.tab == .playlist {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, !self.state.isOpen else { return }
                self.state.tab = .player
            }
        }
        stopPolling()
        updateCapture()
    }

    private func scheduleClose(after delay: TimeInterval) {
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Clear the slot first, so a later exit can schedule a fresh close.
            self.closeWork = nil
            guard !self.pointerInside else {
                // Still being looked at: from here on it behaves as if it
                // had been opened by hovering.
                self.heldOpen = false
                return
            }
            self.close()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Pointer

    private func startTracking() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .leftMouseDown, .rightMouseDown, .leftMouseUp
        ]
        let handle: (NSEvent) -> Void = { [weak self] event in
            let type = event.type
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.pointerEvent(type) }
            } else {
                DispatchQueue.main.async { self?.pointerEvent(type) }
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handle) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            handle(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    private func stopTracking() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        stopPolling()
    }

    /// While open, also glance at the pointer ten times a second — events
    /// over VinylQ's own windows reach neither monitor, and a missed exit would
    /// leave the panel hanging open.
    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerEvent(.mouseMoved) }
        }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pointerEvent(_ type: NSEvent.EventType) {
        guard panel?.isVisible == true else { return }
        let inside = hitRect().contains(NSEvent.mouseLocation)
        let buttonsDown = NSEvent.pressedMouseButtons != 0

        switch type {
        case .leftMouseDown, .rightMouseDown:
            dragBeganInside = inside
            // A click anywhere else dismisses it, like a popover.
            if !inside, state.isOpen { close() }
        case .leftMouseUp:
            dragBeganInside = false
            // A click on the pill opens it too, even if the click cut short
            // the hover's moment of intent.
            if inside, !state.isOpen { open() }
        default:
            break
        }

        if inside != pointerInside {
            pointerInside = inside
            if inside { pointerEntered(buttonsDown: buttonsDown) }
        }

        if !inside, state.isOpen, !heldOpen, !buttonsDown, closeWork == nil {
            scheduleClose(after: state.tab == .playlist ? 0.9 : 0.3)
        }
        updateCapture()
    }

    private func pointerEntered(buttonsDown: Bool) {
        closeWork?.cancel()
        closeWork = nil
        heldOpen = false
        guard !state.isOpen, !buttonsDown else { return }
        // A beat of intent, so sweeping past on the way to a menu doesn't
        // throw the panel open.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pointerInside, NSEvent.pressedMouseButtons == 0 else { return }
            self.open()
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: work)
    }

    /// Takes the mouse only where the shape is — or while a drag that began
    /// on it (the stylus) is still going.
    private func updateCapture() {
        guard let panel else { return }
        let capture = pointerInside || (dragBeganInside && NSEvent.pressedMouseButtons != 0)
        if panel.ignoresMouseEvents == capture {
            panel.ignoresMouseEvents = !capture
        }
    }

    /// The visible shape, in screen coordinates, with a little slack.
    private func hitRect() -> NSRect {
        guard let screen = targetScreen else { return .zero }
        let size = state.currentSize
        let top = topEdge(of: screen)
        let slack: CGFloat = state.isOpen ? 6 : 2
        return NSRect(
            x: screen.frame.midX - size.width / 2 - slack,
            y: top - size.height - slack,
            width: size.width + slack * 2,
            // Reach past the top edge so a pointer pinned there still counts.
            height: size.height + slack + 4
        )
    }

    // MARK: Building

    private func build() {
        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: state.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // Order matters: `isFloatingPanel` resets the level to .floating, which
        // is *below* the menu bar — the translucent bar then draws over the
        // pill's ears and turns them grey. The level has to be set last.
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let root = NotchView(
            engine: engine,
            state: state,
            settings: settings,
            study: study,
            onSelectTab: { [weak self] tab in self?.select(tab) },
            onOpenAmbient: { [weak self] in
                self?.close()
                self?.onOpenAmbient()
            },
            onOpenApp: { [weak self] in
                self?.close()
                self?.onOpenApp()
            }
        )
        let hosting = NSHostingView(rootView: root)
        // Never let SwiftUI resize the window: it stays one fixed canvas.
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: state.canvasSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        self.panel = panel
        applyCollectionBehavior()
    }

    private func applyCollectionBehavior() {
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .stationary]
        behavior.insert(settings.notchOnAllSpaces ? .canJoinAllSpaces : .moveToActiveSpace)
        panel?.collectionBehavior = behavior
    }

    // MARK: Geometry

    /// The screen we hang from: the one with a notch, else the main one.
    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func measureScreen() {
        guard let screen = targetScreen else { return }
        let inset = screen.safeAreaInsets.top
        guard inset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            state.notchWidth = 0
            state.notchHeight = 0
            return
        }
        state.notchWidth = max(0, screen.frame.width - left.width - right.width)
        state.notchHeight = inset
    }

    private func topEdge(of screen: NSScreen) -> CGFloat {
        guard !state.hasNotch else { return screen.frame.maxY }
        // Without a notch we hang just below the menu bar.
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        return screen.frame.maxY - (reserved > 0 ? reserved : NSStatusBar.system.thickness)
    }

    private func placeWindow() {
        guard let panel, let screen = targetScreen else { return }
        let canvas = state.canvasSize
        let top = topEdge(of: screen)
        panel.setFrame(
            NSRect(x: screen.frame.midX - canvas.width / 2, y: top - canvas.height,
                   width: canvas.width, height: canvas.height),
            display: true
        )
        Self.log.notice("""
            notch placed: frame=\(NSStringFromRect(panel.frame), privacy: .public) \
            level=\(panel.level.rawValue) notch=\(self.state.notchWidth)x\(self.state.notchHeight) \
            screen=\(NSStringFromRect(screen.frame), privacy: .public)
            """)
    }

    private static let log = Logger(subsystem: "app.wax.deck", category: "notch")
}
