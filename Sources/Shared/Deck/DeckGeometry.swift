import CoreGraphics
import Foundation

/// Proportional layout for the deck, solved from real turntable geometry.
///
/// Everything is a fraction of the shortest side, so the same deck draws
/// correctly at 120 pt in the notch and at 900 pt across a desktop. The arm
/// angles aren't eyeballed: given a pivot, an arm length and a groove radius,
/// the law of cosines gives the one angle that puts the stylus in that groove.
struct DeckGeometry: Equatable {

    let side: CGFloat

    init(side: CGFloat) { self.side = side }

    // MARK: Platter

    var center: CGPoint { CGPoint(x: side * 0.455, y: side * 0.525) }
    var recordRadius: CGFloat { side * 0.395 }
    var labelRadius: CGFloat { recordRadius * 0.345 }
    var spindleRadius: CGFloat { side * 0.009 }

    /// Grooved area: from the lead-in at the rim to the run-out by the label.
    var outerGroove: CGFloat { recordRadius * 0.93 }
    var innerGroove: CGFloat { recordRadius * 0.40 }

    // MARK: Tonearm

    var pivot: CGPoint { CGPoint(x: side * 0.895, y: side * 0.150) }
    var armLength: CGFloat { side * 0.620 }
    var headshellRadius: CGFloat { side * 0.052 }

    /// Angle, in degrees, of the pivot→centre line in screen space.
    private var baseAngle: Double {
        Double(atan2(center.y - pivot.y, center.x - pivot.x)) * 180 / .pi
    }

    private var pivotDistance: CGFloat {
        hypot(pivot.x - center.x, pivot.y - center.y)
    }

    /// The arm angle that lands the stylus `radius` out from the spindle.
    func angle(forGrooveRadius radius: CGFloat) -> Double {
        let d = pivotDistance
        guard d > 0, armLength > 0 else { return baseAngle }
        let cosine = (armLength * armLength + d * d - radius * radius) / (2 * armLength * d)
        let theta = acos(Double(min(max(cosine, -1), 1))) * 180 / .pi
        return baseAngle - theta
    }

    var startAngle: Double { angle(forGrooveRadius: outerGroove) }
    var endAngle: Double { angle(forGrooveRadius: innerGroove) }
    /// Parked on the rest, clear of the record.
    var restAngle: Double { startAngle - 17 }

    /// Arm angle for a point in the track, or the rest when nothing is cued.
    func armAngle(progress: Double, parked: Bool) -> Double {
        guard !parked else { return restAngle }
        let p = min(max(progress, 0), 1)
        return startAngle + (endAngle - startAngle) * p
    }

    /// Where the stylus sits for a given arm angle.
    func tip(atAngle degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: pivot.x + armLength * CGFloat(cos(radians)),
            y: pivot.y + armLength * CGFloat(sin(radians))
        )
    }

    /// Inverse of `armAngle` — turns a drag location into a position in the
    /// track by asking which way the arm would have to point to reach it.
    func progress(forDragAt point: CGPoint) -> Double {
        let degrees = Double(atan2(point.y - pivot.y, point.x - pivot.x)) * 180 / .pi
        let span = endAngle - startAngle
        guard abs(span) > 0.001 else { return 0 }
        return min(max((degrees - startAngle) / span, 0), 1)
    }
}
