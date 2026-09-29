import SwiftUI

/// The tonearm — counterweight, pivot, tube, headshell and stylus.
///
/// Drawn in its own flat coordinate space with the pivot on the left and the
/// stylus `armLength` to the right, then rotated about the pivot. That way the
/// stylus always lands exactly where `DeckGeometry` says it should, and the
/// same drawing works at any size.
struct Tonearm: View {

    var geometry: DeckGeometry
    /// Arm angle in degrees, already including any in-progress scrub.
    var angle: Double
    var isScrubbing: Bool
    var accent: Color
    var interactive: Bool = true
    /// Flattens the arm into a texture so turning it is just a transform.
    /// Off for widgets, which render still frames and can't host Metal.
    var rasterize: Bool = false

    var onScrubBegan: (Double) -> Void = { _ in }
    var onScrubChanged: (Double) -> Void = { _ in }
    var onScrubEnded: () -> Void = {}

    var body: some View {
        ZStack {
            arm
            if interactive {
                TonearmHandle(
                    geometry: geometry, angle: angle, isScrubbing: isScrubbing, accent: accent,
                    onScrubBegan: onScrubBegan, onScrubChanged: onScrubChanged, onScrubEnded: onScrubEnded
                )
            }
        }
        .frame(width: geometry.side, height: geometry.side)
    }

    @ViewBuilder
    private var arm: some View {
        let shape = TonearmBody(geometry: geometry, isScrubbing: isScrubbing, accent: accent)
        let anchor = UnitPoint(x: shape.pivotX / shape.frameWidth, y: 0.5)
        let position = CGPoint(x: geometry.pivot.x + (shape.frameWidth / 2 - shape.pivotX), y: geometry.pivot.y)

        if rasterize {
            shape.equatable()
                .drawingGroup()
                .rotationEffect(.degrees(angle), anchor: anchor)
                .position(position)
                .allowsHitTesting(false)
        } else {
            shape
                .rotationEffect(.degrees(angle), anchor: anchor)
                .position(position)
                .allowsHitTesting(false)
        }
    }
}

/// The arm itself, lying flat. Everything that doesn't depend on the angle.
struct TonearmBody: View, Equatable {
    let geometry: DeckGeometry
    let isScrubbing: Bool
    let accent: Color

    private var side: CGFloat { geometry.side }
    private var armLength: CGFloat { geometry.armLength }
    private var counterweightLength: CGFloat { armLength * 0.16 }
    var pivotX: CGFloat { counterweightLength }
    var frameWidth: CGFloat { counterweightLength + armLength + side * 0.03 }
    private var frameHeight: CGFloat { side * 0.14 }
    private var tubeWidth: CGFloat { max(1.5, side * 0.0135) }

    var body: some View {
        let mid = frameHeight / 2

        ZStack(alignment: .topLeading) {
            // Counterweight behind the pivot.
            Capsule()
                .fill(Theme.brushed)
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.6))
                .frame(width: counterweightLength * 0.82, height: frameHeight * 0.34)
                .position(x: counterweightLength * 0.40, y: mid)

            // Tube.
            Capsule()
                .fill(Theme.brushed)
                .frame(width: armLength, height: tubeWidth)
                .position(x: pivotX + armLength / 2, y: mid)
                .shadow(color: .black.opacity(0.5), radius: side * 0.006, y: side * 0.004)

            // Finger lift.
            Capsule()
                .fill(Theme.brushed)
                .frame(width: side * 0.055, height: tubeWidth * 0.62)
                .rotationEffect(.degrees(-26), anchor: .center)
                .position(x: pivotX + armLength * 0.84, y: mid - frameHeight * 0.09)

            // Headshell and cartridge.
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.008, style: .continuous)
                    .fill(Theme.brushed)
                    .frame(width: side * 0.072, height: side * 0.030)
                RoundedRectangle(cornerRadius: side * 0.005, style: .continuous)
                    .fill(Color(hex: 0x22201D))
                    .frame(width: side * 0.044, height: side * 0.020)
                    .offset(x: side * 0.008)
            }
            .position(x: pivotX + armLength - side * 0.030, y: mid)

            // Stylus: the one part that touches the record.
            Path { path in
                let tipX = pivotX + armLength
                path.move(to: CGPoint(x: tipX - side * 0.011, y: mid + side * 0.004))
                path.addLine(to: CGPoint(x: tipX, y: mid + side * 0.019))
                path.addLine(to: CGPoint(x: tipX + side * 0.006, y: mid + side * 0.003))
                path.closeSubpath()
            }
            .fill(isScrubbing ? accent : Color(hex: 0xD8D2C8))

            // Pivot gimbal, drawn last so it sits on top of the tube.
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xEDE7DC), Color(hex: 0x6B6459)],
                                         center: .topLeading, startRadius: 0,
                                         endRadius: frameHeight * 0.42))
                    .frame(width: frameHeight * 0.46, height: frameHeight * 0.46)
                Circle()
                    .fill(Color(hex: 0x141210))
                    .frame(width: frameHeight * 0.16, height: frameHeight * 0.16)
            }
            .position(x: pivotX, y: mid)
            .shadow(color: .black.opacity(0.6), radius: side * 0.01, y: side * 0.006)
        }
        .frame(width: frameWidth, height: frameHeight)
    }
}

/// The invisible grip on the headshell that lets you drag the needle.
private struct TonearmHandle: View {
    var geometry: DeckGeometry
    var angle: Double
    var isScrubbing: Bool
    var accent: Color
    var onScrubBegan: (Double) -> Void
    var onScrubChanged: (Double) -> Void
    var onScrubEnded: () -> Void

    @State private var hovering = false

    var body: some View {
        let tip = geometry.tip(atAngle: angle)
        let radius = geometry.headshellRadius * 1.8

        Circle()
            .fill(Color.white.opacity(0.001))   // invisible, still hit-testable
            .overlay(
                Circle()
                    .strokeBorder(accent.opacity(hovering || isScrubbing ? 0.55 : 0), lineWidth: 1.2)
            )
            .frame(width: radius * 2, height: radius * 2)
            .position(tip)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.18), value: hovering)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(DeckSpace.name))
                    .onChanged { value in
                        let progress = geometry.progress(forDragAt: value.location)
                        if isScrubbing { onScrubChanged(progress) } else { onScrubBegan(progress) }
                    }
                    .onEnded { _ in onScrubEnded() }
            )
    }
}

/// Shared name for the deck's drag coordinate space.
enum DeckSpace {
    static let name = "wax.deck"
}
