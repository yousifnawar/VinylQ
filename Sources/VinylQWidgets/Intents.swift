import AppIntents
import Foundation

// The widgets' buttons.
//
// Each intent runs inside the widget extension, which is sandboxed and can't
// touch the music itself, so it just tells VinylQ what was pressed. The short
// wait gives VinylQ time to act and write its new state before WidgetKit redraws
// the widget, so the button you pressed shows its result straight away.

private func ask(_ command: VinylQCommand) async {
    command.post()
    try? await Task.sleep(nanoseconds: 400_000_000)
}

struct TogglePlaybackIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays or pauses the record on VinylQ's deck.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await ask(.togglePlayback)
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let description = IntentDescription("Skips to the next song.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await ask(.nextTrack)
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let description = IntentDescription("Goes back a song.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await ask(.previousTrack)
        return .result()
    }
}

struct ToggleFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or Pause Focus"
    static let description = IntentDescription("Starts, pauses or resumes VinylQ's focus timer.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await ask(.toggleFocus)
        return .result()
    }
}

struct SkipFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Block"
    static let description = IntentDescription("Moves the focus timer on to the next block.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await ask(.skipFocus)
        return .result()
    }
}

struct ResetFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Timer"
    static let description = IntentDescription("Stops the focus timer and starts the cycle over.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await ask(.resetFocus)
        return .result()
    }
}
