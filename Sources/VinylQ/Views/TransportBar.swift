import SwiftUI

/// Play/pause, skip, and a slim scrub bar.
///
/// The stylus is the headline gesture, but a thin bar is faster for long jumps,
/// so both drive the same `PlayerEngine` scrub.
struct TransportBar: View {

    @ObservedObject var engine: PlayerEngine
    /// Base point size; every metric below is derived from it.
    var scale: CGFloat = 13
    var showsTime: Bool = true
    var showsScrubBar: Bool = true
    /// Centred reads better when the bar stands alone; leading lines up with
    /// a title above it.
    var centred: Bool = false
    var showsVolume: Bool = false

    var body: some View {
        VStack(spacing: scale * 0.55) {
            if showsScrubBar {
                ScrubBar(engine: engine, scale: scale, showsTime: showsTime)
            }
            buttons
            if showsVolume {
                VolumeSlider(engine: engine, scale: scale)
                    .frame(maxWidth: scale * 12)
                    .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: scale * 1.3) {
            DeckButton(symbol: "backward.fill", size: scale * 1.05) { engine.previous() }
            DeckButton(
                symbol: engine.snapshot.isPlaying ? "pause.fill" : "play.fill",
                size: scale * 1.35,
                prominent: true,
                tint: engine.accent
            ) { engine.togglePlayPause() }
            DeckButton(symbol: "forward.fill", size: scale * 1.05) { engine.next() }
        }
        .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)
    }
}

/// The bar itself, in its own view so its timeline redraws only the bar.
private struct ScrubBar: View {
    @ObservedObject var engine: PlayerEngine
    var scale: CGFloat
    var showsTime: Bool

    @State private var dragging = false
    @State private var hovering = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !engine.snapshot.isPlaying)) { timeline in
            let progress = engine.progress(at: timeline.date)

            VStack(spacing: scale * 0.30) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let thick = dragging || hovering
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(engine.accent.opacity(0.9))
                            .frame(width: max(0, width * progress))
                        Circle()
                            .fill(Theme.cream)
                            .frame(width: scale * 0.7, height: scale * 0.7)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                            .offset(x: max(0, min(width - scale * 0.7, width * progress - scale * 0.35)))
                            .opacity(thick ? 1 : 0)
                            .scaleEffect(thick ? 1 : 0.4)
                    }
                    .frame(height: scale * (thick ? 0.36 : 0.24))
                    .frame(height: scale * 0.9)          // generous hit area
                    .contentShape(Rectangle())
                    .onHover { hovering = $0 }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragging = true
                                engine.updateScrub(to: value.location.x / max(width, 1))
                            }
                            .onEnded { _ in
                                dragging = false
                                engine.endScrub()
                            }
                    )
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: thick)
                }
                .frame(height: scale * 0.9)

                if showsTime {
                    HStack {
                        Text(engine.position(at: timeline.date).clockString)
                        Spacer(minLength: 0)
                        Text(engine.snapshot.track.duration.clockString)
                    }
                    .font(Theme.mono(scale * 0.66))
                    .monospacedDigit()
                    .foregroundStyle(Theme.creamFaint)
                }
            }
        }
    }
}

/// Speaker icon and a thin slider; click the icon to mute.
private struct VolumeSlider: View {
    @ObservedObject var engine: PlayerEngine
    var scale: CGFloat

    @State private var hovering = false
    @State private var dragging = false
    @State private var mutedFrom: Double?

    private var symbol: String {
        switch engine.volume {
        case 0: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        HStack(spacing: scale * 0.6) {
            Button {
                if engine.volume > 0 {
                    mutedFrom = engine.volume
                    engine.setVolume(0)
                } else {
                    engine.setVolume(mutedFrom ?? 0.6)
                }
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: scale * 0.8))
                    .foregroundStyle(Theme.creamSoft)
                    .frame(width: scale * 1.4, height: scale * 1.4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Mute")

            GeometryReader { proxy in
                let width = proxy.size.width
                let thick = dragging || hovering
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(engine.accent.opacity(0.9))
                        .frame(width: max(0, width * engine.volume))
                }
                .frame(height: scale * (thick ? 0.36 : 0.24))
                .frame(height: scale * 0.9)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragging = true
                            engine.setVolume(value.location.x / max(width, 1))
                        }
                        .onEnded { _ in dragging = false }
                )
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: thick)
            }
            .frame(height: scale * 0.9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(engine.volume * 100)) percent")
    }
}

/// A round, quiet control that lifts slightly on hover.
struct DeckButton: View {
    var symbol: String
    var size: CGFloat
    var prominent: Bool = false
    var tint: Color = Theme.cream
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(prominent ? Theme.ink : Theme.cream)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size * 2.1, height: size * 2.1)
                .background(
                    Circle().fill(
                        prominent
                            ? AnyShapeStyle(tint.opacity(hovering ? 1 : 0.92))
                            : AnyShapeStyle(Color.white.opacity(hovering ? 0.14 : 0.07))
                    )
                )
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(prominent ? 0 : 0.10), lineWidth: 0.6)
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(hovering ? 1.06 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
    }
}
