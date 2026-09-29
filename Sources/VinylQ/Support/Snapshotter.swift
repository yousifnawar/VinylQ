import AppKit
import SwiftUI
import WidgetKit

/// Renders every surface to a PNG, offscreen.
///
/// Run with `build/VinylQ.app/Contents/MacOS/VinylQ --render <dir>`. It pins the
/// demo record so the output is the same every time, then puts the pin back
/// where it found it.
@MainActor
enum Snapshotter {

    static func run(outputDirectory: URL) -> Never {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let settings = Settings.shared
        let previousPin = settings.pinnedSourceRaw
        settings.pinnedSource = .demo

        let engine = PlayerEngine()
        let study = StudyTimer()
        let access = MusicAccess()
        engine.start()
        access.refresh()

        // Let the demo record start turning and its sleeve resolve.
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        func app(_ room: MainView.Room) -> some View {
            MainView(
                engine: engine, settings: settings, study: study, access: access, bridge: nil,
                onOpenAmbient: {}, onRevealNotch: { _ in }, initialRoom: room
            )
        }

        let window = CGSize(width: 1180, height: 820)
        write(app(.deck),     "01-deck",     window, to: outputDirectory)
        write(app(.widgets),  "02-widgets",  CGSize(width: 1180, height: 1180), to: outputDirectory)
        write(app(.sources),  "03-sources",  CGSize(width: 1180, height: 1000), to: outputDirectory)
        write(app(.study),    "04-study",    CGSize(width: 1180, height: 860), to: outputDirectory)
        write(app(.settings), "05-settings", CGSize(width: 1180, height: 1120), to: outputDirectory)

        // The notch, over a stand-in menu bar with a stand-in notch, so the
        // pictures show how the pill meets the hardware.
        let notchState = NotchState()
        notchState.notchWidth = 200
        notchState.notchHeight = 34

        func notch(open: Bool, tab: NotchState.Tab = .player, timer: Bool = false, peek: Bool = false,
                   height: CGFloat) -> some View {
            notchState.isOpen = open
            notchState.tab = tab
            notchState.showsTimerInPill = timer
            notchState.isPeeking = peek
            let canvas = notchState.canvasSize
            return ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: 0x5B6B82), Color(hex: 0x2E3444), Color(hex: 0x1B1D26)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle()
                    .fill(Color(hex: 0x3B4456).opacity(0.92))
                    .frame(height: notchState.notchHeight)
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
                    .fill(Color.black)
                    .frame(width: notchState.notchWidth, height: notchState.notchHeight)
                NotchView(
                    engine: engine, state: notchState, settings: settings, study: study,
                    onSelectTab: { _ in }, onOpenAmbient: {}, onOpenApp: {}
                )
                .frame(width: canvas.width, height: canvas.height)
            }
            .frame(width: canvas.width, height: height, alignment: .top)
            .clipped()
        }

        let canvas = notchState.canvasSize
        write(notch(open: false, height: 90), "06-notch-pill", CGSize(width: canvas.width, height: 90), to: outputDirectory)
        write(notch(open: false, peek: true, height: 110), "06c-notch-new-song", CGSize(width: canvas.width, height: 110), to: outputDirectory)
        write(notch(open: true, height: 250), "07-notch-player", CGSize(width: canvas.width, height: 250), to: outputDirectory)
        write(notch(open: true, tab: .playlist, height: canvas.height), "08-notch-playlist", canvas, to: outputDirectory)

        // With a focus block running.
        study.start()
        quietTimer = study
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        write(notch(open: false, timer: true, height: 90), "06b-notch-pill-timer", CGSize(width: canvas.width, height: 90), to: outputDirectory)
        write(notch(open: true, tab: .timer, timer: true, height: 250), "07b-notch-timer", CGSize(width: canvas.width, height: 250), to: outputDirectory)

        write(
            AmbientView(engine: engine, settings: settings, study: study,
                        startWithStudy: false, onClose: {}),
            "09-ambient", CGSize(width: 1440, height: 900), to: outputDirectory
        )
        write(
            AmbientView(engine: engine, settings: settings, study: study,
                        startWithStudy: true, onClose: {}),
            "10-ambient-timer-settings", CGSize(width: 1440, height: 900), to: outputDirectory
        )
        write(app(.widgets), "11-widgets-with-timer", CGSize(width: 1180, height: 1180), to: outputDirectory)
        study.reset()

        settings.pinnedSourceRaw = previousPin
        print("wrote snapshots to \(outputDirectory.path)")
        exit(0)
    }

    /// Hosts the view in a real (off-screen) window and captures its backing
    /// store. `ImageRenderer` would be simpler, but it lays `ScrollView` out at
    /// zero height — so it would photograph a window VinylQ never actually shows.
    /// Set while a focus block runs, so captures can dodge its ticks.
    private static var quietTimer: StudyTimer?

    private static func write<V: View>(_ view: V, _ name: String, _ size: CGSize, to directory: URL) {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -30_000, y: -30_000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.orderFront(nil)

        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        // A running timer rolls its digits every second; wait for a still
        // moment between ticks so no picture catches a digit mid-roll.
        if let end = quietTimer?.endDate {
            let untilTick = end.timeIntervalSinceNow.truncatingRemainder(dividingBy: 1)
            let sinceTick = 1 - untilTick
            if untilTick < 0.3 {
                RunLoop.main.run(until: Date().addingTimeInterval(untilTick + 0.4))
            } else if sinceTick < 0.4 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.4 - sinceTick))
            }
        }

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            print("could not render \(name)")
            window.orderOut(nil)
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("could not encode \(name)")
            return
        }
        let url = directory.appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("· \(url.lastPathComponent)")
    }
}
