import AppKit
import SwiftUI

/// A small spinning disc — the notch's whole idle presence.
///
/// Only the label turns; the disc under it is drawn once and kept.
struct MiniRecord: View {

    @ObservedObject var engine: PlayerEngine
    var diameter: CGFloat

    var body: some View {
        ZStack {
            MiniRecordDisc(diameter: diameter).equatable()

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !engine.snapshot.isPlaying)) { timeline in
                MiniRecordLabel(artwork: engine.artwork, accent: engine.accent, diameter: diameter)
                    .equatable()
                    .rotationEffect(.degrees(engine.platterAngle(at: timeline.date)))
            }

            Circle()
                .fill(Theme.ink)
                .frame(width: diameter * 0.075, height: diameter * 0.075)

            Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct MiniRecordDisc: View, Equatable {
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x1A1918), Color(hex: 0x070707)],
                        center: .center, startRadius: diameter * 0.12, endRadius: diameter * 0.5
                    )
                )
            // Two grooves are enough to read as vinyl at this size.
            ForEach([0.78, 0.58], id: \.self) { fraction in
                Circle()
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.5)
                    .frame(width: diameter * fraction, height: diameter * fraction)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct MiniRecordLabel: View, Equatable {
    let artwork: NSImage?
    let accent: Color
    let diameter: CGFloat

    static func == (a: Self, b: Self) -> Bool {
        a.artwork === b.artwork && a.accent == b.accent && a.diameter == b.diameter
    }

    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle().fill(accent)
            }
        }
        .frame(width: diameter * 0.42, height: diameter * 0.42)
        .clipShape(Circle())
    }
}

/// Four bars that breathe while something is playing, still when it isn't.
struct LiveBars: View {

    var isPlaying: Bool
    var tint: Color
    var height: CGFloat = 11
    var barWidth: CGFloat = 2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth * 0.9) {
                ForEach(0..<4, id: \.self) { index in
                    let phase = t * 3.1 + Double(index) * 0.8
                    let wobble = 0.5 + 0.5 * sin(t * 1.7 + Double(index) * 1.3)
                    let amount = isPlaying ? (0.3 + 0.7 * abs(sin(phase)) * (0.7 + 0.3 * wobble)) : 0.22
                    Capsule()
                        .fill(tint.opacity(isPlaying ? 0.95 : 0.4))
                        .frame(width: barWidth, height: max(barWidth, height * amount))
                }
            }
            .frame(height: height, alignment: .center)
        }
        .animation(.easeOut(duration: 0.3), value: isPlaying)
    }
}
