import SwiftUI
import WidgetKit

/// VinylQ's real desktop widgets, shown live, with how to add them.
///
/// The previews here are the very views the widget extension draws — the
/// designs live in `Shared/WidgetDesigns.swift` and are compiled into both —
/// so what you see is what goes on your desktop. The buttons work here too.
struct WidgetsPane: View {

    @ObservedObject var engine: PlayerEngine
    @ObservedObject var settings: Settings
    @ObservedObject var study: StudyTimer
    let bridge: WidgetBridge?
    var onRevealNotch: (NotchState.Tab) -> Void

    @State private var installed: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            PaneSection(
                title: "Widgets",
                caption: "Real macOS widgets for your desktop and Notification Center. They show what's on the deck and the focus timer, and their buttons work without opening VinylQ."
            ) {
                howToAdd
            }

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let state = WidgetState.live(engine: engine, study: study, settings: settings, at: timeline.date)
                VStack(alignment: .leading, spacing: 32) {
                    PaneSection(title: "Now Playing", caption: "The record on the deck, with play, pause and skip. Small, medium and large.") {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 20) {
                                nowPlaying(.systemLarge, state: state, date: timeline.date)
                                VStack(alignment: .leading, spacing: 20) {
                                    nowPlaying(.systemMedium, state: state, date: timeline.date)
                                    nowPlaying(.systemSmall, state: state, date: timeline.date)
                                }
                            }
                            VStack(alignment: .leading, spacing: 20) {
                                HStack(alignment: .top, spacing: 20) {
                                    nowPlaying(.systemSmall, state: state, date: timeline.date)
                                    nowPlaying(.systemMedium, state: state, date: timeline.date)
                                }
                                nowPlaying(.systemLarge, state: state, date: timeline.date)
                            }
                        }
                    }

                    PaneSection(title: "Focus Timer", caption: "Start, pause and skip blocks from the desktop. The countdown ticks on its own.") {
                        HStack(alignment: .top, spacing: 20) {
                            focus(.systemSmall, state: state, date: timeline.date)
                            focus(.systemMedium, state: state, date: timeline.date)
                        }
                    }
                }
            }
            .environment(\.vinylqDrawsOwnProgress, true)
            .environment(\.vinylqCommandHandler) { command in
                if let bridge {
                    bridge.perform(command)
                } else {
                    WidgetBridge.performDirectly(command, engine: engine, study: study)
                }
            }

            PaneSection(title: "In the notch", caption: "VinylQ also lives in the notch: hover it for the deck, the timer and your playlists.") {
                HStack(spacing: 8) {
                    NotchChip(symbol: "opticaldisc", title: "Show the player") { onRevealNotch(.player) }
                    NotchChip(symbol: "timer", title: "Show the timer") { onRevealNotch(.timer) }
                    NotchChip(symbol: "list.bullet", title: "Show playlists") { onRevealNotch(.playlist) }
                }
            }
        }
        .onAppear(perform: refreshCount)
    }

    // MARK: How to add

    private var howToAdd: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                step(1, "Right-click an empty part of your desktop and choose **Edit Widgets…**")
                step(2, "Search for **VinylQ**.")
                step(3, "Drag **Now Playing** or **Focus Timer** onto your desktop — or into Notification Center.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill((installed ?? 0) > 0 ? Theme.moss : Theme.creamFaint)
                        .frame(width: 6, height: 6)
                    Text(installedText)
                        .font(Theme.display(11.5, .medium))
                        .foregroundStyle(Theme.creamSoft)
                }
                NotchChip(symbol: "arrow.clockwise", title: "Refresh widgets") {
                    bridge?.reloadAll()
                    refreshCount()
                }
            }
        }
        .sleeveCard(radius: 18, highlight: true, padding: 18)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(Theme.mono(10.5, .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 19, height: 19)
                .background(Circle().fill(Theme.brass))
            Text(text)
                .font(Theme.display(12.5))
                .foregroundStyle(Theme.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var installedText: String {
        switch installed {
        case nil:  return "Checking your desktop…"
        case 0:    return "No VinylQ widgets added yet"
        case 1:    return "1 VinylQ widget on your desktop"
        case let n?: return "\(n) VinylQ widgets on your desktop"
        }
    }

    private func refreshCount() {
        bridge?.countInstalled { installed = $0 }
        if bridge == nil { installed = 0 }
    }

    // MARK: Previews

    private func nowPlaying(_ family: WidgetFamily, state: WidgetState, date: Date) -> some View {
        WidgetPreviewFrame(family: family) {
            NowPlayingWidgetView(state: state, artwork: engine.artwork, family: family, date: date)
        } background: {
            NowPlayingWidgetBackground(state: state, artwork: engine.artwork)
        }
    }

    private func focus(_ family: WidgetFamily, state: WidgetState, date: Date) -> some View {
        WidgetPreviewFrame(family: family) {
            FocusWidgetView(state: state, family: family, date: date)
        } background: {
            FocusWidgetBackground(state: state)
        }
    }
}

/// A widget-shaped tile at the size macOS gives each family.
private struct WidgetPreviewFrame<Content: View, Background: View>: View {
    var family: WidgetFamily
    @ViewBuilder var content: () -> Content
    @ViewBuilder var background: () -> Background

    var body: some View {
        let size = Self.size(for: family)
        content()
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(background())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    static func size(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall:  return CGSize(width: 170, height: 170)
        case .systemLarge:  return CGSize(width: 364, height: 382)
        default:            return CGSize(width: 364, height: 170)
        }
    }
}

// MARK: - The app's side of the widgets' buttons

/// In the app, a widget button just does the thing. (The widget extension
/// defines its own `VinylQActionButton`, which sends an App Intent instead.)
struct VinylQActionButton<Label: View>: View {
    let action: VinylQCommand
    @ViewBuilder let label: () -> Label

    @Environment(\.vinylqCommandHandler) private var handler

    var body: some View {
        Button { handler(action) } label: { label() }
            .buttonStyle(PressableStyle())
    }
}

private struct VinylQCommandHandlerKey: EnvironmentKey {
    static let defaultValue: (VinylQCommand) -> Void = { _ in }
}

extension EnvironmentValues {
    var vinylqCommandHandler: (VinylQCommand) -> Void {
        get { self[VinylQCommandHandlerKey.self] }
        set { self[VinylQCommandHandlerKey.self] = newValue }
    }
}

// MARK: - Live state

extension WidgetState {
    /// What the widgets would show right now, built straight from the app.
    @MainActor
    static func live(engine: PlayerEngine, study: StudyTimer, settings: Settings,
                     at date: Date = Date(), appRunning: Bool = true, artworkFile: String? = nil) -> WidgetState {
        let snapshot = engine.snapshot
        let track = snapshot.track
        return WidgetState(
            writtenAt: date,
            appRunning: appRunning,
            nowPlaying: NowPlaying(
                track: Track(
                    id: track.id, title: track.title, artist: track.artist, album: track.album,
                    source: snapshot.source.rawValue, sourceSymbol: snapshot.source.symbol,
                    duration: track.duration, isSilence: track.isSilence
                ),
                isPlaying: snapshot.isPlaying,
                position: engine.position(at: date),
                accent: engine.accentRGB,
                artworkFile: artworkFile
            ),
            focus: Focus(
                phase: Phase(rawValue: study.phase.rawValue) ?? .idle,
                isRunning: study.isRunning,
                endDate: study.endDate,
                remaining: study.remaining,
                phaseLength: study.phaseLength,
                blocksDone: study.blocksDone,
                blocksPerLongBreak: settings.cyclesUntilLongBreak,
                focusMinutes: settings.focusMinutes,
                breakMinutes: settings.breakMinutes,
                longBreakMinutes: settings.longBreakMinutes
            )
        )
    }
}
