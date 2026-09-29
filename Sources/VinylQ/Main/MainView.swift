import SwiftUI

/// The app window: a rail of rooms on the left, the room itself on the right.
struct MainView: View {

    @ObservedObject var engine: PlayerEngine
    @ObservedObject var settings: Settings
    let study: StudyTimer
    let access: MusicAccess
    let bridge: WidgetBridge?

    var onOpenAmbient: () -> Void
    var onRevealNotch: (NotchState.Tab) -> Void

    enum Room: String, CaseIterable, Identifiable {
        case deck = "Deck"
        case widgets = "Widgets"
        case sources = "Sources"
        case study = "Study"
        case settings = "Settings"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .deck:     return "opticaldisc"
            case .widgets:  return "square.grid.2x2"
            case .sources:  return "music.note.house"
            case .study:    return "timer"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    @State private var room: Room
    @Namespace private var railSelection

    init(
        engine: PlayerEngine,
        settings: Settings,
        study: StudyTimer,
        access: MusicAccess,
        bridge: WidgetBridge?,
        onOpenAmbient: @escaping () -> Void,
        onRevealNotch: @escaping (NotchState.Tab) -> Void,
        initialRoom: Room = .deck
    ) {
        self.engine = engine
        self.settings = settings
        self.study = study
        self.access = access
        self.bridge = bridge
        self.onOpenAmbient = onOpenAmbient
        self.onRevealNotch = onRevealNotch
        _room = State(initialValue: initialRoom)
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Rectangle().fill(Theme.hairline.opacity(0.8)).frame(width: 1)
            content
        }
        .frame(minWidth: 960, minHeight: 660)
        .background(Theme.ink)
        .paperGrain(opacity: settings.showGrain ? 0.035 : 0)
        .onReceive(NotificationCenter.default.publisher(for: .vinylqShowRoom)) { note in
            if let raw = note.object as? String, let target = Room(rawValue: raw) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { room = target }
            }
        }
    }

    // MARK: Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color(hex: 0x0C0B0A))
                    Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    Circle().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5).padding(4)
                    Circle().fill(engine.accent).frame(width: 7, height: 7)
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: -2) {
                    Text("VinylQ")
                        .font(Theme.display(17, .bold))
                        .foregroundStyle(Theme.cream)
                    Text("records for your desktop")
                        .font(Theme.display(9.5))
                        .foregroundStyle(Theme.creamFaint)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ForEach(Room.allCases) { item in
                RailButton(room: item, isSelected: room == item, namespace: railSelection) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { room = item }
                }
            }

            Spacer(minLength: 0)

            nowPlayingFooter
        }
        .frame(width: 212)
        .frame(maxHeight: .infinity)
        .background(Theme.sleeve.opacity(0.6))
    }

    private var nowPlayingFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Theme.hairline.opacity(0.8)).frame(height: 1)
            HStack(spacing: 10) {
                MiniRecord(engine: engine, diameter: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(engine.snapshot.track.title)
                        .font(Theme.display(11.5, .medium))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    Text(engine.snapshot.track.artist)
                        .font(Theme.display(9.5))
                        .foregroundStyle(Theme.creamFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.snapshot.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.creamSoft)
                        .frame(width: 24, height: 24)
                        .contentTransition(.symbolEffect(.replace))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                switch room {
                case .deck:
                    DeckPane(engine: engine, settings: settings, onOpenAmbient: onOpenAmbient)
                case .widgets:
                    WidgetsPane(engine: engine, settings: settings, study: study, bridge: bridge,
                                onRevealNotch: onRevealNotch)
                case .sources:
                    SourcesPane(engine: engine, settings: settings, access: access,
                                library: engine.spotifyLibrary, web: engine.spotifyWeb)
                case .study:
                    StudyPane(study: study, settings: settings, onOpenAmbient: onOpenAmbient,
                              onRevealNotch: { onRevealNotch(.timer) })
                case .settings:
                    SettingsPane(engine: engine, settings: settings)
                }
            }
            .padding(34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(room)
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ink)
    }
}

extension Notification.Name {
    /// Switches the main window to a room, e.g. from a `vinylq://` link.
    static let vinylqShowRoom = Notification.Name("vinylq.showRoom")
}

// MARK: - Rail button

private struct RailButton: View {
    var room: MainView.Room
    var isSelected: Bool
    var namespace: Namespace.ID
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: room.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                Text(room.rawValue)
                    .font(Theme.display(13, isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Theme.cream : (hovering ? Theme.cream.opacity(0.85) : Theme.creamSoft))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.085))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Theme.brass)
                                .frame(width: 2.5, height: 15)
                                .offset(x: -5)
                        }
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Shared section chrome

/// A titled block, used by every pane so the app reads as one document.
struct PaneSection<Content: View>: View {
    var title: String
    var caption: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.display(20, .semibold))
                    .foregroundStyle(Theme.cream)
                if let caption {
                    Text(caption)
                        .font(Theme.display(12))
                        .foregroundStyle(Theme.creamFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A labelled row for settings-style content.
struct SettingRow<Control: View>: View {
    var title: String
    var caption: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.display(12.5, .medium))
                    .foregroundStyle(Theme.cream)
                if let caption {
                    Text(caption)
                        .font(Theme.display(11))
                        .foregroundStyle(Theme.creamFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 2)
    }
}
