import AppKit
import Combine
import CoreServices
import Foundation

/// Connecting Apple Music and Spotify — which, for VinylQ, means one click.
///
/// Neither service needs a password or a key here. VinylQ drives the Music and
/// Spotify apps you're already signed into, so "connecting" is two things:
/// the app being there, and macOS's one-time "VinylQ wants to control Spotify"
/// permission. `connect(_:)` does both — opens the app if it's closed, then
/// asks macOS — and remembers the answer so the Sources room can show it.
@MainActor
final class MusicAccess: ObservableObject {

    enum Status: Equatable {
        /// We haven't looked yet.
        case unknown
        case notInstalled
        /// Installed, never connected.
        case available
        /// Waiting on the app to open, or on the permission prompt.
        case connecting
        case connected
        /// Permission was refused in System Settings.
        case denied
    }

    @Published private(set) var appleMusic: Status = .unknown
    @Published private(set) var spotify: Status = .unknown

    /// Called after a service connects, so the library can fill in.
    var onConnect: (SourceKind) -> Void = { _ in }

    private let runner = AppleScriptRunner.shared

    func status(for kind: SourceKind) -> Status {
        switch kind {
        case .appleMusic: return appleMusic
        case .spotify:    return spotify
        case .local, .demo: return .connected
        }
    }

    func isRunning(_ kind: SourceKind) -> Bool {
        guard let id = kind.hostBundleID else { return true }
        return runner.isRunning(bundleID: id)
    }

    // MARK: Checking

    /// Re-reads both services without prompting.
    func refresh() {
        for kind in [SourceKind.appleMusic, .spotify] {
            guard let bundleID = kind.hostBundleID else { continue }
            if status(for: kind) == .connecting { continue }
            guard runner.isInstalled(bundleID: bundleID) else {
                set(kind, .notInstalled)
                continue
            }
            // Asking macOS needs the app running; otherwise go on what we
            // last heard.
            guard runner.isRunning(bundleID: bundleID) else {
                set(kind, Self.remembered(bundleID) ?? .available)
                continue
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let code = Self.permission(for: bundleID, ask: false)
                Task { @MainActor in self?.receive(code, for: kind, asked: false) }
            }
        }
    }

    /// Marks a service blocked when an Apple Event bounces for permission.
    func noteBlocked(_ kind: SourceKind) {
        guard let bundleID = kind.hostBundleID else { return }
        Self.remember(.denied, bundleID)
        set(kind, .denied)
    }

    // MARK: Connecting

    /// Opens the app if needed and asks macOS for permission to control it.
    func connect(_ kind: SourceKind) {
        guard let bundleID = kind.hostBundleID else { return }
        guard runner.isInstalled(bundleID: bundleID) else {
            set(kind, .notInstalled)
            if kind == .spotify, let url = URL(string: "https://www.spotify.com/download/mac/") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        if status(for: kind) == .denied {
            openAutomationSettings()
            return
        }

        set(kind, .connecting)
        let runner = self.runner
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if !runner.isRunning(bundleID: bundleID) {
                runner.launch(bundleID: bundleID)
                runner.waitUntilRunning(bundleID: bundleID, timeout: 20)
                // A freshly opened app needs a moment before it takes events.
                Thread.sleep(forTimeInterval: 1.2)
            }
            // Blocks while macOS shows its prompt, which is why we're off main.
            let code = Self.permission(for: bundleID, ask: true)
            Task { @MainActor in self?.receive(code, for: kind, asked: true) }
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Results

    private func receive(_ code: OSStatus, for kind: SourceKind, asked: Bool) {
        guard let bundleID = kind.hostBundleID else { return }
        switch code {
        case 0:
            Self.remember(.connected, bundleID)
            let wasConnected = status(for: kind) == .connected
            set(kind, .connected)
            if asked || !wasConnected { onConnect(kind) }
        case -1743:   // errAEEventNotPermitted
            Self.remember(.denied, bundleID)
            set(kind, .denied)
        case -1744:   // errAEEventWouldRequireUserConsent — never asked yet
            set(kind, .available)
        default:      // not running any more, or no answer
            set(kind, Self.remembered(bundleID) ?? .available)
        }
    }

    private func set(_ kind: SourceKind, _ status: Status) {
        switch kind {
        case .appleMusic: if appleMusic != status { appleMusic = status }
        case .spotify:    if spotify != status { spotify = status }
        case .local, .demo: break
        }
    }

    // MARK: macOS

    /// `noErr` when allowed, -1743 when refused, -1744 when macOS would have
    /// to ask, -600 when the app isn't running.
    nonisolated private static func permission(for bundleID: String, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let descriptor = target.aeDesc else { return -600 }
        return AEDeterminePermissionToAutomateTarget(
            descriptor, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask
        )
    }

    private static func key(_ bundleID: String) -> String { "access.\(bundleID)" }

    private static func remember(_ status: Status, _ bundleID: String) {
        UserDefaults.standard.set(status == .connected ? "granted" : "denied", forKey: key(bundleID))
    }

    private static func remembered(_ bundleID: String) -> Status? {
        switch UserDefaults.standard.string(forKey: key(bundleID)) {
        case "granted": return .connected
        case "denied":  return .denied
        default:        return nil
        }
    }
}
