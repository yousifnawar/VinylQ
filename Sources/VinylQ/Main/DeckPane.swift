import AppKit
import SwiftUI

/// The home room: the record, full size, with everything you'd reach for.
struct DeckPane: View {

    @ObservedObject var engine: PlayerEngine
    @ObservedObject var settings: Settings
    var onOpenAmbient: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 36) {
            VStack(alignment: .leading, spacing: 12) {
                TurntableView(engine: engine, interactive: true)
                    .frame(width: 420, height: 420)

                Text("Drag the stylus to move through the track — the needle scrubs the real player, not a copy of it.")
                    .font(Theme.display(11.5))
                    .foregroundStyle(Theme.creamFaint)
                    .frame(width: 420, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 20) {
                nowPlaying
                TransportBar(engine: engine, scale: 15, showsVolume: true)
                speedPicker
                actions
                if engine.automationBlocked { permissionNote }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Now playing

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 7) {
            SourceChip(kind: engine.activeKind, tint: engine.accent)

            Text(engine.snapshot.track.title)
                .font(Theme.display(28, .semibold))
                .foregroundStyle(Theme.cream)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(engine.snapshot.track.artist)
                .font(Theme.display(15))
                .foregroundStyle(Theme.creamSoft)
                .lineLimit(1)

            if !engine.snapshot.track.album.isEmpty {
                Text(engine.snapshot.track.album)
                    .font(Theme.display(12))
                    .foregroundStyle(Theme.creamFaint)
                    .lineLimit(1)
            }
        }
        .id(engine.snapshot.track.id)
        .transition(.opacity.combined(with: .offset(y: 5)))
        .animation(.easeInOut(duration: 0.4), value: engine.snapshot.track.id)
    }

    // MARK: Speed

    private var speedPicker: some View {
        HStack(spacing: 8) {
            Text("SPEED")
                .font(Theme.mono(9, .semibold))
                .tracking(1)
                .foregroundStyle(Theme.creamFaint)

            ForEach([33.333, 45.0, 78.0], id: \.self) { rpm in
                let selected = abs(settings.rpm - rpm) < 0.01
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { settings.rpm = rpm }
                } label: {
                    Text(rpm == 33.333 ? "33⅓" : "\(Int(rpm))")
                        .font(Theme.mono(11, .semibold))
                        .foregroundStyle(selected ? Theme.ink : Theme.creamSoft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(selected ? AnyShapeStyle(Theme.brass) : AnyShapeStyle(Color.white.opacity(0.07)))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }

            Text("how fast the record turns")
                .font(Theme.display(10))
                .foregroundStyle(Theme.creamFaint)
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            NotchChip(symbol: "arrow.up.left.and.arrow.down.right", title: "Full Screen",
                      action: onOpenAmbient)
            NotchChip(symbol: "arrow.clockwise", title: "Reload Library") {
                engine.refreshLibrary()
                engine.local.rescan()
            }
        }
    }

    private var permissionNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.rust)
            VStack(alignment: .leading, spacing: 3) {
                Text("VinylQ needs permission to control your music app")
                    .font(Theme.display(12, .semibold))
                    .foregroundStyle(Theme.cream)
                Text("Allow VinylQ under Privacy & Security → Automation, then play something again.")
                    .font(Theme.display(11))
                    .foregroundStyle(Theme.creamSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy & Security") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(Theme.display(11, .medium))
            }
        }
        .sleeveCard(radius: 14, highlight: true, padding: 13)
    }
}
