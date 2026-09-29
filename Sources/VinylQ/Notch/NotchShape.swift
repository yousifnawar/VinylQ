import SwiftUI

/// The outline of the notch panel, drawn to be mistaken for the hardware.
///
/// The real notch is flat along the top edge of the screen, rounded at the
/// bottom, and where it meets the edge the display curves *into* it — a
/// small concave flare. This shape does the same: `topFlare` is that concave
/// curve, `bottomRadius` the convex one. Filled pure black, the collapsed
/// pill reads as the notch simply being a little wider, and opening it
/// looks like the notch itself growing.
///
/// Every dimension is animatable, so a single spring carries the shape from
/// pill to panel with no jumps — the width and height come from the frame,
/// the curves from `animatableData`.
struct NotchShape: Shape {

    /// Concave curve where the top edge meets the screen edge.
    var topFlare: CGFloat
    /// Convex rounding at the top corners — for a panel hanging free below
    /// a menu bar on Macs without a notch. Use either this or `topFlare`.
    var topRadius: CGFloat = 0
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(topFlare, topRadius), bottomRadius) }
        set {
            topFlare = newValue.first.first
            topRadius = newValue.first.second
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let flare = max(0, min(topFlare, rect.width / 4, rect.height / 2))
        let left = rect.minX + flare
        let right = rect.maxX - flare
        let bodyWidth = max(0, right - left)
        let top = max(0, min(topRadius, bodyWidth / 2, rect.height / 2))
        let bottom = max(0, min(bottomRadius, bodyWidth / 2, rect.height - max(flare, top)))

        var path = Path()

        // Top edge, flush with the screen.
        if flare > 0 {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + flare),
                              control: CGPoint(x: right, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: left + top, y: rect.minY))
            path.addLine(to: CGPoint(x: right - top, y: rect.minY))
            if top > 0 {
                path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + top),
                                  control: CGPoint(x: right, y: rect.minY))
            }
        }

        // Right side and the bottom corners.
        path.addLine(to: CGPoint(x: right, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: right - bottom, y: rect.maxY),
                          control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: left + bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - bottom),
                          control: CGPoint(x: left, y: rect.maxY))

        // Back up the left side to where we began.
        if flare > 0 {
            path.addLine(to: CGPoint(x: left, y: rect.minY + flare))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                              control: CGPoint(x: left, y: rect.minY))
        } else {
            path.addLine(to: CGPoint(x: left, y: rect.minY + top))
            if top > 0 {
                path.addQuadCurve(to: CGPoint(x: left + top, y: rect.minY),
                                  control: CGPoint(x: left, y: rect.minY))
            }
        }
        path.closeSubpath()
        return path
    }
}
