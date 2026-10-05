import SwiftUI
import SwitchboardKit

struct PomodoroSection: View {
    let model: PomodoroModel
    /// The countdown only ticks while the panel is showing.
    let isVisible: Bool

    private var timer: Pomodoro { model.timer }

    private var isPaused: Bool {
        if case .paused = timer.status { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            timerRow
            HStack(spacing: 6) {
                Picker("Focus length", selection: Binding(
                    get: { model.focusMinutes },
                    set: { model.setFocusMinutes($0) })
                ) {
                    ForEach(PomodoroSettings.focusChoices, id: \.self) { minutes in
                        Text("\(minutes)m").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .help("Focus length. Changes apply from the next focus session.")
                alertMenu
            }
        }
        .padding(.horizontal, 6)
    }

    /// How the end of a phase is announced: the sound, the pop-up, and a test.
    private var alertMenu: some View {
        Menu {
            Picker("Sound", selection: Binding(
                get: { model.alertSound ?? "" },
                set: { model.setAlertSound($0.isEmpty ? nil : $0) })
            ) {
                Text("None").tag("")
                Divider()
                ForEach(PomodoroAlert.soundNames, id: \.self) { Text($0).tag($0) }
            }
            Toggle("Show Pop-up", isOn: Binding(
                get: { model.showsPopUp },
                set: { model.setShowsPopUp($0) }))
            Divider()
            Button("Test Alert") { model.testAlert() }
        } label: {
            Image(systemName: model.alertSound == nil ? "bell.slash" : "bell")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("How the end of a focus session or break is announced")
        .accessibilityLabel("Alert sound and pop-up")
    }

    private var timerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isPaused ? "\(timer.phase.title) · Paused" : timer.phase.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                countdown
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                progressDots
            }
            Spacer()
            HStack(spacing: 6) {
                if timer.status != .idle {
                    RoundButton(symbol: "arrow.counterclockwise", help: "Reset") { model.reset() }
                }
                RoundButton(symbol: "forward.end.fill", help: "Skip to the next phase") { model.skip() }
                RoundButton(symbol: timer.isRunning ? "pause.fill" : "play.fill",
                            help: timer.isRunning ? "Pause" : "Start",
                            prominent: true) {
                    timer.isRunning ? model.pause() : model.start()
                }
            }
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if isVisible, case .running(let end) = timer.status, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
        } else {
            Text(Self.format(timer.remaining(at: .now)))
        }
    }

    private var progressDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<timer.settings.sessionsBeforeLongBreak, id: \.self) { index in
                Circle()
                    .fill(index < timer.completedInCycle ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("\(timer.completedInCycle) of \(timer.settings.sessionsBeforeLongBreak) focus sessions done")
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct RoundButton: View {
    let symbol: String
    let help: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 13 : 11, weight: .semibold))
                .frame(width: prominent ? 34 : 28, height: prominent ? 34 : 28)
                .background(Circle().fill(prominent ? Color.accentColor : Color.primary.opacity(0.08)))
                .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
