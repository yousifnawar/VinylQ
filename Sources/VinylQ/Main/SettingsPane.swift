import AppKit
import ServiceManagement
import SwiftUI

/// Everything else, grouped so it reads top to bottom.
struct SettingsPane: View {

    @ObservedObject var engine: PlayerEngine
    @ObservedObject var settings: Settings

    @State private var loginItemEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginItemProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PaneSection(title: "Notch", caption: "The pill in your notch.") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingRow(title: "Show the notch player") {
                        toggle($settings.notchEnabled)
                    }
                    SettingRow(title: "Show each new song",
                               caption: "When a song starts, the notch drops down for a moment with its name.") {
                        toggle($settings.notchPeekOnNewSong)
                    }
                    SettingRow(title: "Show the timer in the pill",
                               caption: "While a focus block runs, its countdown sits beside the notch.") {
                        toggle($settings.notchShowsTimer)
                    }
                    SettingRow(title: "Keep it on every Space",
                               caption: "Off means it only follows the Space you're working in.") {
                        toggle($settings.notchOnAllSpaces)
                    }
                }
                .sleeveCard(radius: 18, padding: 18)
            }

            PaneSection(title: "Full-screen deck", caption: "The ambient mode, ⌘⇧F.") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingRow(title: "Show the clock") {
                        toggle($settings.ambientShowClock)
                    }
                    SettingRow(title: "Show the timer under the clock") {
                        toggle($settings.ambientShowTimer)
                    }
                    SettingRow(title: "24-hour time") {
                        toggle($settings.ambientTwentyFourHour)
                    }
                    SettingRow(title: "Show seconds",
                               caption: "Off keeps the clock still, which is calmer to work beside.") {
                        toggle($settings.ambientShowSeconds)
                    }
                    SettingRow(title: "Backdrop dimming",
                               caption: "How far the cover art fades behind the record.") {
                        Slider(value: $settings.ambientDim, in: 0.4...0.98)
                            .frame(width: 160)
                            .controlSize(.small)
                            .tint(Theme.brass)
                    }
                }
                .sleeveCard(radius: 18, padding: 18)
            }

            PaneSection(title: "Look", caption: nil) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingRow(title: "Paper grain",
                               caption: "A fine texture over dark surfaces.") {
                        toggle($settings.showGrain)
                    }
                    SettingRow(title: "Take colour from the cover",
                               caption: "The label, needle and accents pick up the record's tone.") {
                        toggle($settings.tintFromArtwork)
                    }
                }
                .sleeveCard(radius: 18, padding: 18)
            }

            PaneSection(title: "Startup", caption: nil) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingRow(title: "Open VinylQ at login") {
                        Toggle("", isOn: Binding(
                            get: { loginItemEnabled },
                            set: { setLoginItem($0) }
                        ))
                        .toggleStyle(.switch).labelsHidden().tint(Theme.brass)
                    }
                    if let loginItemProblem {
                        Text(loginItemProblem)
                            .font(Theme.display(11))
                            .foregroundStyle(Theme.rust)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .sleeveCard(radius: 18, padding: 18)
            }

            about
        }
    }

    private func toggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Theme.brass)
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemEnabled = SMAppService.mainApp.status == .enabled
            loginItemProblem = nil
        } catch {
            loginItemEnabled = SMAppService.mainApp.status == .enabled
            loginItemProblem = "macOS wouldn't register VinylQ as a login item — this needs a signed copy in /Applications. (\(error.localizedDescription))"
        }
    }

    private var about: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: 0x0C0B0A))
                Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                Circle().fill(Theme.brass).frame(width: 9, height: 9)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text("VinylQ")
                    .font(Theme.display(13, .semibold))
                    .foregroundStyle(Theme.cream)
                Text("VinylQ drives the players you already use — the Music app and Spotify — over Apple Events, and plays your own files itself. Nothing is uploaded, and no password ever passes through it.")
                    .font(Theme.display(11))
                    .foregroundStyle(Theme.creamFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sleeveCard(radius: 18, padding: 18)
    }
}
