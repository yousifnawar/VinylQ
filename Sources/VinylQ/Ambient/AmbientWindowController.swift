import AppKit
import SwiftUI

/// Owns the borderless window that turns the display into a record deck.
@MainActor
final class AmbientWindowController {

    private let engine: PlayerEngine
    private let settings: Settings
    private let study: StudyTimer

    private var window: NSWindow?
    private var savedPresentationOptions: NSApplication.PresentationOptions?

    init(engine: PlayerEngine, settings: Settings, study: StudyTimer) {
        self.engine = engine
        self.settings = settings
        self.study = study
    }

    var isVisible: Bool { window?.isVisible == true }

    func toggle() { isVisible ? close() : show() }

    func show(openingStudy: Bool = false) {
        if window == nil { build() }
        guard let window else { return }

        let wasVisible = window.isVisible
        if let screen = NSScreen.main {
            window.setFrame(screen.frame, display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible { window.alphaValue = 0 }
        window.makeKeyAndOrderFront(nil)

        // Give the deck the whole screen, menu bar and Dock included.
        if savedPresentationOptions == nil {
            savedPresentationOptions = NSApp.presentationOptions
        }
        NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]

        if !wasVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        }

        if openingStudy { NotificationCenter.default.post(name: .vinylqOpenStudy, object: nil) }
    }

    func close() {
        if let saved = savedPresentationOptions {
            NSApp.presentationOptions = saved
            savedPresentationOptions = nil
        } else {
            NSApp.presentationOptions = []
        }
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                window.orderOut(nil)
                window.alphaValue = 1
            }
        })
    }

    private func build() {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = NSColor(Theme.ink)
        window.level = .normal
        window.collectionBehavior = [.fullScreenAuxiliary, .stationary]
        window.isMovable = false
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false

        let root = AmbientView(
            engine: engine,
            settings: settings,
            study: study,
            onClose: { [weak self] in self?.close() }
        )
        window.contentView = NSHostingView(rootView: root)
        self.window = window
    }
}

extension Notification.Name {
    static let vinylqOpenStudy = Notification.Name("vinylq.openStudy")
}
