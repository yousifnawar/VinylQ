import AppKit
import Foundation
import OSLog

/// Thin, cached wrapper around `NSAppleScript`.
///
/// Two rules keep this cheap enough to poll every second:
/// 1. Scripts are compiled once and reused.
/// 2. Polling never sends an event to an app that isn't already running —
///    asking `tell application "Spotify"` anything at all is enough to
///    *launch* Spotify, which is the last thing a now-playing widget should
///    do. Only an explicit "play this" (`commandLaunching`) may open it.
final class AppleScriptRunner: @unchecked Sendable {

    static let shared = AppleScriptRunner()

    /// Field separator: a control character no track title will contain.
    static let sep = "\u{1}"

    /// Set when macOS refuses automation, so the UI can explain itself
    /// instead of silently showing an empty turntable.
    private(set) var authorizationMessage: String?

    private var cache: [String: NSAppleScript] = [:]
    private let lock = NSLock()

    private init() {}

    // MARK: Availability

    func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func isInstalled(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Opens the app without bringing it in front of what you're doing.
    func launch(bundleID: String, activate: Bool = false) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Blocks until the app is running, or `timeout` passes. Call off the main thread.
    @discardableResult
    func waitUntilRunning(bundleID: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isRunning(bundleID: bundleID) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return isRunning(bundleID: bundleID)
    }

    // MARK: Execution

    /// Runs `source`, returning the raw descriptor or `nil` on any failure.
    @discardableResult
    func run(_ source: String) -> NSAppleEventDescriptor? {
        lock.lock()
        let script: NSAppleScript
        if let cached = cache[source] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else { lock.unlock(); return nil }
            cache[source] = fresh
            script = fresh
        }
        lock.unlock()

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "no message"
            // -1743 = automation permission not granted. Everything else
            // (notably -1728, "no current track") is normal operation.
            if code == -1743 {
                authorizationMessage = message
            }
            report(code: code, message: message, source: source)
            return nil
        }
        authorizationMessage = nil
        return result
    }

    // MARK: Diagnostics

    private static let log = Logger(subsystem: "app.wax.deck", category: "applescript")
    private var lastReported: [String: Int] = [:]

    /// Logs a failing script once per distinct error, so a poll that fails
    /// every second doesn't flood the log.
    private func report(code: Int, message: String, source: String) {
        let key = String(source.prefix(80))
        lock.lock()
        let isNew = lastReported[key] != code
        lastReported[key] = code
        lock.unlock()
        guard isNew else { return }
        Self.log.error("""
            script failed (\(code)): \(message, privacy: .public) — \
            \(source.replacingOccurrences(of: "\n", with: " ").prefix(120), privacy: .public)
            """)
    }

    /// Runs `source` and returns its non-empty string value.
    func string(_ source: String) -> String? {
        guard let value = run(source)?.stringValue, !value.isEmpty else { return nil }
        return value
    }

    /// Runs a script returning separator-joined fields, split back into an array.
    func fields(_ source: String) -> [String]? {
        string(source)?.components(separatedBy: AppleScriptRunner.sep)
    }

    /// Runs a script returning raw image data (Music.app artwork).
    func data(_ source: String) -> Data? {
        guard let data = run(source)?.data, !data.isEmpty else { return nil }
        return data
    }

    /// Fire-and-forget command. Skips entirely if the host app is asleep.
    func command(_ source: String, requiring bundleID: String?) {
        if let bundleID, !isRunning(bundleID: bundleID) { return }
        DispatchQueue.global(qos: .userInitiated).async { _ = self.run(source) }
    }

    /// A command the user asked for by name ("play this playlist"): opens the
    /// app first if it's closed, then retries briefly while it wakes up.
    func commandLaunching(_ source: String, bundleID: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let wasRunning = self.isRunning(bundleID: bundleID)
            if !wasRunning {
                self.launch(bundleID: bundleID)
                guard self.waitUntilRunning(bundleID: bundleID, timeout: 15) else { return }
                Thread.sleep(forTimeInterval: 1.5)
            }
            for attempt in 0..<4 {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                _ = script?.executeAndReturnError(&error)
                if error == nil { return }
                if (error?[NSAppleScript.errorNumber] as? Int) == -1743 { return }
                Thread.sleep(forTimeInterval: 0.8 + Double(attempt) * 0.4)
            }
        }
    }
}
