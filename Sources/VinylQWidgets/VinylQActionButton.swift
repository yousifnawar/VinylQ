import AppIntents
import SwiftUI

/// A widget button: an App Intent while VinylQ is running, so a tap acts without
/// bringing anything forward; a `vinylq://` link when it isn't, which opens VinylQ
/// and carries the same command.
///
/// The app defines its own `VinylQActionButton` with the same shape, which is how
/// the shared widget designs work in both places.
struct VinylQActionButton<Label: View>: View {
    let action: VinylQCommand
    @ViewBuilder let label: () -> Label

    @Environment(\.vinylqAppRunning) private var appRunning

    var body: some View {
        if appRunning {
            intentButton.buttonStyle(.plain)
        } else {
            Link(destination: action.url) { label() }
        }
    }

    @ViewBuilder
    private var intentButton: some View {
        switch action {
        case .togglePlayback: Button(intent: TogglePlaybackIntent()) { label() }
        case .nextTrack:      Button(intent: NextTrackIntent()) { label() }
        case .previousTrack:  Button(intent: PreviousTrackIntent()) { label() }
        case .toggleFocus:    Button(intent: ToggleFocusIntent()) { label() }
        case .skipFocus:      Button(intent: SkipFocusIntent()) { label() }
        case .resetFocus:     Button(intent: ResetFocusIntent()) { label() }
        }
    }
}
