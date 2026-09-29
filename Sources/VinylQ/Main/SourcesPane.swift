import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Where the music comes from.
///
/// Apple Music connects through the Music app, signed in as you already are.
/// Spotify signs in the way Cascade does — Spotify's own sign-in sheet, once —
/// which brings every playlist, Liked Songs and recent plays; playback runs
/// through the Spotify app. All of it lands in one playlist browser.
struct SourcesPane: View {

    @ObservedObject var engine: PlayerEngine
    @ObservedObject var settings: Settings
    @ObservedObject var access: MusicAccess
    @ObservedObject var library: SpotifyLibrary
    @ObservedObject var web: SpotifyWebAPI

    @State private var linkDraft = ""
    @State private var linkMessage: String?
    @State private var linkMessageIsError = false
    @State private var isAdding = false
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            PaneSection(
                title: "Connect your music",
                caption: "Sign in once and every playlist — Spotify, Apple Music and your own files — shows up in VinylQ: in the notch, on the full-screen deck and here."
            ) {
                HStack(alignment: .top, spacing: 14) {
                    ConnectionCard(
                        name: "Apple Music",
                        symbol: "music.note",
                        brand: [Color(hex: 0xFA2D48), Color(hex: 0xFC6F86)],
                        status: access.appleMusic,
                        isRunning: access.isRunning(.appleMusic),
                        detail: "Uses the Apple ID you're signed into the Music app with. Your whole library and playlists come along.",
                        appName: "Music",
                        connect: { access.connect(.appleMusic) },
                        openApp: { AppleScriptRunner.shared.launch(bundleID: "com.apple.Music", activate: true) },
                        openSettings: access.openAutomationSettings
                    )
                    SpotifyCard(access: access, web: web, connect: connectSpotify)
                    FilesCard(engine: engine, addFolder: addFolder)
                }
            }

            PaneSection(
                title: "Your playlists",
                caption: "Everything from every service, in one list. Click a playlist to see its songs, or a song to play it."
            ) {
                PlaylistPanel(engine: engine)
                    .frame(height: 380)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.sleeve)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.hairline.opacity(0.7), lineWidth: 1)
                    )
            }

            if access.spotify != .notInstalled {
                linksSection
            }

            if !engine.local.roots.isEmpty {
                foldersSection
            }

            PaneSection(
                title: "Which one the deck shows",
                caption: "VinylQ follows whatever is playing. Pin a source if you'd rather it stayed put."
            ) {
                pinPicker
            }
        }
        .onAppear {
            access.refresh()
            engine.refreshLibrary()
        }
    }

    /// Spotify's sign-in sheet first — that's what brings the playlists —
    /// then macOS's one question about controlling the Spotify app.
    private func connectSpotify() {
        Task {
            if !web.isConnected {
                await web.connect()
            }
            if access.spotify != .connected {
                access.connect(.spotify)
            }
            engine.refreshLibrary()
        }
    }

    // MARK: Links

    private var linksSection: some View {
        PaneSection(
            title: "Add a Spotify playlist by link",
            caption: web.isConnected
                ? "For playlists that aren't in your library — someone else's, or an album. Drag it in from Spotify or paste its link."
                : "Not signed in? You can still add playlists one at a time: drag one in from Spotify, or paste its link."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                dropZone
                if !library.saved.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(library.saved) { collection in
                            if collection != library.saved.first {
                                Rectangle().fill(Theme.hairline.opacity(0.5)).frame(height: 1).padding(.leading, 58)
                            }
                            CollectionRow(
                                title: collection.name,
                                subtitle: collection.kind.capitalized,
                                imageURL: collection.imageURL,
                                symbol: "music.note.list",
                                play: { engine.spotify.playCollection(uri: collection.uri) },
                                remove: { library.remove(collection) },
                                removeHelp: "Remove from VinylQ"
                            )
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.sleeve)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.hairline.opacity(0.7), lineWidth: 1)
                    )
                }
            }
        }
    }

    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(dropTargeted ? Theme.brass : Theme.creamSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drag a playlist or album here from Spotify")
                        .font(Theme.display(12.5, .semibold))
                        .foregroundStyle(Theme.cream)
                    Text("or paste its link — in Spotify, … → Share → Copy link")
                        .font(Theme.display(11))
                        .foregroundStyle(Theme.creamFaint)
                }
            }

            HStack(spacing: 8) {
                TextField("", text: $linkDraft,
                          prompt: Text(verbatim: "https://open.spotify.com/playlist/…").foregroundStyle(Theme.creamFaint))
                    .textFieldStyle(.plain)
                    .font(Theme.mono(11))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1))
                    .onSubmit { add(linkDraft) }

                Button {
                    add(linkDraft)
                } label: {
                    HStack(spacing: 5) {
                        if isAdding { ProgressView().controlSize(.mini) }
                        Text("Add").font(Theme.display(12, .semibold))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.brass))
                }
                .buttonStyle(PressableStyle())
                .disabled(linkDraft.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
            }

            if let linkMessage {
                Text(linkMessage)
                    .font(Theme.display(11, .medium))
                    .foregroundStyle(linkMessageIsError ? Theme.rust : Theme.moss)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(dropTargeted ? Theme.brass.opacity(0.08) : Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(dropTargeted ? Theme.brass : Theme.hairline,
                              style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
        .animation(.easeOut(duration: 0.2), value: linkMessage)
        .onDrop(of: [UTType.url, UTType.plainText], isTargeted: $dropTargeted) { providers in
            receive(providers)
        }
    }

    private func receive(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in add(url.absoluteString) }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                handled = true
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    Task { @MainActor in add(text) }
                }
            }
        }
        return handled
    }

    /// Adds every Spotify link in `text` (a drag of several items arrives as
    /// one link per line).
    private func add(_ text: String) {
        let pieces = text.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        guard !pieces.isEmpty else { return }
        isAdding = true
        Task {
            var added: [String] = []
            var failure: String?
            for piece in pieces {
                do {
                    added.append(try await library.add(piece).name)
                } catch {
                    failure = error.localizedDescription
                }
            }
            isAdding = false
            if !added.isEmpty {
                linkDraft = ""
                linkMessageIsError = false
                linkMessage = added.count == 1 ? "Added \u{201C}\(added[0])\u{201D}." : "Added \(added.count) playlists."
            } else if let failure {
                linkMessageIsError = true
                linkMessage = failure
            }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            linkMessage = nil
        }
    }

    // MARK: Folders

    private var foldersSection: some View {
        PaneSection(title: "Music folders", caption: "Sub-folders become playlists. The stylus scrubs these instantly, because VinylQ is the player.") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(engine.local.roots, id: \.self) { url in
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.brass)
                        Text(url.path)
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.creamSoft)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button {
                            engine.local.removeRoot(url)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.creamFaint)
                        }
                        .buttonStyle(.plain)
                        .help("Stop using this folder")
                    }
                }
                HStack(spacing: 8) {
                    NotchChip(symbol: "plus", title: "Add Folder…", action: addFolder)
                    NotchChip(symbol: "arrow.clockwise", title: "Rescan") { engine.local.rescan() }
                }
                .padding(.top, 4)
            }
            .sleeveCard(radius: 16, padding: 16)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to VinylQ"
        panel.message = "Pick a folder of music. Sub-folders become playlists."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { engine.local.addRoot(url) }
    }

    // MARK: Pin

    private var pinPicker: some View {
        HStack(spacing: 8) {
            SourcePin(title: "Follow playback", isOn: settings.pinnedSource == nil) {
                settings.pinnedSource = nil
            }
            ForEach(SourceKind.allCases) { kind in
                SourcePin(title: kind.rawValue, symbol: kind.symbol,
                          isOn: settings.pinnedSource == kind) {
                    settings.pinnedSource = kind
                }
            }
        }
    }
}

// MARK: - Cards

/// Spotify: sign in (for your library) and allow control (for playback).
private struct SpotifyCard: View {
    @ObservedObject var access: MusicAccess
    @ObservedObject var web: SpotifyWebAPI
    var connect: () -> Void

    @State private var hovering = false

    private let brand = [Color(hex: 0x1DB954), Color(hex: 0x1ED760)]

    private var fullyConnected: Bool { web.isConnected && access.spotify == .connected }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: brand, startPoint: .bottomLeading, endPoint: .topTrailing))
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                .shadow(color: brand[0].opacity(0.35), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Spotify")
                        .font(Theme.display(15, .semibold))
                        .foregroundStyle(Theme.cream)
                    StatusPill(text: statusText, color: statusColor)
                }
            }

            Text(detailText)
                .font(Theme.display(11.5))
                .foregroundStyle(Theme.creamFaint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            primary
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.sleeveGradient(highlight: hovering))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(fullyConnected ? brand[0].opacity(0.45) : Theme.hairline.opacity(hovering ? 1 : 0.7),
                              lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: hovering)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: fullyConnected)
    }

    private var statusText: String {
        if web.isWorking { return "Signing in…" }
        switch (web.isConnected, access.spotify) {
        case (_, .notInstalled):  return "Spotify app not installed"
        case (_, .denied):        return "Control blocked in System Settings"
        case (_, .connecting):    return "Waiting for macOS…"
        case (true, .connected):  return "Connected\(web.displayName.map { " as \($0)" } ?? "")"
        case (true, _):           return "Signed in · allow control"
        case (false, .connected): return "Playing works · sign in for playlists"
        default:                  return "Not connected"
        }
    }

    private var statusColor: Color {
        if fullyConnected { return Theme.moss }
        if access.spotify == .denied { return Theme.rust }
        if web.isWorking || access.spotify == .connecting { return Theme.brass }
        return Theme.creamFaint
    }

    private var detailText: String {
        if access.spotify == .denied {
            return "macOS is blocking VinylQ. Open Privacy & Security → Automation, find VinylQ, and switch Spotify on."
        }
        if let status = web.status, !web.isConnected { return status }
        if fullyConnected {
            return "\(web.playlistCount) playlists, Liked Songs and your recent plays are in. Playback runs through the Spotify app."
        }
        return "Sign in once and your playlists, Liked Songs and recent plays show up everywhere. Playback runs through the Spotify app."
    }

    @ViewBuilder
    private var primary: some View {
        if web.isWorking || access.spotify == .connecting {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(web.isWorking ? "Finish signing in with Spotify" : "Say OK when macOS asks")
                    .font(Theme.display(11.5, .medium))
                    .foregroundStyle(Theme.creamSoft)
            }
            .frame(height: 30)
        } else if access.spotify == .denied {
            wideButton("Open Privacy Settings", filled: false, action: access.openAutomationSettings)
        } else if access.spotify == .notInstalled {
            wideButton("Get Spotify", filled: false) {
                if let url = URL(string: "https://www.spotify.com/download/mac/") { NSWorkspace.shared.open(url) }
            }
        } else if fullyConnected {
            HStack(spacing: 8) {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(Theme.display(12, .semibold))
                    .foregroundStyle(Theme.moss)
                Spacer(minLength: 0)
                NotchChip(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out") { web.disconnect() }
            }
        } else {
            wideButton(web.isConnected ? "Allow VinylQ to control Spotify" : "Sign in with Spotify",
                       filled: true, action: connect)
        }
    }

    private func wideButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.display(12.5, .semibold))
                .foregroundStyle(filled ? Color.black : Theme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(filled
                                   ? AnyShapeStyle(LinearGradient(colors: brand, startPoint: .leading, endPoint: .trailing))
                                   : AnyShapeStyle(Color.white.opacity(0.08)))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

private struct ConnectionCard: View {
    var name: String
    var symbol: String
    var brand: [Color]
    var status: MusicAccess.Status
    var isRunning: Bool
    var detail: String
    var appName: String
    var connect: () -> Void
    var openApp: () -> Void
    var openSettings: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: brand, startPoint: .bottomLeading, endPoint: .topTrailing))
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                .shadow(color: brand[0].opacity(0.35), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(Theme.display(15, .semibold))
                        .foregroundStyle(Theme.cream)
                    StatusPill(text: statusText, color: statusColor)
                }
            }

            Text(detailText)
                .font(Theme.display(11.5))
                .foregroundStyle(Theme.creamFaint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            primaryButton
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.sleeveGradient(highlight: hovering))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(status == .connected ? brand[0].opacity(0.45) : Theme.hairline.opacity(hovering ? 1 : 0.7),
                              lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: hovering)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: status)
    }

    private var statusText: String {
        switch status {
        case .unknown:      return "Checking…"
        case .notInstalled: return "Not installed"
        case .available:    return "Not connected"
        case .connecting:   return "Waiting for macOS…"
        case .connected:    return isRunning ? "Connected" : "Connected · \(appName) is closed"
        case .denied:       return "Blocked in System Settings"
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected:              return Theme.moss
        case .denied:                 return Theme.rust
        case .connecting:             return Theme.brass
        case .unknown, .available, .notInstalled: return Theme.creamFaint
        }
    }

    private var detailText: String {
        switch status {
        case .denied:
            return "macOS is blocking VinylQ. Open Privacy & Security → Automation, find VinylQ, and switch \(appName) on."
        case .notInstalled:
            return "Install \(appName) and sign in, then connect it here."
        default:
            return detail
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch status {
        case .connected:
            HStack(spacing: 8) {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(Theme.display(12, .semibold))
                    .foregroundStyle(Theme.moss)
                Spacer(minLength: 0)
                NotchChip(symbol: "arrow.up.forward.app", title: "Open \(appName)", action: openApp)
            }
        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Say OK when macOS asks")
                    .font(Theme.display(11.5, .medium))
                    .foregroundStyle(Theme.creamSoft)
            }
            .frame(height: 30)
        case .denied:
            wideButton(title: "Open Privacy Settings", filled: false, action: openSettings)
        case .notInstalled:
            wideButton(title: "Install \(appName)", filled: false, action: connect)
        case .unknown, .available:
            wideButton(title: "Connect \(name)", filled: true, action: connect)
        }
    }

    private func wideButton(title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.display(12.5, .semibold))
                .foregroundStyle(filled ? Color.white : Theme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(filled
                                   ? AnyShapeStyle(LinearGradient(colors: brand, startPoint: .leading, endPoint: .trailing))
                                   : AnyShapeStyle(Color.white.opacity(0.08)))
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(filled ? 0 : 0.1), lineWidth: 0.8))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

private struct FilesCard: View {
    @ObservedObject var engine: PlayerEngine
    var addFolder: () -> Void

    @State private var hovering = false

    var body: some View {
        let count = engine.local.roots.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Theme.brass, Color(hex: 0xC98A3E)],
                                                 startPoint: .bottomLeading, endPoint: .topTrailing))
                    Image(systemName: "folder.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 34, height: 34)
                .shadow(color: Theme.brass.opacity(0.3), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Files")
                        .font(Theme.display(15, .semibold))
                        .foregroundStyle(Theme.cream)
                    StatusPill(text: count == 0 ? "No folders yet" : "\(count) folder\(count == 1 ? "" : "s")",
                               color: count == 0 ? Theme.creamFaint : Theme.moss)
                }
            }

            Text("MP3, AAC, FLAC, WAV and more, played by VinylQ itself — the needle scrubs instantly.")
                .font(Theme.display(11.5))
                .foregroundStyle(Theme.creamFaint)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(action: addFolder) {
                Text(count == 0 ? "Add a Folder…" : "Add Another Folder…")
                    .font(Theme.display(12.5, .semibold))
                    .foregroundStyle(count == 0 ? Theme.ink : Theme.cream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(count == 0 ? AnyShapeStyle(Theme.brass) : AnyShapeStyle(Color.white.opacity(0.08))))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.sleeveGradient(highlight: hovering))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.hairline.opacity(hovering ? 1 : 0.7), lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: hovering)
    }
}

private struct StatusPill: View {
    var text: String
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(Theme.display(10.5, .medium))
                .foregroundStyle(color == Theme.creamFaint ? Theme.creamSoft : color)
                .lineLimit(1)
        }
    }
}

private struct CollectionRow: View {
    var title: String
    var subtitle: String
    var imageURL: URL?
    var symbol: String
    var play: () -> Void
    var remove: () -> Void
    var removeHelp: String

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.display(12.5, .semibold))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.display(10.5))
                    .foregroundStyle(Theme.creamFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            DeckButton(symbol: "play.fill", size: 9, prominent: true, tint: Color(hex: 0x1ED760), action: play)
                .help("Play in Spotify")
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.creamFaint)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.35)
            .help(removeHelp)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(hovering ? 0.03 : 0))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var placeholder: some View {
        ZStack {
            Color(hex: 0x1DB954).opacity(0.16)
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1ED760))
        }
    }
}

private struct SourcePin: View {
    var title: String
    var symbol: String?
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                }
                Text(title).font(Theme.display(11.5, .medium))
            }
            .foregroundStyle(isOn ? Theme.ink : Theme.creamSoft)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isOn ? AnyShapeStyle(Theme.brass) : AnyShapeStyle(Color.white.opacity(0.07)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .animation(.easeOut(duration: 0.18), value: isOn)
    }
}
