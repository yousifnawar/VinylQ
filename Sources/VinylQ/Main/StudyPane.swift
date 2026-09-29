import SwiftUI

/// Study mode, with room to explain itself.
struct StudyPane: View {

    @ObservedObject var study: StudyTimer
    @ObservedObject var settings: Settings
    var onOpenAmbient: () -> Void
    var onRevealNotch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PaneSection(
                title: "Study",
                caption: "A focus timer that stays out of the way: no alerts, no stolen focus, no pausing your record. Just one soft sound when it's time to stop."
            ) {
                FocusTimerPanel(timer: study, settings: settings)
            }

            PaneSection(title: "Wherever you are", caption: nil) {
                HStack(alignment: .top, spacing: 14) {
                    place(
                        symbol: "rectangle.topthird.inset.filled",
                        title: "In the notch",
                        body: "While a block runs, the countdown rides in the pill. Hover for the full timer.",
                        action: ("Show it", onRevealNotch)
                    )
                    place(
                        symbol: "arrow.up.left.and.arrow.down.right",
                        title: "Full screen",
                        body: "Tucked under the clock on the ambient deck — just the time, until you open it up.",
                        action: ("Open the deck", onOpenAmbient)
                    )
                    place(
                        symbol: "square.grid.2x2",
                        title: "On your desktop",
                        body: "Add the Focus Timer widget: Edit Widgets… → search VinylQ.",
                        action: nil
                    )
                }
            }
        }
    }

    private func place(symbol: String, title: String, body: String, action: (String, () -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.brass)
            Text(title)
                .font(Theme.display(13.5, .semibold))
                .foregroundStyle(Theme.cream)
            Text(body)
                .font(Theme.display(11.5))
                .foregroundStyle(Theme.creamFaint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(action: action.1) {
                    HStack(spacing: 4) {
                        Text(action.0).font(Theme.display(11.5, .medium))
                        Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Theme.brass)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .sleeveCard(radius: 16, padding: 16)
    }
}
