import SwiftUI

/// Browse playlists, then tracks inside one — the "View Playlist" surface.
///
/// Playlists from every connected service sit in one list, grouped by where
/// they came from, so switching between an Apple Music album and a Spotify
/// playlist is one click rather than a mode change.
struct PlaylistPanel: View {

    @ObservedObject var engine: PlayerEngine
    var compact: Bool = false

    /// Playlist awaiting an inline "are you sure?" — a sheet or alert would
    /// fight the notch panel for focus.
    @State private var pendingRemoval: Playlist?
    @State private var failedRemoval: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            ZStack {
                if engine.openPlaylist == nil {
                    playlistList
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    trackList
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.88), value: engine.openPlaylist?.id)
            .clipped()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if let open = engine.openPlaylist {
                Button {
                    engine.closePlaylist()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: compact ? 10 : 12, weight: .bold))
                        .foregroundStyle(Theme.creamSoft)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text(open.name)
                        .font(Theme.display(compact ? 12 : 14, .semibold))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    Text("\(open.trackCount) tracks · \(open.source.rawValue)")
                        .font(Theme.mono(compact ? 8.5 : 10))
                        .foregroundStyle(Theme.creamFaint)
                }
            } else {
                Text("Playlists")
                    .font(Theme.display(compact ? 12 : 14, .semibold))
                    .foregroundStyle(Theme.cream)
                Text("\(engine.playlists.count)")
                    .font(Theme.mono(compact ? 8.5 : 10))
                    .foregroundStyle(Theme.creamFaint)
            }

            Spacer(minLength: 0)

            Button {
                engine.refreshLibrary()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
                    .foregroundStyle(Theme.creamFaint)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reload playlists")
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 7 : 11)
    }

    // MARK: Playlists

    private var grouped: [(SourceKind, [Playlist])] {
        let buckets = Dictionary(grouping: engine.playlists, by: \.source)
        return SourceKind.allCases.compactMap { kind in
            guard let lists = buckets[kind], !lists.isEmpty else { return nil }
            return (kind, lists)
        }
    }

    private var playlistList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(grouped, id: \.0) { kind, lists in
                    Section {
                        ForEach(lists) { playlist in
                            if pendingRemoval?.id == playlist.id && pendingRemoval?.source == playlist.source {
                                RemovalConfirmRow(
                                    playlist: playlist,
                                    kind: engine.removal(for: playlist),
                                    compact: compact,
                                    cancel: { pendingRemoval = nil },
                                    confirm: { confirmRemoval(playlist) }
                                )
                            } else {
                                PlaylistRow(
                                    playlist: playlist,
                                    compact: compact,
                                    canRemove: engine.removal(for: playlist) != .none,
                                    action: { engine.open(playlist) },
                                    remove: { requestRemoval(playlist) }
                                )
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: compact ? 8 : 9, weight: .semibold))
                            Text(kind.rawValue.uppercased())
                                .font(Theme.mono(compact ? 8 : 9, .semibold))
                                .tracking(0.8)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Theme.creamFaint)
                        .padding(.horizontal, compact ? 12 : 16)
                        .padding(.vertical, 5)
                        .background(compact ? Color.black.opacity(0.94) : Theme.ink.opacity(0.94))
                    }
                }

                if engine.playlists.isEmpty { emptyState }

                if let failedRemoval {
                    Text(failedRemoval)
                        .font(Theme.display(10.5))
                        .foregroundStyle(Theme.creamFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, compact ? 12 : 16)
                        .padding(.vertical, 8)
                }

                if engine.hiddenPlaylistCount > 0 {
                    Button {
                        engine.restoreHiddenPlaylists()
                    } label: {
                        Text("Restore \(engine.hiddenPlaylistCount) removed")
                            .font(Theme.display(10.5, .medium))
                            .foregroundStyle(Theme.creamFaint)
                            .padding(.horizontal, compact ? 12 : 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 6)
        }
        .scrollIndicators(.never)
    }

    private func requestRemoval(_ playlist: Playlist) {
        failedRemoval = nil
        switch engine.removal(for: playlist) {
        case .none:
            break
        case .deleteFromMusic:
            pendingRemoval = playlist
        case .removeLink, .hide:
            Task { await engine.remove(playlist) }
        }
    }

    private func confirmRemoval(_ playlist: Playlist) {
        pendingRemoval = nil
        Task {
            if await !engine.remove(playlist) {
                failedRemoval = "Couldn\u{2019}t delete \u{201C}\(playlist.name)\u{201D}. Is Music open, and is VinylQ allowed to control it?"
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No playlists yet")
                .font(Theme.display(12, .semibold))
                .foregroundStyle(Theme.creamSoft)
            Text("Connect Apple Music or Spotify in VinylQ → Sources, or add a folder of music.")
                .font(Theme.display(11, .regular))
                .foregroundStyle(Theme.creamFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, 14)
    }

    // MARK: Tracks

    private var trackList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if engine.isLoadingTracks {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading the sleeve…")
                            .font(Theme.display(11))
                            .foregroundStyle(Theme.creamFaint)
                    }
                    .padding(.horizontal, compact ? 12 : 16)
                    .padding(.vertical, 14)
                } else if engine.openTracks.isEmpty {
                    Text(engine.openPlaylist?.source == .spotify
                         ? "Spotify only shares the songs in playlists you own or collaborate on."
                         : "This playlist is empty.")
                        .font(Theme.display(11))
                        .foregroundStyle(Theme.creamFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, compact ? 12 : 16)
                        .padding(.vertical, 14)
                }

                ForEach(Array(engine.openTracks.enumerated()), id: \.offset) { index, track in
                    TrackRow(
                        index: index + 1,
                        track: track,
                        compact: compact,
                        isCurrent: track.id == engine.snapshot.track.id,
                        isPlaying: engine.snapshot.isPlaying,
                        accent: engine.accent
                    ) {
                        engine.play(track, in: engine.openPlaylist)
                    }
                }
            }
            .padding(.bottom, 6)
        }
        .scrollIndicators(.never)
    }
}

// MARK: - Rows

private struct PlaylistRow: View {
    var playlist: Playlist
    var compact: Bool
    var canRemove: Bool
    var action: () -> Void
    var remove: () -> Void

    @State private var hovering = false

    private var thumb: CGFloat { compact ? 22 : 28 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                cover
                    .frame(width: thumb, height: thumb)

                VStack(alignment: .leading, spacing: 0) {
                    Text(playlist.name)
                        .font(Theme.display(compact ? 11.5 : 13, .medium))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    if playlist.isCollection {
                        Text("Plays in Spotify")
                            .font(Theme.display(compact ? 9 : 10))
                            .foregroundStyle(Theme.creamFaint)
                    }
                }

                Spacer(minLength: 4)

                if playlist.isCollection {
                    Image(systemName: "play.fill")
                        .font(.system(size: compact ? 8 : 9, weight: .bold))
                        .foregroundStyle(Theme.creamSoft.opacity(hovering ? 1 : 0.5))
                } else {
                    if playlist.trackCount > 0 {
                        Text("\(playlist.trackCount)")
                            .font(Theme.mono(compact ? 9 : 10))
                            .foregroundStyle(Theme.creamFaint)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: compact ? 8 : 9, weight: .bold))
                        .foregroundStyle(Theme.creamFaint.opacity(hovering ? 1 : 0.4))
                }

                if canRemove && hovering {
                    Button(action: remove) {
                        Image(systemName: "trash")
                            .font(.system(size: compact ? 9 : 10, weight: .semibold))
                            .foregroundStyle(Theme.creamSoft)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove playlist")
                }
            }
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 5 : 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.06 : 0))
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu {
            if canRemove {
                Button("Remove Playlist", systemImage: "trash", role: .destructive, action: remove)
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let url = playlist.artworkURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    disc
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else if playlist.id == SpotifyProvider.recentID {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.brass.opacity(0.18))
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: compact ? 9 : 11, weight: .semibold))
                    .foregroundStyle(Theme.brass)
            }
        } else {
            disc
        }
    }

    /// A tiny record standing in for a sleeve thumbnail.
    private var disc: some View {
        ZStack {
            Circle().fill(Color(hex: 0x0D0C0B))
            Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            Circle().fill(Theme.brass.opacity(0.85))
                .frame(width: thumb * 0.34, height: thumb * 0.34)
        }
    }
}

private struct RemovalConfirmRow: View {
    var playlist: Playlist
    var kind: PlayerEngine.Removal
    var compact: Bool
    var cancel: () -> Void
    var confirm: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Delete \u{201C}\(playlist.name)\u{201D}?")
                    .font(Theme.display(compact ? 11 : 12.5, .medium))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                Text("Removes it from Music. Your songs stay.")
                    .font(Theme.display(compact ? 9 : 10))
                    .foregroundStyle(Theme.creamFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("Cancel", action: cancel)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.creamSoft)
            Button("Delete", action: confirm)
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(Color(hex: 0xE5604D))
        }
        .font(Theme.display(compact ? 10.5 : 12))
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 5 : 7)
    }
}

private struct TrackRow: View {
    var index: Int
    var track: Track
    var compact: Bool
    var isCurrent: Bool
    var isPlaying: Bool
    var accent: Color
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    if isCurrent {
                        Image(systemName: isPlaying ? "waveform" : "pause.fill")
                            .font(.system(size: compact ? 9 : 10, weight: .semibold))
                            .foregroundStyle(accent)
                            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                    } else if hovering {
                        Image(systemName: "play.fill")
                            .font(.system(size: compact ? 8 : 9, weight: .semibold))
                            .foregroundStyle(Theme.creamSoft)
                    } else {
                        Text("\(index)")
                            .font(Theme.mono(compact ? 9 : 10))
                            .foregroundStyle(Theme.creamFaint)
                    }
                }
                .frame(width: compact ? 16 : 20, alignment: .center)

                VStack(alignment: .leading, spacing: 0) {
                    Text(track.title)
                        .font(Theme.display(compact ? 11.5 : 13, isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? accent : Theme.cream)
                        .lineLimit(1)
                    if !track.artist.isEmpty {
                        Text(track.artist)
                            .font(Theme.display(compact ? 9.5 : 11))
                            .foregroundStyle(Theme.creamFaint)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if track.duration > 0 {
                    Text(track.duration.clockString)
                        .font(Theme.mono(compact ? 9 : 10))
                        .foregroundStyle(Theme.creamFaint)
                }
            }
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 5 : 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.06 : 0))
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
