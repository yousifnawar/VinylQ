import AppKit
import SwiftUI

// The record, split into layers by how often they change.
//
// A spinning record only *looks* like it redraws every frame. The mat, the
// disc and its grooves are rotationally symmetric, so they never change at
// all; the label and the light sweeping across the vinyl only rotate. Each
// layer is `Equatable`, so SwiftUI keeps its rendered output and a frame of
// animation costs one rotation transform rather than a few hundred strokes.

/// Slipmat, disc and grooves — everything that holds still.
struct PlatterBase: View, Equatable {
    let geometry: DeckGeometry
    var compact: Bool = false

    private var diameter: CGFloat { geometry.recordRadius * 2 }

    var body: some View {
        ZStack {
            mat
            disc
            grooves
        }
        .frame(width: geometry.side, height: geometry.side)
    }

    /// The felt slipmat peeking out beyond the record.
    private var mat: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(hex: 0x2A231C), Color(hex: 0x15110D)],
                    center: .center,
                    startRadius: 0,
                    endRadius: geometry.recordRadius * 1.08
                )
            )
            .frame(width: diameter * 1.075, height: diameter * 1.075)
            .position(geometry.center)
    }

    private var disc: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: 0x1C1A19), Color(hex: 0x0B0A0A),
                        Color(hex: 0x131211), Color(hex: 0x060606)
                    ],
                    center: .center,
                    startRadius: geometry.labelRadius,
                    endRadius: geometry.recordRadius
                )
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75))
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.55), radius: geometry.side * 0.03, y: geometry.side * 0.012)
            .position(geometry.center)
    }

    private var grooves: some View {
        Canvas { context, _ in
            let c = geometry.center
            let outer = geometry.outerGroove
            let inner = geometry.innerGroove
            let count = compact ? 26 : 58
            let step = (outer - inner) / CGFloat(count)
            let width = max(0.4, geometry.side * 0.0016)

            for i in 0...count {
                let r = inner + step * CGFloat(i)
                // A repeating light/dark beat reads as vinyl rather than a target.
                let opacity = i % 7 == 0 ? 0.13 : (i % 2 == 0 ? 0.055 : 0.028)
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)), lineWidth: width)
            }

            // Lead-in and run-out land as slightly wider gaps.
            for r in [outer + step * 1.4, inner - step * 1.4] where r > 0 {
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.10)),
                               lineWidth: max(0.5, geometry.side * 0.002))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The grooves the needle has already travelled, a shade brighter.
///
/// Driven by a coarse `step` rather than raw progress, so it redraws a few
/// hundred times across a whole side instead of every frame.
struct PlayedGrooves: View, Equatable {
    let geometry: DeckGeometry
    var compact: Bool = false
    /// Progress quantised to `0...PlayedGrooves.steps`.
    let step: Int

    static let steps = 400

    static func step(for progress: Double) -> Int {
        Int((min(max(progress, 0), 1) * Double(steps)).rounded())
    }

    var body: some View {
        Canvas { context, _ in
            guard step > 0 else { return }
            let c = geometry.center
            let outer = geometry.outerGroove
            let inner = geometry.innerGroove
            let count = compact ? 26 : 58
            let grooveStep = (outer - inner) / CGFloat(count)
            let playedRadius = outer - (outer - inner) * CGFloat(step) / CGFloat(Self.steps)
            let width = max(0.4, geometry.side * 0.0016)

            for i in 0...count {
                let r = inner + grooveStep * CGFloat(i)
                guard r >= playedRadius else { continue }
                let base = i % 7 == 0 ? 0.13 : (i % 2 == 0 ? 0.055 : 0.028)
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(base * 0.9)), lineWidth: width)
            }
        }
        .frame(width: geometry.side, height: geometry.side)
        .allowsHitTesting(false)
    }
}

/// The paper label — cover art when there is some, printed text when not.
struct RecordLabel: View, Equatable {
    let geometry: DeckGeometry
    let artwork: NSImage?
    let accent: Color
    let title: String
    let subtitle: String
    var compact: Bool = false

    static func == (a: RecordLabel, b: RecordLabel) -> Bool {
        a.geometry == b.geometry && a.artwork === b.artwork && a.accent == b.accent
            && a.title == b.title && a.subtitle == b.subtitle && a.compact == b.compact
    }

    var body: some View {
        let r = geometry.labelRadius
        ZStack {
            Circle()
                .fill(accent.opacity(0.9))
                .overlay(Circle().fill(Theme.rust.opacity(artwork == nil ? 0.55 : 0)))

            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            } else if !compact {
                VStack(spacing: r * 0.08) {
                    Text(title)
                        .font(Theme.display(r * 0.20, .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(Theme.display(r * 0.15, .medium))
                        .opacity(0.75)
                        .lineLimit(1)
                }
                .foregroundStyle(Color(hex: 0x1A1208))
                .padding(.horizontal, r * 0.24)
            }

            // The ring where it's glued down, and a faint pressed edge.
            Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: r * 0.045)
            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                .padding(r * 0.12)
        }
        .frame(width: r * 2, height: r * 2)
        .clipShape(Circle())
    }
}

/// Light raking across the vinyl — the part that makes it read as spinning.
struct RecordSheen: View, Equatable {
    let geometry: DeckGeometry

    var body: some View {
        Circle()
            .fill(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white.opacity(0.00), location: 0.00),
                        .init(color: .white.opacity(0.075), location: 0.11),
                        .init(color: .white.opacity(0.00), location: 0.26),
                        .init(color: .white.opacity(0.00), location: 0.50),
                        .init(color: .white.opacity(0.05), location: 0.61),
                        .init(color: .white.opacity(0.00), location: 0.78)
                    ]),
                    center: .center
                )
            )
            .mask(
                // Keep the sweep on the vinyl, off the label.
                Circle()
                    .strokeBorder(Color.white, lineWidth: geometry.recordRadius - geometry.labelRadius)
            )
            .frame(width: geometry.recordRadius * 2, height: geometry.recordRadius * 2)
            .allowsHitTesting(false)
    }
}

/// The brushed spindle through the middle.
struct Spindle: View, Equatable {
    let geometry: DeckGeometry

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: geometry.spindleRadius * 2.6, height: geometry.spindleRadius * 2.6)
            Capsule()
                .fill(Theme.brushed)
                .frame(width: geometry.spindleRadius * 1.5, height: geometry.spindleRadius * 1.5)
        }
        .allowsHitTesting(false)
    }
}

/// The whole record at one instant — for places that draw a still frame,
/// such as widgets. The live deck assembles the same layers itself so it can
/// keep the static ones cached while the others turn.
struct VinylPlatter: View {
    var geometry: DeckGeometry
    var artwork: NSImage?
    var accent: Color
    /// Degrees of platter rotation.
    var angle: Double
    var progress: Double
    var title: String
    var subtitle: String
    var compact: Bool = false

    var body: some View {
        ZStack {
            PlatterBase(geometry: geometry, compact: compact)
            PlayedGrooves(geometry: geometry, compact: compact, step: PlayedGrooves.step(for: progress))
            RecordSheen(geometry: geometry)
                .rotationEffect(.degrees(angle))
                .position(geometry.center)
            RecordLabel(geometry: geometry, artwork: artwork, accent: accent,
                        title: title, subtitle: subtitle, compact: compact)
                .rotationEffect(.degrees(angle))
                .position(geometry.center)
            Spindle(geometry: geometry)
                .position(geometry.center)
        }
        .frame(width: geometry.side, height: geometry.side)
    }
}
