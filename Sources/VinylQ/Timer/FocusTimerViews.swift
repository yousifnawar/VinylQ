import SwiftUI

// The focus timer, in the three places it lives: tucked under the clock on
// the full-screen deck, in the notch, and in the Study room. All of them are
// built from the same few parts, so a change in one reads the same in all.

// MARK: - Ring

/// A thin progress ring, starting at twelve o'clock.
struct TimerRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.09), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(progress, 0.0005))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0 ? 1 : 0)
        }
        .padding(lineWidth / 2)
    }
}

// MARK: - Controls

/// Start / pause / resume, and — once a block is going — skip and reset.
struct TimerControls: View {
    enum Size { case regular, large }

    @ObservedObject var timer: StudyTimer
    var size: Size = .regular

    var body: some View {
        HStack(spacing: 8) {
            Button {
                timer.start()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: size == .large ? 11 : 9.5, weight: .bold))
                    Text(timer.primaryActionTitle)
                        .font(Theme.display(size == .large ? 13.5 : 12, .semibold))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, size == .large ? 18 : 14)
                .padding(.vertical, size == .large ? 9 : 7)
                .frame(maxWidth: size == .large ? .infinity : nil)
                .background(Capsule().fill(timer.phase.tint))
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())

            if timer.phase != .idle {
                DeckButton(symbol: "forward.end.fill", size: size == .large ? 10.5 : 9.5) { timer.skip() }
                    .help("Skip to the next block")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                DeckButton(symbol: "arrow.counterclockwise", size: size == .large ? 10.5 : 9.5) { timer.reset() }
                    .help("Reset the timer")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: timer.phase)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: timer.isRunning)
    }
}

/// One tap to a focus/break pair.
struct PresetChip: View {
    var preset: StudyTimer.Preset
    var isSelected: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(preset.label)
                .font(Theme.mono(10, .semibold))
                .foregroundStyle(isSelected ? Theme.cream : (hovering ? Theme.creamSoft : Theme.creamFaint))
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    Capsule().fill(isSelected ? Theme.moss.opacity(0.28) : Color.white.opacity(hovering ? 0.09 : 0.05))
                )
                .overlay(Capsule().strokeBorder(isSelected ? Theme.moss.opacity(0.5) : .clear, lineWidth: 0.7))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .help("\(preset.focus) minutes of focus, \(preset.rest) minute breaks")
    }
}

/// The break chime, on or off.
struct ChimeToggle: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Button {
            settings.chimeEnabled.toggle()
        } label: {
            Image(systemName: settings.chimeEnabled ? "bell.fill" : "bell.slash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(settings.chimeEnabled ? Theme.creamSoft : Theme.creamFaint)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(settings.chimeEnabled ? "Chime is on — click to mute" : "Chime is off")
    }
}

/// A button that gives a little under your finger.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Under the clock (full-screen deck)

/// Just a timer — until you open it up to change how it runs.
struct FocusTimerCompact: View {
    @ObservedObject var timer: StudyTimer
    @ObservedObject var settings: Settings
    @Binding var expanded: Bool
    var width: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                TimerRing(progress: timer.progress, tint: timer.phase.tint, lineWidth: 3.5)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(timer.remainingLabel)
                        .font(Theme.mono(34, .light))
                        .monospacedDigit()
                        .foregroundStyle(Theme.cream)
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1)
                        .fixedSize()
                    Text(caption.uppercased())
                        .font(Theme.mono(9, .semibold))
                        .tracking(1.2)
                        .foregroundStyle(timer.phase.tint)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button {
                    timer.start()
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(timer.phase.tint))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .help(timer.primaryActionTitle)

                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.creamSoft)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(expanded ? 0.12 : 0.07)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .help(expanded ? "Hide timer settings" : "Timer settings")
            }

            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    Rectangle()
                        .fill(Theme.glassStroke)
                        .frame(height: 1)
                        .padding(.top, 16)
                    TimerSettingsView(timer: timer, settings: settings)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: width - 36, alignment: .leading)
        .glassCard(radius: 22, padding: 18)
        .animation(.easeOut(duration: 0.25), value: timer.secondsLeft)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: expanded)
    }

    private var caption: String {
        switch timer.phase {
        case .idle: return "Focus timer · \(settings.focusMinutes) min"
        default:    return "\(timer.phase.title)\(timer.isRunning ? "" : " · paused") · \(timer.cycleCaption)"
        }
    }
}

// MARK: - Settings

/// Lengths, the chime, and what happens between blocks.
struct TimerSettingsView: View {
    @ObservedObject var timer: StudyTimer
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(StudyTimer.Preset.all) { preset in
                    PresetChip(preset: preset, isSelected: timer.currentPreset == preset) {
                        timer.apply(preset)
                    }
                }
            }

            VStack(spacing: 9) {
                MinuteStepper(label: "Focus", value: $settings.focusMinutes, range: 5...180, step: 5)
                MinuteStepper(label: "Break", value: $settings.breakMinutes, range: 1...60, step: 1)
                MinuteStepper(label: "Long break", value: $settings.longBreakMinutes, range: 5...90, step: 5)
                MinuteStepper(label: "Blocks before a long break", value: $settings.cyclesUntilLongBreak,
                              range: 2...8, step: 1, unit: "")
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.chimeEnabled) {
                    Text("Chime between blocks")
                        .font(Theme.display(12, .medium))
                        .foregroundStyle(Theme.cream)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(timer.phase.tint)

                if settings.chimeEnabled {
                    HStack(spacing: 8) {
                        Picker("", selection: $settings.chimeName) {
                            ForEach(Chime.allCases) { chime in
                                Text(chime.label).tag(chime.rawValue)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)

                        Button {
                            timer.previewChime()
                        } label: {
                            Image(systemName: "play.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.creamSoft)
                        }
                        .buttonStyle(.plain)
                        .help("Hear it")
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.creamFaint)
                        Slider(value: $settings.chimeVolume, in: 0.05...1)
                            .controlSize(.mini)
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.creamFaint)
                    }
                }

                Toggle(isOn: $settings.autoContinue) {
                    Text("Roll straight into the next block")
                        .font(Theme.display(11.5))
                        .foregroundStyle(Theme.creamSoft)
                }
                .toggleStyle(.checkbox)
            }

            if timer.phase != .idle {
                HStack(spacing: 8) {
                    NotchChip(symbol: "forward.end.fill", title: "Skip block") { timer.skip() }
                    NotchChip(symbol: "arrow.counterclockwise", title: "Reset") { timer.reset() }
                }
            }
        }
    }
}

/// A compact stepper row used by the timer settings.
struct MinuteStepper: View {
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int
    var unit: String = "min"

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Theme.display(11.5))
                .foregroundStyle(Theme.creamSoft)
                .lineLimit(1)
            Spacer(minLength: 0)
            stepButton("minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                .font(Theme.mono(11, .medium))
                .foregroundStyle(Theme.cream)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(width: 54, alignment: .center)
            stepButton("plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
        .animation(.easeOut(duration: 0.2), value: value)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(enabled ? Theme.creamSoft : Theme.creamFaint.opacity(0.5))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

// MARK: - Study room

/// The big version: a large ring, and the settings laid out beside it.
struct FocusTimerPanel: View {
    @ObservedObject var timer: StudyTimer
    @ObservedObject var settings: Settings

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(spacing: 18) {
                ZStack {
                    TimerRing(progress: timer.progress, tint: timer.phase.tint, lineWidth: 9)
                    VStack(spacing: 4) {
                        Text(timer.phase.title.uppercased())
                            .font(Theme.mono(10, .semibold))
                            .tracking(1.4)
                            .foregroundStyle(timer.phase.tint)
                        Text(timer.remainingLabel)
                            .font(Theme.mono(timer.remaining >= 3600 ? 34 : 44, .light))
                            .monospacedDigit()
                            .foregroundStyle(Theme.cream)
                            .contentTransition(.numericText(countsDown: true))
                        Text(timer.cycleCaption)
                            .font(Theme.display(11, .medium))
                            .foregroundStyle(Theme.creamFaint)
                    }
                }
                .frame(width: 200, height: 200)
                .animation(.easeOut(duration: 0.25), value: timer.secondsLeft)

                TimerControls(timer: timer, size: .large)
                    .frame(width: 220)
            }

            TimerSettingsView(timer: timer, settings: settings)
                .frame(maxWidth: 320, alignment: .leading)
        }
        .sleeveCard(radius: 24, highlight: true, padding: 24)
    }
}
