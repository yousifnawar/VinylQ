import SwiftUI
import WidgetKit

/// VinylQ's desktop widgets: the record that's playing, and the focus timer.
@main
struct VinylQWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        FocusTimerWidget()
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VinylQWidgetKind.nowPlaying, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("The record on VinylQ's deck, with play, pause and skip.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct FocusTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VinylQWidgetKind.focus, provider: FocusProvider()) { entry in
            FocusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Focus Timer")
        .description("VinylQ's study timer. Start, pause and skip blocks from your desktop.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Entry views

private struct NowPlayingWidgetEntryView: View {
    var entry: VinylQEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        NowPlayingWidgetView(state: entry.state, artwork: entry.artwork, family: family, date: entry.date)
            .environment(\.vinylqAppRunning, entry.appRunning)
            .widgetURL(entry.appRunning ? nil : URL(string: "vinylq://open"))
            .containerBackground(for: .widget) {
                NowPlayingWidgetBackground(state: entry.state, artwork: entry.artwork)
            }
    }
}

private struct FocusWidgetEntryView: View {
    var entry: VinylQEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        FocusWidgetView(state: entry.state, family: family, date: entry.date)
            .environment(\.vinylqAppRunning, entry.appRunning)
            .widgetURL(entry.appRunning ? nil : URL(string: "vinylq://open"))
            .containerBackground(for: .widget) {
                FocusWidgetBackground(state: entry.state)
            }
    }
}
