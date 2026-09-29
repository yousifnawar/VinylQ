import SwiftUI

/// The clock that appears when the deck goes full screen.
struct AmbientClock: View {

    @ObservedObject var settings: Settings
    var size: CGFloat = 76
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        TimelineView(.everyMinute(orSecond: settings.ambientShowSeconds)) { timeline in
            VStack(alignment: alignment, spacing: size * 0.05) {
                Text(timeString(timeline.date))
                    .font(Theme.mono(size, .light))
                    .foregroundStyle(Theme.cream)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.35), value: timeString(timeline.date))

                Text(Self.dateFormatter.string(from: timeline.date).uppercased())
                    .font(Theme.display(size * 0.18, .medium))
                    .foregroundStyle(Theme.creamFaint)
                    .tracking(size * 0.022)
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let hour = settings.ambientTwentyFourHour ? "HH" : "h"
        let format = settings.ambientShowSeconds ? "\(hour):mm:ss" : "\(hour):mm"
        return Self.formatter(format).string(from: date)
    }

    // Formatters are expensive to build; the clock redraws every minute.
    private static var formatters: [String: DateFormatter] = [:]

    private static func formatter(_ format: String) -> DateFormatter {
        if let cached = formatters[format] { return cached }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatters[format] = formatter
        return formatter
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter
    }()
}

private extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    /// Ticks on the minute (or second), aligned to the wall clock.
    static func everyMinute(orSecond seconds: Bool) -> PeriodicTimelineSchedule {
        let now = Date()
        let interval: TimeInterval = seconds ? 1 : 60
        let start = Date(timeIntervalSinceReferenceDate:
            (now.timeIntervalSinceReferenceDate / interval).rounded(.down) * interval)
        return .periodic(from: start, by: interval)
    }
}
