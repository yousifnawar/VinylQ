import AppKit

/// Entry point.
///
/// VinylQ is driven by AppKit rather than a SwiftUI `App`: it owns a borderless
/// notch panel, a full-screen deck and an ordinary window, and coordinating
/// those three is far simpler from a delegate than from a `Scene`.
@main
enum VinylQMain {

    @MainActor private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--render") {
            // Offscreen snapshot pass — see Snapshotter.
            let path = arguments.count > flag + 1 ? arguments[flag + 1] : "./Screenshots"
            _ = NSApplication.shared
            Snapshotter.run(outputDirectory: URL(fileURLWithPath: path))
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
