import SwiftUI

/// The notch: a pill at rest, a small deck when you hover, with a timer and
/// your playlists a tab away.
///
/// One black shape does all of it. The content inside is clipped to that
/// shape, so while it springs open nothing spills past its edges.
struct NotchView: View {

    @ObservedObject var engine: PlayerEngine
    @ObservedObject var state: NotchState
    @ObservedObject var settings: Settings
    let study: StudyTimer

    var onSelectTab: (NotchState.Tab) -> Void
    var onOpenAmbient: () -> Void
    var onOpenApp: () -> Void

    var body: some View {
        let size = state.currentSize
        let shape = NotchShape(topFlare: state.topFlare, topRadius: state.topRadius,
                               bottomRadius: state.bottomRadius)

        ZStack(alignment: .top) {
            shape
                .fill(Theme.notch)
                .frame(width: size.width, height: size.height)
                // Depth only once it's out of the notch — a shadow on the
                // closed pill would smudge grey onto the menu bar beside it.
                .shadow(color: .black.opacity(state.isOpen ? 0.55 : 0),
                        radius: state.isOpen ? 16 : 0, y: state.isOpen ? 8 : 0)

            ZStack(alignment: .top) {
                if state.isOpen {
                    NotchOpenContent(
                        engine: engine, state: state, settings: settings, study: study,
                        onSelectTab: onSelectTab, onOpenAmbient: onOpenAmbient, onOpenApp: onOpenApp
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.95, anchor: .top))
                                .animation(.spring(response: 0.42, dampingFraction: 0.88).delay(0.06)),
                            removal: .opacity.animation(.easeOut(duration: 0.1))
                        )
                    )
                } else {
                    NotchClosedContent(engine: engine, state: state, study: study)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.14)),
                                removal: .opacity.animation(.easeOut(duration: 0.08))
                            )
                        )
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Closed

/// The pill: a spinning label on one side, four bars — or the focus timer —
/// on the other.
private struct NotchClosedContent: View {
    @ObservedObject var engine: PlayerEngine
    @ObservedObject var state: NotchState
    let study: StudyTimer

    var body: some View {
        if state.hasNotch {
            let disc = min(state.notchHeight - 12, 20)
            let ear = (state.currentSize.width - state.notchWidth) / 2
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Each ear's content hugs the notch, so it stays put while
                    // the pill widens around it.
                    HStack(spacing: 7) {
                        MiniRecord(engine: engine, diameter: disc)
                        if state.showsTimerInPill {
                            LiveBars(isPlaying: engine.snapshot.isPlaying, tint: engine.accent, height: disc * 0.5)
                        }
                    }
                    .padding(.trailing, earInset)
                    .frame(width: ear, alignment: .trailing)

                    Color.clear.frame(width: state.notchWidth)

                    Group {
                        if state.showsTimerInPill {
                            PillTimer(timer: study)
                        } else {
                            LiveBars(isPlaying: engine.snapshot.isPlaying, tint: engine.accent, height: disc * 0.55)
                        }
                    }
                    .padding(.leading, earInset)
                    .frame(width: ear, alignment: .leading)
                }
                .frame(height: state.notchHeight)

                if state.isPeeking {
                    SongPeek(engine: engine)
                        .frame(height: state.peekSize.height - state.notchHeight)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }
            }
            .frame(width: state.currentSize.width, alignment: .top)
        } else {
            HStack(spacing: 8) {
                MiniRecord(engine: engine, diameter: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(engine.snapshot.track.isSilence ? "VinylQ" : engine.snapshot.track.title)
                        .font(Theme.display(11.5, .medium))
                        .foregroundStyle(state.isPeeking ? Theme.cream : Theme.creamSoft)
                        .lineLimit(1)
                    if state.isPeeking {
                        Text(engine.snapshot.track.artist)
                            .font(Theme.display(10.5))
                            .foregroundStyle(Theme.creamSoft)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 4)
                if state.showsTimerInPill {
                    PillTimer(timer: study)
                } else {
                    LiveBars(isPlaying: engine.snapshot.isPlaying, tint: engine.accent, height: 11)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: state.currentSize.height)
        }
    }

    /// Distance between an ear's content and the notch.
    private var earInset: CGFloat { state.showsTimerInPill ? 10 : 11 }
}

/// The new song, named under the notch for a moment.
private struct SongPeek: View {
    @ObservedObject var engine: PlayerEngine

    var body: some View {
        HStack(spacing: 7) {
            Text(engine.snapshot.track.title)
                .font(Theme.display(12.5, .semibold))
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
                .layoutPriority(1)
            if !engine.snapshot.track.artist.isEmpty {
                Text("·")
                    .foregroundStyle(Theme.creamFaint)
                Text(engine.snapshot.track.artist)
                    .font(Theme.display(12, .medium))
                    .foregroundStyle(Theme.creamSoft)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }
}

/// The countdown that rides in the pill: a thin ring and the minutes left.
private struct PillTimer: View {
    @ObservedObject var timer: StudyTimer

    var body: some View {
        HStack(spacing: 5) {
            TimerRing(progress: timer.progress, tint: timer.phase.tint, lineWidth: 2)
                .frame(width: 12, height: 12)
            Text(timer.remainingLabel)
                .font(Theme.mono(11.5, .semibold))
                .monospacedDigit()
                .foregroundStyle(timer.isRunning ? Theme.cream : Theme.creamFaint)
                .contentTransition(.numericText(countsDown: true))
                .lineLimit(1)
                .fixedSize()
        }
        .animation(.easeOut(duration: 0.25), value: timer.secondsLeft)
    }
}

// MARK: - Open

private struct NotchOpenContent: View {
    @ObservedObject var engine: PlayerEngine
    @ObservedObject var state: NotchState
    @ObservedObject var settings: Settings
    let study: StudyTimer

    var onSelectTab: (NotchState.Tab) -> Void
    var onOpenAmbient: () -> Void
    var onOpenApp: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: state.headerHeight)

            ZStack(alignment: .top) {
                switch state.tab {
                case .player:
                    NotchPlayerTab(engine: engine, study: study, onShowTimer: { onSelectTab(.timer) })
                        .transition(.opacity)
                case .timer:
                    NotchTimerTab(timer: study, settings: settings)
                        .transition(.opacity)
                case .playlist:
                    NotchPlaylistTab(engine: engine)
                        .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: NotchState.openWidth)
    }

    /// Tabs to the left of the notch, actions to the right — the notch
    /// itself sits between them, where nothing can be drawn.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(NotchState.Tab.allCases) { tab in
                    NotchTabButton(tab: tab, isSelected: state.tab == tab) { onSelectTab(tab) }
                }
            }
            .padding(.leading, 26)

            Spacer(minLength: state.hasNotch ? state.notchWidth : 12)

            HStack(spacing: 3) {
                NotchIconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Full-screen deck",
                                action: onOpenAmbient)
                NotchIconButton(symbol: "gearshape", help: "Open VinylQ", action: onOpenApp)
            }
            .padding(.trailing, 26)
        }
        .padding(.top, state.hasNotch ? 0 : 4)
    }
}

// MARK: Player tab

private struct NotchPlayerTab: View {
    @ObservedObject var engine: PlayerEngine
    let study: StudyTimer
    var onShowTimer: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            TurntableView(engine: engine, interactive: true, compact: true)
                .frame(width: 138, height: 138)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    SourceChip(kind: engine.activeKind, tint: engine.accent)
                    TimerChip(timer: study, action: onShowTimer)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.snapshot.track.title)
                        .font(Theme.display(15, .semibold))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    Text(engine.snapshot.track.artist)
                        .font(Theme.display(12))
                        .foregroundStyle(Theme.creamSoft)
                        .lineLimit(1)
                }
                .animation(.easeInOut(duration: 0.3), value: engine.snapshot.track.id)

                TransportBar(engine: engine, scale: 12, showsTime: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 18)
    }
}

/// Where the music is coming from, in the record's colour.
struct SourceChip: View {
    var kind: SourceKind
    var tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind.symbol)
                .font(.system(size: 8, weight: .bold))
            Text(kind.rawValue.uppercased())
                .font(Theme.mono(8.5, .semibold))
                .tracking(0.7)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// The running timer, as a chip beside the source. Tap to see it.
private struct TimerChip: View {
    @ObservedObject var timer: StudyTimer
    var action: () -> Void

    var body: some View {
        if timer.phase != .idle {
            Button(action: action) {
                HStack(spacing: 4) {
                    TimerRing(progress: timer.progress, tint: timer.phase.tint, lineWidth: 1.6)
                        .frame(width: 9, height: 9)
                    Text(timer.remainingLabel)
                        .font(Theme.mono(8.5, .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(timer.phase.tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(timer.phase.tint.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help("\(timer.phase.title) — open the timer")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}

// MARK: Timer tab

private struct NotchTimerTab: View {
    @ObservedObject var timer: StudyTimer
    @ObservedObject var settings: Settings

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            ZStack {
                TimerRing(progress: timer.progress, tint: timer.phase.tint, lineWidth: 7)
                VStack(spacing: 1) {
                    Text(timer.remainingLabel)
                        .font(Theme.mono(timer.remaining >= 3600 ? 20 : 25, .light))
                        .monospacedDigit()
                        .foregroundStyle(Theme.cream)
                        .contentTransition(.numericText(countsDown: true))
                    Text(timer.phase == .idle ? "minutes" : (timer.isRunning ? "remaining" : "paused"))
                        .font(Theme.display(9.5, .medium))
                        .foregroundStyle(Theme.creamFaint)
                }
            }
            .frame(width: 118, height: 118)
            .animation(.easeOut(duration: 0.25), value: timer.secondsLeft)

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(timer.phase.tint)
                        .frame(width: 6, height: 6)
                        .opacity(timer.isRunning ? 1 : 0.4)
                    Text(timer.phase.title.uppercased())
                        .font(Theme.mono(9.5, .semibold))
                        .tracking(1.2)
                        .foregroundStyle(timer.phase.tint)
                    Spacer(minLength: 4)
                    Text(timer.cycleCaption)
                        .font(Theme.display(10.5, .medium))
                        .foregroundStyle(Theme.creamFaint)
                        .lineLimit(1)
                }

                TimerControls(timer: timer, size: .regular)

                HStack(spacing: 6) {
                    ForEach(StudyTimer.Preset.all) { preset in
                        PresetChip(preset: preset, isSelected: timer.currentPreset == preset) {
                            timer.apply(preset)
                        }
                    }
                    Spacer(minLength: 0)
                    ChimeToggle(settings: settings)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 28)
        .padding(.top, 6)
        .padding(.bottom, 20)
    }
}

// MARK: Playlist tab

private struct NotchPlaylistTab: View {
    @ObservedObject var engine: PlayerEngine

    var body: some View {
        VStack(spacing: 0) {
            // A slim now-playing strip so you never lose the record.
            HStack(spacing: 10) {
                MiniRecord(engine: engine, diameter: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.snapshot.track.title)
                        .font(Theme.display(12.5, .semibold))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    Text(engine.snapshot.track.artist)
                        .font(Theme.display(10.5))
                        .foregroundStyle(Theme.creamFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                DeckButton(symbol: "backward.fill", size: 9) { engine.previous() }
                DeckButton(
                    symbol: engine.snapshot.isPlaying ? "pause.fill" : "play.fill",
                    size: 11, prominent: true, tint: engine.accent
                ) { engine.togglePlayPause() }
                DeckButton(symbol: "forward.fill", size: 9) { engine.next() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 10)

            PlaylistPanel(engine: engine, compact: true)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
        }
    }
}

// MARK: - Header buttons

private struct NotchTabButton: View {
    var tab: NotchState.Tab
    var isSelected: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.cream : Color.white.opacity(hovering ? 0.78 : 0.46))
                .frame(width: 30, height: 22)
                .background(
                    Capsule().fill(Color.white.opacity(isSelected ? 0.14 : (hovering ? 0.07 : 0)))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .help(tab.title)
    }
}

private struct NotchIconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(hovering ? 0.85 : 0.5))
                .frame(width: 28, height: 22)
                .background(Capsule().fill(Color.white.opacity(hovering ? 0.08 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(help)
    }
}

// MARK: - Chip

/// A small capsule action, icon-only or icon-with-label.
struct NotchChip: View {
    var symbol: String
    var title: String?
    var help: String?
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                if let title {
                    Text(title).font(Theme.display(11, .medium))
                }
            }
            .foregroundStyle(hovering ? Theme.cream : Theme.creamSoft)
            .padding(.horizontal, title == nil ? 8 : 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.white.opacity(hovering ? 0.12 : 0.06))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 0.6))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(help ?? title ?? "")
    }
}
