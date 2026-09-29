import AppKit
import SwiftUI

/// The visual language for VinylQ: warm espresso paper, cream ink, amber brass.
///
/// Shared by the app and its widgets, so a widget on the desktop is drawn with
/// exactly the same palette as the deck it mirrors.
enum Theme {

    // MARK: Palette

    static let ink        = Color(hex: 0x100E0C)   // deepest background
    static let sleeve     = Color(hex: 0x17140F)   // panel background
    static let sleeveHigh = Color(hex: 0x211C16)   // raised panel
    static let hairline   = Color(hex: 0x3A3129)   // borders

    static let cream      = Color(hex: 0xF3E9DA)   // primary text
    static let creamSoft  = Color(hex: 0xB9AC9A)   // secondary text
    static let creamFaint = Color(hex: 0x7A6E60)   // tertiary text

    static let brass      = Color(hex: 0xE0A458)   // accent / active
    static let rust       = Color(hex: 0xC0563F)   // record label
    static let moss       = Color(hex: 0x8FA36A)   // study / focus

    /// The notch is true black. Anything lighter shows up as a grey band
    /// beside the hardware, which is exactly what the panel must not do.
    static let notch      = Color.black

    /// Frosted surfaces on dark backgrounds.
    static let glass       = Color.white.opacity(0.055)
    static let glassRaised = Color.white.opacity(0.10)
    static let glassStroke = Color.white.opacity(0.085)

    // MARK: Type

    /// Rounded system face — reads as "Apple, but soft".
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Monospaced digits for clocks, timers and elapsed time.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: Materials

    /// The signature surface: a dark sheet with a warm top-light.
    static func sleeveGradient(highlight: Bool = false) -> LinearGradient {
        LinearGradient(
            colors: highlight ? [sleeveHigh, sleeve] : [sleeve.opacity(0.98), ink],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Brushed-metal sheen used on the tonearm and hardware.
    static let brushed = LinearGradient(
        colors: [
            Color(hex: 0xE8E2D8), Color(hex: 0x9C958A),
            Color(hex: 0xD6CFC3), Color(hex: 0x6E675E)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Shared modifiers

/// A card that matches the app's panel treatment at any corner radius.
struct SleeveCard: ViewModifier {
    var radius: CGFloat = 18
    var highlight: Bool = false
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.sleeveGradient(highlight: highlight))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(0.7), lineWidth: 1)
            )
    }
}

/// A frosted card for surfaces that float over artwork (the ambient deck).
struct GlassCard: ViewModifier {
    var radius: CGFloat = 20
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.glass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.glassStroke, lineWidth: 0.8)
            )
    }
}

extension View {
    func sleeveCard(radius: CGFloat = 18, highlight: Bool = false, padding: CGFloat = 16) -> some View {
        modifier(SleeveCard(radius: radius, highlight: highlight, padding: padding))
    }

    func glassCard(radius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        modifier(GlassCard(radius: radius, padding: padding))
    }

    /// Fine paper grain. Keeps large dark surfaces from looking like flat black.
    func paperGrain(opacity: Double = 0.045) -> some View {
        overlay(GrainOverlay(opacity: opacity).allowsHitTesting(false))
    }
}

/// Procedural film grain, rendered once into a tile.
struct GrainOverlay: View {
    var opacity: Double

    var body: some View {
        if opacity > 0 {
            Image(nsImage: GrainOverlay.tile)
                .resizable(resizingMode: .tile)
                .opacity(opacity)
                .blendMode(.overlay)
        }
    }

    private static let tile: NSImage = {
        let side = 96
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        for x in 0..<side {
            for y in 0..<side {
                NSColor(white: CGFloat.random(in: 0...1), alpha: 1).setFill()
                NSRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1).fill()
            }
        }
        image.unlockFocus()
        return image
    }()
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Double {
    /// `213.4` -> `"3:33"`, `-1` -> `"--:--"`
    var clockString: String {
        guard isFinite, self >= 0 else { return "--:--" }
        let total = Int(rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Like `clockString`, but rounds up — a countdown should read `0:01`
    /// until the very last moment, never `0:00` with time still on it.
    var countdownString: String {
        guard isFinite else { return "--:--" }
        return Double(max(0, ceil(self - 0.001))).clockString
    }
}
