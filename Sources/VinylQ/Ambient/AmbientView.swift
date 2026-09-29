import AppKit
import Combine
import SwiftUI

/// Full-screen deck: the clock with the focus timer tucked beneath it, the
/// record in the middle, what's playing on the right.
///
/// The timer is just a timer until you ask for more — its chevron opens the
/// lengths, presets and chime right where it sits.
struct AmbientView: View {

    @ObservedObject var engine: PlayerEngine
    @ObservedObject var settings: Settings
    let study: StudyTimer

    /// Opens with the timer's settings already out.
    var startWithStudy: Bool = false

    @State private var showPlaylist = false
    @State private var timerExpanded = false
    /// Buttons fade when the pointer settles, leaving the record and the time.
    @State private var chromeVisible = true
    @State private var idleWork: DispatchWorkItem?

    var onClose: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let showsLeft = settings.ambientShowClock || settings.ambientShowTimer
            let leftWidth: CGFloat = showsLeft ? 350 : 0
            let rightWidth = min(360, max(270, size.width * 0.24))
            let deckSide = max(240, min(size.height * 0.64, 640, size.width - leftWidth - rightWidth - 190))

            ZStack {
                backdrop

                HStack(alignment: .center, spacing: 0) {
                    if showsLeft {
                        leftColumn
                            .frame(width: leftWidth, alignment: .topLeading)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                    Spacer(minLength: 28)

                    TurntableView(engine: engine, interactive: true)
                        .frame(width: deckSide, height: deckSide)

                    Spacer(minLength: 28)

                    nowPlaying
                        .frame(width: rightWidth, alignment: .leading)
                }
                .padding(.horizontal, 56)
                .padding(.top, 50)
                .padding(.bottom, 86)

                chrome
                    .padding(.horizontal, 44)
                    .padding(.vertical, 36)
                    .frame(width: size.width, height: size.height)
                    .opacity(chromeVisible ? 1 : 0)

                if showPlaylist { playlistOverlay }
            }
            .frame(width: size.width, height: size.height)
            .background(Theme.ink)
            .animation(.easeInOut(duration: 0.45), value: chromeVisible)
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: settings.ambientShowTimer)
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: settings.ambientShowClock)
            .animation(.spring(response: 0.4, dampingFraction: 0.88), value: showPlaylist)
            .onContinuousHover { phase in
                if case .active = phase { wake() }
            }
            .onAppear {
                if startWithStudy { openTimer() }
                wake()
            }
            .onReceive(NotificationCenter.default.publisher(for: .vinylqOpenStudy)) { _ in
                openTimer()
            }
            .onChange(of: timerExpanded) { _, _ in wake() }
            .overlay(escapeHatch)
        }
    }

    // MARK: Backdrop

    private var backdrop: some View {
        ZStack {
            ArtworkBackdrop(image: engine.backdrop, saturation: 1.35, zoom: 1.2)
                .id(engine.artworkID)
                .transition(.opacity)
            Theme.ink.opacity(settings.ambientDim)
            RadialGradient(
                colors: [.clear, Theme.ink.opacity(0.8)],
                center: .center, startRadius: 140, endRadius: 1000
            )
        }
        .animation(.easeInOut(duration: 1.2), value: engine.artworkID)
        .ignoresSafeArea()
        .paperGrain(opacity: settings.showGrain ? 0.05 : 0)
        .allowsHitTesting(false)
    }

    // MARK: Left: clock and timer

    private var leftColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                if settings.ambientShowClock {
                    AmbientClock(settings: settings, size: 84)
                        .transition(.opacity)
                }
                if settings.ambientShowTimer {
                    FocusTimerCompact(timer: study, settings: settings, expanded: $timerExpanded, width: 340)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                }
            }
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Right: what's playing

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SourceChip(kind: engine.activeKind, tint: engine.accent)

                Text(engine.snapshot.track.title)
                    .font(Theme.display(32, .semibold))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(engine.snapshot.track.artist)
                    .font(Theme.display(17, .regular))
                    .foregroundStyle(Theme.creamSoft)
                    .lineLimit(1)

                if !engine.snapshot.track.album.isEmpty {
                    Text(engine.snapshot.track.album)
                        .font(Theme.display(13))
                        .foregroundStyle(Theme.creamFaint)
                        .lineLimit(1)
                }
            }
            .id(engine.snapshot.track.id)
            .transition(.opacity.combined(with: .offset(y: 6)))
            .animation(.easeInOut(duration: 0.45), value: engine.snapshot.track.id)

            TransportBar(engine: engine, scale: 16)
                .opacity(chromeVisible ? 1 : 0.35)
        }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                NotchChip(symbol: settings.ambientShowClock ? "clock.fill" : "clock", title: nil,
                          help: settings.ambientShowClock ? "Hide the clock" : "Show the clock") {
                    settings.ambientShowClock.toggle()
                }
                NotchChip(symbol: "timer", title: nil,
                          help: settings.ambientShowTimer ? "Hide the timer" : "Show the timer") {
                    settings.ambientShowTimer.toggle()
                }
                NotchChip(symbol: "xmark", title: nil, help: "Leave full screen (esc)", action: onClose)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                NotchChip(symbol: "list.bullet", title: showPlaylist ? "Hide Playlist" : "View Playlist") {
                    showPlaylist.toggle()
                    if showPlaylist { engine.refreshLibrary() }
                }
                Spacer(minLength: 0)
                Text("\(Int(settings.rpm.rounded())) RPM")
                    .font(Theme.mono(10, .semibold))
                    .foregroundStyle(Theme.creamFaint)
                    .tracking(1)
            }
        }
    }

    // MARK: Playlist

    private var playlistOverlay: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            PlaylistPanel(engine: engine)
                .frame(width: 400)
                .padding(.top, 30)
                .background(
                    Rectangle()
                        .fill(Theme.ink.opacity(0.95))
                        .overlay(
                            Rectangle().frame(width: 1).foregroundStyle(Theme.hairline),
                            alignment: .leading
                        )
                )
        }
        .ignoresSafeArea()
        .transition(.move(edge: .trailing))
    }

    // MARK: Behaviour

    private func openTimer() {
        settings.ambientShowTimer = true
        timerExpanded = true
        wake()
    }

    private func wake() {
        idleWork?.cancel()
        if !chromeVisible { chromeVisible = true }
        let work = DispatchWorkItem {
            guard !showPlaylist, !timerExpanded else { return }
            chromeVisible = false
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    /// An invisible button so `esc` leaves full screen.
    private var escapeHatch: some View {
        Button(action: onClose) { EmptyView() }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .frame(width: 0, height: 0)
            .opacity(0)
    }
}
