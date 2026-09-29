import AppKit
import SwiftUI

/// A small, still record: black vinyl, a few grooves, the cover as its label.
///
/// Cheaper than the full `VinylPlatter` and drawn to read at thumbnail sizes —
/// widgets, playlist rows, the notch pill.
struct VinylDisc: View {
    var artwork: NSImage?
    var accent: Color
    /// Label size as a fraction of the disc.
    var labelFraction: CGFloat = 0.38
    var grooves: Int = 7

    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0x1D1B1A), Color(hex: 0x0A0909), Color(hex: 0x141312), Color(hex: 0x050505)],
                            center: .center, startRadius: d * labelFraction * 0.5, endRadius: d * 0.5
                        )
                    )

                ForEach(0..<grooves, id: \.self) { i in
                    Circle()
                        .strokeBorder(Color.white.opacity(i % 3 == 0 ? 0.11 : 0.05), lineWidth: max(0.4, d * 0.004))
                        .padding(d * (0.035 + CGFloat(i) * (0.5 - labelFraction * 0.5 - 0.06) / CGFloat(max(grooves, 1))))
                }

                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: .white.opacity(0.0), location: 0.0),
                                .init(color: .white.opacity(0.10), location: 0.12),
                                .init(color: .white.opacity(0.0), location: 0.27),
                                .init(color: .white.opacity(0.0), location: 0.52),
                                .init(color: .white.opacity(0.07), location: 0.63),
                                .init(color: .white.opacity(0.0), location: 0.8)
                            ]),
                            center: .center
                        )
                    )

                label
                    .frame(width: d * labelFraction, height: d * labelFraction)

                Circle()
                    .fill(Theme.ink)
                    .frame(width: max(2, d * 0.03), height: max(2, d * 0.03))

                Circle().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
            }
            .frame(width: d, height: d)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var label: some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle().fill(accent)
                Circle().fill(Theme.rust.opacity(0.35))
            }
            Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1)
        }
        .clipShape(Circle())
    }
}

/// An album sleeve: the cover, a soft shadow, a whisper of an edge.
struct AlbumSleeve: View {
    var artwork: NSImage?
    var accent: Color
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                // No cover: a printed sleeve in the record's colour.
                LinearGradient(colors: [accent, accent.opacity(0.55), Color(hex: 0x2A1C12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                GeometryReader { proxy in
                    let d = min(proxy.size.width, proxy.size.height)
                    ZStack {
                        ForEach(0..<4, id: \.self) { i in
                            Circle()
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: max(1, d * 0.02))
                                .frame(width: d * (0.3 + CGFloat(i) * 0.18), height: d * (0.3 + CGFloat(i) * 0.18))
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 6, x: 2, y: 3)
    }
}

/// The sleeve with its record half slid out — the classic way to show that
/// something is on the turntable.
struct SleeveAndRecord: View {
    var artwork: NSImage?
    var accent: Color
    /// How far the record slides out, as a fraction of the sleeve.
    var peek: CGFloat = 0.36

    var body: some View {
        GeometryReader { proxy in
            // Fit a sleeve plus its peeking record into whatever we're given.
            let sleeve = min(proxy.size.height, proxy.size.width / (1 + peek))
            ZStack(alignment: .leading) {
                VinylDisc(artwork: artwork, accent: accent)
                    .frame(width: sleeve * 0.94, height: sleeve * 0.94)
                    .offset(x: sleeve * peek + sleeve * 0.03)
                AlbumSleeve(artwork: artwork, accent: accent, cornerRadius: max(4, sleeve * 0.06))
                    .frame(width: sleeve, height: sleeve)
            }
            .frame(width: sleeve * (1 + peek), height: sleeve, alignment: .leading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
    }
}
