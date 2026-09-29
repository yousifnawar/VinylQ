import SwiftUI

/// A complete, live deck: platter, record and tonearm.
///
/// One view serves every surface. It's assembled from layers that change at
/// different speeds (see `PlatterLayers.swift`): the slipmat, disc and grooves
/// are flattened into a texture once; inside the animation timeline only the
/// label, the sheen and the arm move, and they move as transforms of cached
/// drawings. So the record turns at the display's full refresh rate — 120 Hz
/// on a ProMotion screen — for very little work, even though the source
/// behind it is only polled once a second.
struct TurntableView: View {

    @ObservedObject var engine: PlayerEngine
    var interactive: Bool = true
    /// Drops fine detail and text for small sizes.
    var compact: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let geometry = DeckGeometry(side: side)

            ZStack {
                PlatterBase(geometry: geometry, compact: compact)
                    .equatable()
                    .drawingGroup()

                TimelineView(.animation(minimumInterval: nil, paused: !shouldAnimate)) { timeline in
                    let date = timeline.date
                    let progress = engine.progress(at: date)
                    let angle = engine.platterAngle(at: date)
                    let parked = engine.snapshot.track.isSilence

                    ZStack {
                        PlayedGrooves(geometry: geometry, compact: compact,
                                      step: PlayedGrooves.step(for: progress))
                            .equatable()

                        RecordSheen(geometry: geometry)
                            .equatable()
                            .drawingGroup()
                            .rotationEffect(.degrees(angle))
                            .position(geometry.center)

                        RecordLabel(
                            geometry: geometry,
                            artwork: engine.artwork,
                            accent: engine.accent,
                            title: engine.snapshot.track.title,
                            subtitle: engine.snapshot.track.artist,
                            compact: compact
                        )
                        .equatable()
                        .drawingGroup()
                        .rotationEffect(.degrees(angle))
                        .position(geometry.center)

                        Spindle(geometry: geometry)
                            .equatable()
                            .position(geometry.center)

                        Tonearm(
                            geometry: geometry,
                            angle: geometry.armAngle(progress: progress, parked: parked),
                            isScrubbing: engine.scrubProgress != nil,
                            accent: engine.accent,
                            interactive: interactive && !parked,
                            rasterize: true,
                            onScrubBegan: { engine.beginScrub(at: $0) },
                            onScrubChanged: { engine.updateScrub(to: $0) },
                            onScrubEnded: { engine.endScrub() }
                        )
                    }
                    .frame(width: side, height: side)
                }
            }
            .frame(width: side, height: side)
            .coordinateSpace(.named(DeckSpace.name))
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Keep the timeline idle when nothing moves, so a parked deck costs nothing.
    private var shouldAnimate: Bool {
        engine.snapshot.isPlaying || engine.scrubProgress != nil
    }
}
