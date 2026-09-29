import CoreGraphics
import SwiftUI

/// Shared state between the notch view and the window controller that
/// decides when it opens.
@MainActor
final class NotchState: ObservableObject {

    enum Tab: String, CaseIterable, Identifiable {
        case player, timer, playlist

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .player:   return "opticaldisc"
            case .timer:    return "timer"
            case .playlist: return "list.bullet"
            }
        }

        var title: String {
            switch self {
            case .player:   return "Now Playing"
            case .timer:    return "Focus Timer"
            case .playlist: return "Playlists"
            }
        }
    }

    @Published var isOpen = false
    @Published var tab: Tab = .player
    /// A new song just started: the pill drops a little to name it, then
    /// tucks back in.
    @Published var isPeeking = false

    /// Physical notch metrics for the active screen; zero on Macs without one.
    @Published var notchWidth: CGFloat = 0
    @Published var notchHeight: CGFloat = 0

    /// While a focus block runs, the pill grows ears wide enough for it.
    @Published var showsTimerInPill = false
    /// Hours on the clock need a little more room.
    @Published var timerNeedsHours = false

    var hasNotch: Bool { notchWidth > 1 && notchHeight > 1 }

    // MARK: Sizes

    static let openWidth: CGFloat = 520
    /// Room around the panel for its shadow, inside the fixed window.
    static let margin: CGFloat = 36

    /// The row level with the notch. On a notched Mac nothing can be drawn
    /// in the middle of it, so the tabs and actions sit either side.
    var headerHeight: CGFloat { hasNotch ? notchHeight : 32 }

    /// Width of each ear of the closed pill.
    var earWidth: CGFloat {
        guard showsTimerInPill else { return 40 }
        return timerNeedsHours ? 86 : 72
    }

    var closedSize: CGSize {
        hasNotch
            ? CGSize(width: notchWidth + earWidth * 2, height: notchHeight)
            : CGSize(width: showsTimerInPill ? 300 : 252, height: 32)
    }

    func openSize(for tab: Tab) -> CGSize {
        let body: CGFloat
        switch tab {
        case .player:   body = 160
        case .timer:    body = 148
        case .playlist: body = 430
        }
        return CGSize(width: Self.openWidth, height: headerHeight + body)
    }

    /// Wide enough for a title under the notch.
    var peekSize: CGSize {
        hasNotch
            ? CGSize(width: max(closedSize.width, notchWidth + 230), height: notchHeight + 38)
            : CGSize(width: 340, height: 58)
    }

    var currentSize: CGSize {
        if isOpen { return openSize(for: tab) }
        return isPeeking ? peekSize : closedSize
    }

    /// The window is sized once, for the largest thing it will ever show, so
    /// nothing is resized while the panel animates.
    var canvasSize: CGSize {
        let largest = openSize(for: .playlist)
        return CGSize(width: largest.width + Self.margin * 2, height: largest.height + Self.margin)
    }

    // MARK: Shape

    /// The concave flare at the top corners — small on the pill, like the
    /// hardware's, broader on the open panel.
    var topFlare: CGFloat {
        guard hasNotch else { return 0 }
        if isOpen { return 14 }
        return isPeeking ? 9 : 6
    }

    var topRadius: CGFloat { hasNotch ? 0 : (isOpen ? 14 : 10) }

    var bottomRadius: CGFloat {
        if isOpen { return 30 }
        if isPeeking { return 20 }
        return hasNotch ? 11 : 16
    }
}
