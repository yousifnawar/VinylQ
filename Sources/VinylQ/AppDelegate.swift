import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let settings = Settings.shared
    let engine = PlayerEngine()
    let study = StudyTimer()
    let access = MusicAccess()

    private lazy var notch = NotchWindowController(engine: engine, settings: settings, study: study)
    private lazy var ambient = AmbientWindowController(engine: engine, settings: settings, study: study)
    private var bridge: WidgetBridge?

    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var terminationSignal: DispatchSourceSignal?

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // VinylQ is a dark room whatever the system is set to, so switches,
        // sliders and pickers should draw for a dark background too.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildMainMenu()
        quitCleanlyOnSIGTERM()

        notch.onOpenAmbient = { [weak self] in self?.ambient.show() }
        notch.onOpenApp = { [weak self] in self?.showMainWindow() }

        access.onConnect = { [weak self] _ in
            guard let self else { return }
            // Once a service is connected, follow it rather than the demo.
            if self.settings.pinnedSource == .demo { self.settings.pinnedSource = nil }
            self.engine.refreshLibrary()
        }
        // A bounced Apple Event means a permission was switched off.
        engine.$automationBlocked
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.access.refresh() }
            .store(in: &cancellables)

        // When Music or Spotify opens or quits, re-check it and pick up its
        // playlists without being asked.
        let hosts = Set(SourceKind.allCases.compactMap(\.hostBundleID))
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .compactMap { ($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier }
            .filter { hosts.contains($0) }
            // A freshly opened Music needs a moment before it answers.
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.access.refresh()
                self?.engine.refreshLibrary()
            }
            .store(in: &cancellables)

        engine.start()
        bridge = WidgetBridge(engine: engine, study: study, settings: settings)
        access.refresh()
        notch.show()
        installStatusItem()
        showMainWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridge?.writeFinalState()
    }

    /// `kill` (and the build script) send SIGTERM, which would otherwise end
    /// VinylQ on the spot. Treat it like ⌘Q so the widgets hear it closed.
    private func quitCleanlyOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }

    /// A widget app shouldn't quit just because its window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // MARK: vinylq:// links

    /// `vinylq://notch[/timer|/playlist]`, `vinylq://ambient`, `vinylq://timer`,
    /// `vinylq://command/<name>` (what widgets send when VinylQ wasn't running),
    /// `vinylq://sources`, `vinylq://widgets`, `vinylq://open`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "vinylq" || url.scheme == "wax" {
            let path = url.pathComponents.filter { $0 != "/" }
            switch url.host {
            case "notch":
                notch.reveal(NotchState.Tab(rawValue: path.first ?? "") ?? .player)
            case "timer":
                notch.reveal(.timer)
            case "ambient":
                ambient.show(openingStudy: path.first == "timer")
            case "command":
                if let name = path.first, let command = VinylQCommand(rawValue: name) {
                    bridge?.perform(command)
                }
            case "sources", "widgets", "study", "settings", "deck":
                showMainWindow(room: url.host)
            case "spotify-auth":
                break   // handled by the sign-in session
            default:
                showMainWindow()
            }
        }
    }

    // MARK: Main window

    func showMainWindow(room: String? = nil) {
        if mainWindow == nil {
            let root = MainView(
                engine: engine,
                settings: settings,
                study: study,
                access: access,
                bridge: bridge,
                onOpenAmbient: { [weak self] in self?.ambient.show() },
                onRevealNotch: { [weak self] tab in self?.notch.reveal(tab) }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "VinylQ"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor(Theme.ink)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: root)
            window.center()
            window.setFrameAutosaveName("wax.main")
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        if let room {
            let name = room.prefix(1).uppercased() + room.dropFirst()
            NotificationCenter.default.post(name: .vinylqShowRoom, object: String(name))
        }
    }

    // MARK: Menu bar extra

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "opticaldisc",
            accessibilityDescription: "VinylQ"
        )
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Notch Player", action: #selector(revealNotch), keyEquivalent: "")
        menu.addItem(withTitle: "Focus Timer", action: #selector(revealTimer), keyEquivalent: "")
        menu.addItem(withTitle: "View Playlist", action: #selector(revealPlaylist), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Full-Screen Deck", action: #selector(toggleAmbient), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open VinylQ", action: #selector(openApp), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit VinylQ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for menuItem in menu.items where menuItem.action != #selector(NSApplication.terminate(_:)) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    @objc private func revealNotch()    { notch.reveal(.player) }
    @objc private func revealTimer()    { notch.reveal(.timer) }
    @objc private func revealPlaylist() { notch.reveal(.playlist) }
    @objc private func toggleAmbient()  { ambient.toggle() }
    @objc private func openApp()        { showMainWindow() }

    // MARK: Main menu

    /// A minimal menu bar, so the standard shortcuts (⌘Q, ⌘W, ⌘,) behave.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About VinylQ", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let ambientItem = NSMenuItem(title: "Full-Screen Deck", action: #selector(toggleAmbient), keyEquivalent: "f")
        ambientItem.keyEquivalentModifierMask = [.command, .shift]
        ambientItem.target = self
        appMenu.addItem(ambientItem)
        let notchItem = NSMenuItem(title: "Show Notch Player", action: #selector(revealNotch), keyEquivalent: "n")
        notchItem.keyEquivalentModifierMask = [.command, .shift]
        notchItem.target = self
        appMenu.addItem(notchItem)
        let timerItem = NSMenuItem(title: "Focus Timer", action: #selector(revealTimer), keyEquivalent: "t")
        timerItem.keyEquivalentModifierMask = [.command, .shift]
        timerItem.target = self
        appMenu.addItem(timerItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide VinylQ", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit VinylQ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimise", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}
