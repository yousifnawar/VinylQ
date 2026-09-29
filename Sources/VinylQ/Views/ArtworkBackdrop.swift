import AppKit
import SwiftUI

/// A soft wash of the current cover art, used behind the ambient deck.
///
/// It draws `PlayerEngine.backdrop` — a tiny copy of the cover that was
/// blurred once when the track changed — stretched across the view. That
/// looks the same as blurring the full image by a hundred points, without
/// paying for a full-screen blur on every frame.
///
/// The art is laid over a `Color.clear` rather than dropped into a stack
/// directly: `.aspectRatio(contentMode: .fill)` reports a size big enough to
/// cover the proposal, which would inflate a `ZStack` and push its siblings
/// out of view.
struct ArtworkBackdrop: View {

    var image: NSImage?
    var saturation: Double = 1.3
    /// Slight over-scale so the soft edges never reach the frame.
    var zoom: CGFloat = 1.15

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .saturation(saturation)
                        .scaleEffect(zoom)
                } else {
                    LinearGradient(
                        colors: [Color(hex: 0x241C15), Theme.ink],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            .clipped()
    }
}
