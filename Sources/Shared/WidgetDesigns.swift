import AppKit
import SwiftUI
import WidgetKit

// The widgets' faces.
//
// Compiled into both the widget extension and the app: the extension shows
// them on your desktop, the app shows the very same views in its Widgets room.
// Buttons go through `VinylQActionButton`, which each target defines for itself —
// an App Intent in the extension, a direct call in the app.

// MARK: - Now Playing

struct NowPlayingWidgetView: View {
    var state: WidgetState
    var artwork: NSImage?
    var family: WidgetFamily
    /// The timeline entry's date; everything that can't tick by itself is
    /// drawn as of this moment.
    var date: Date

    @Environment(\.vinylqAppRunning) private var appRunning

    private var track: WidgetState.Track { state.nowPlaying.track }
    private var accent: Color { state.accent }
    private var isPlaying: Bool { state.nowPlaying.isPlaying && appRunning }
    private var isEmpty: Bool { track.isSilence }

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemLarge, .systemExtraLarge: large
        default: medium
        }
    }

    // MARK: Sizes

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                SleeveAndRecord(artwork: artwork, accent: accent, peek: 0.3)
                    .frame(width: 86, height: 66)
                Spacer(minLength: 4)
                VinylQActionButton(action: .togglePlayback) {
                    PlayGlyph(isPlaying: isPlaying, tint: accent, size: 30)
                }
            }
            Spacer(minLength: 6)
            titles(titleSize: 13.5, artistSize: 11)
            Spacer(minLength: 7)
            progressBar(height: 3.5)
        }
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 14) {
            SleeveAndRecord(artwork: artwork, accent: accent, peek: 0.34)
                .frame(width: 136, height: 102)

            VStack(alignment: .leading, spacing: 0) {
                sourceLabel
                Spacer(minLength: 5)
                titles(titleSize: 15, artistSize: 12)
                Spacer(minLength: 8)
                progressBar(height: 4)
                timeRow.padding(.top, 4)
                Spacer(minLength: 7)
                transport(scale: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var large: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                sourceLabel
                Spacer(minLength: 0)
                focusChip
            }
            Spacer(minLength: 6)

            let side: CGFloat = 176
            let geometry = DeckGeometry(side: side)
            let progress = state.progress(at: date)
            ZStack {
                VinylPlatter(
                    geometry: geometry, artwork: artwork, accent: accent,
                    angle: state.elapsed(at: date) * (33.333 / 60) * 360,
                    progress: progress, title: track.title, subtitle: track.artist, compact: true
                )
                Tonearm(
                    geometry: geometry,
                    angle: geometry.armAngle(progress: progress, parked: isEmpty),
                    isScrubbing: false, accent: accent, interactive: false
                )
            }
            .frame(width: side, height: side)

            Spacer(minLength: 6)
            titles(titleSize: 17, artistSize: 13, centred: true)
            Spacer(minLength: 10)
            progressBar(height: 4)
            timeRow.padding(.top, 4)
            Spacer(minLength: 8)
            transport(scale: 1.2)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Pieces

    private var sourceLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: isEmpty ? "opticaldisc" : track.sourceSymbol)
                .font(.system(size: 8.5, weight: .bold))
            Text((isEmpty ? "VinylQ" : track.source).uppercased())
                .font(Theme.mono(8.5, .semibold))
                .tracking(0.8)
                .lineLimit(1)
        }
        .foregroundStyle(accent)
        .widgetAccentable()
    }

    @ViewBuilder
    private func titles(titleSize: CGFloat, artistSize: CGFloat, centred: Bool = false) -> some View {
        VStack(alignment: centred ? .center : .leading, spacing: 1) {
            Text(isEmpty ? "Nothing spinning" : track.title)
                .font(Theme.display(titleSize, .semibold))
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
            Text(subtitle)
                .font(Theme.display(artistSize, .medium))
                .foregroundStyle(Theme.creamSoft)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)
    }

    private var subtitle: String {
        if !appRunning { return "VinylQ is closed — tap to open" }
        if isEmpty { return "Play something in Music or Spotify" }
        return track.artist
    }

    @Environment(\.vinylqDrawsOwnProgress) private var drawsOwnProgress

    @ViewBuilder
    private func progressBar(height: CGFloat) -> some View {
        let duration = track.duration
        if drawsOwnProgress {
            // Inside the app, where a system progress bar ignores the tint.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(accent)
                        .frame(width: max(height, proxy.size.width * state.progress(at: date)))
                }
            }
            .frame(height: height)
            .animation(.linear(duration: 1), value: date)
        } else {
            Group {
                if isPlaying, duration > 0, let end = state.trackEnd, end > date {
                    // Counts forward by itself — no reloads needed mid-song.
                    ProgressView(timerInterval: state.trackStart...end, countsDown: false,
                                 label: { EmptyView() }, currentValueLabel: { EmptyView() })
                } else {
                    ProgressView(value: state.progress(at: date))
                }
            }
            .progressViewStyle(.linear)
            .tint(accent)
            .frame(height: height)
            .widgetAccentable()
        }
    }

    @ViewBuilder
    private var timeRow: some View {
        let duration = track.duration
        HStack(spacing: 0) {
            Group {
                if isPlaying, duration > 0, let end = state.trackEnd, end > date {
                    Text(timerInterval: state.trackStart...end, countsDown: false)
                } else {
                    Text(state.elapsed(at: date).clockString)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(duration > 0 ? duration.clockString : "")
        }
        .font(Theme.mono(9.5))
        .monospacedDigit()
        .foregroundStyle(Theme.creamFaint)
    }

    private func transport(scale: CGFloat) -> some View {
        HStack(spacing: 14 * scale) {
            VinylQActionButton(action: .previousTrack) {
                TransportGlyph(symbol: "backward.fill", size: 11 * scale)
            }
            VinylQActionButton(action: .togglePlayback) {
                PlayGlyph(isPlaying: isPlaying, tint: accent, size: 30 * scale)
            }
            VinylQActionButton(action: .nextTrack) {
                TransportGlyph(symbol: "forward.fill", size: 11 * scale)
            }
        }
    }

    @ViewBuilder
    private var focusChip: some View {
        if state.focus.phase != .idle {
            HStack(spacing: 4) {
                Image(systemName: "timer").font(.system(size: 8.5, weight: .bold))
                if state.focus.isRunning, let end = state.focus.endDate, end > date {
                    Text(timerInterval: date...end, countsDown: true)
                        .monospacedDigit()
                } else {
                    Text(state.focusRemaining(at: date).countdownString)
                }
            }
            .font(Theme.mono(9, .semibold))
            .foregroundStyle(state.focus.phase.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(state.focus.phase.tint.opacity(0.15)))
            .widgetAccentable()
        }
    }
}

// MARK: - Focus timer

struct FocusWidgetView: View {
    var state: WidgetState
    var family: WidgetFamily
    var date: Date

    private var focus: WidgetState.Focus { state.focus }
    private var tint: Color { focus.phase.tint }
    private var isRunning: Bool { focus.isRunning && focus.endDate.map { $0 > date } == true }

    var body: some View {
        switch family {
        case .systemSmall: small
        default: medium
        }
    }

    private var small: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                phaseDot
                Text(focus.phase.title.uppercased())
                    .font(Theme.mono(8.5, .semibold))
                    .tracking(1.1)
                    .foregroundStyle(tint)
                    .widgetAccentable()
                Spacer(minLength: 0)
            }
            Spacer(minLength: 4)
            ZStack {
                ring(lineWidth: 6.5)
                countdown(size: 19)
            }
            .frame(width: 82, height: 82)
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                VinylQActionButton(action: .toggleFocus) {
                    primaryCapsule(compact: true)
                }
                if focus.phase != .idle {
                    VinylQActionButton(action: .skipFocus) {
                        TransportGlyph(symbol: "forward.end.fill", size: 9)
                    }
                }
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 18) {
            ZStack {
                ring(lineWidth: 8.5)
                VStack(spacing: 1) {
                    countdown(size: 27)
                    Text(ringCaption)
                        .font(Theme.display(9.5, .medium))
                        .foregroundStyle(Theme.creamFaint)
                }
            }
            .frame(width: 122, height: 122)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    phaseDot
                    Text(focus.phase.title.uppercased())
                        .font(Theme.mono(9, .semibold))
                        .tracking(1.2)
                        .foregroundStyle(tint)
                        .widgetAccentable()
                }
                Spacer(minLength: 5)
                Text(headline)
                    .font(Theme.display(18, .semibold))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                caption
                    .font(Theme.display(11.5, .medium))
                    .foregroundStyle(Theme.creamSoft)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 7) {
                    VinylQActionButton(action: .toggleFocus) {
                        primaryCapsule(compact: false)
                    }
                    if focus.phase != .idle {
                        VinylQActionButton(action: .skipFocus) {
                            TransportGlyph(symbol: "forward.end.fill", size: 10)
                        }
                        VinylQActionButton(action: .resetFocus) {
                            TransportGlyph(symbol: "arrow.counterclockwise", size: 10)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Pieces

    private var phaseDot: some View {
        Circle()
            .fill(tint)
            .frame(width: 6, height: 6)
            .opacity(isRunning ? 1 : 0.4)
            .widgetAccentable()
    }

    private func ring(lineWidth: CGFloat) -> some View {
        let progress = state.focusProgress(at: date)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.09), lineWidth: lineWidth)
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: max(progress, 0.004))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
        }
        .padding(lineWidth / 2)
    }

    @ViewBuilder
    private func countdown(size: CGFloat) -> some View {
        // An hour or more needs seven characters; shrink to keep one line.
        let hours = state.focusRemaining(at: date) >= 3600
        Group {
            if isRunning, let end = focus.endDate {
                Text(timerInterval: date...end, countsDown: true)
            } else {
                Text(state.focusRemaining(at: date).countdownString)
            }
        }
        .font(Theme.mono(hours ? size * 0.74 : size, .light))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.cream)
        .frame(maxWidth: size * 4)
    }

    private var ringCaption: String {
        switch (focus.phase, isRunning) {
        case (.idle, _):  return "ready"
        case (_, true):   return "remaining"
        case (_, false):  return "paused"
        }
    }

    private var headline: String {
        switch focus.phase {
        case .idle:       return "Ready to focus"
        case .focus:      return "Deep focus"
        case .shortBreak: return "Take a breath"
        case .longBreak:  return "Long break"
        }
    }

    @ViewBuilder
    private var caption: some View {
        if isRunning, let end = focus.endDate {
            let next = state.nextPhase
            Text("\(state.cycleCaption) · \(next == .focus ? "focus" : "break") at ") + Text(end, style: .time)
        } else {
            Text(state.cycleCaption)
        }
    }

    private func primaryCapsule(compact: Bool) -> some View {
        let title: String
        let symbol: String
        switch (focus.phase, isRunning) {
        case (.idle, _):   title = "Start";  symbol = "play.fill"
        case (_, true):    title = "Pause";  symbol = "pause.fill"
        case (_, false):   title = "Resume"; symbol = "play.fill"
        }
        return HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: compact ? 8.5 : 9.5, weight: .bold))
            Text(title).font(Theme.display(compact ? 11 : 12, .semibold))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, compact ? 11 : 13)
        .padding(.vertical, compact ? 5 : 6)
        .background(Capsule().fill(tint))
        .widgetAccentable()
    }
}

// MARK: - Backgrounds

/// Cover art washed out behind the controls, warmed by the record's colour.
struct NowPlayingWidgetBackground: View {
    var state: WidgetState
    var artwork: NSImage?

    var body: some View {
        ZStack {
            Theme.ink
            Color.clear
                .overlay {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 24, opaque: true)
                            .saturation(1.3)
                            .opacity(0.55)
                    }
                }
                .clipped()
            LinearGradient(colors: [state.accent.opacity(0.24), .clear],
                           startPoint: .topLeading, endPoint: .center)
            LinearGradient(colors: [Theme.ink.opacity(0.30), Theme.ink.opacity(0.88)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

struct FocusWidgetBackground: View {
    var state: WidgetState

    var body: some View {
        ZStack {
            Theme.ink
            RadialGradient(colors: [state.focus.phase.tint.opacity(0.22), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 220)
            LinearGradient(colors: [Color.white.opacity(0.03), .clear], startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Glyphs

/// The round play/pause button.
struct PlayGlyph: View {
    var isPlaying: Bool
    var tint: Color
    var size: CGFloat

    var body: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: size * 0.40, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(tint))
            .widgetAccentable()
    }
}

/// A quiet round transport control.
struct TransportGlyph: View {
    var symbol: String
    var size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Theme.cream)
            .frame(width: size * 2.3, height: size * 2.3)
            .background(Circle().fill(Color.white.opacity(0.09)))
    }
}
