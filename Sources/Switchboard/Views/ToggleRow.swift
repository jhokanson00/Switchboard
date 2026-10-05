import AppKit
import SwiftUI

struct ToggleRow: View {
    let control: Control
    let board: Board
    @State private var hovering = false

    private var state: ControlState { control.reading.state }
    private var isOn: Bool { state == .on }
    private var canSwitch: Bool { state.isOn != nil && !control.isBusy }

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(control.setting.title)
                    .font(.system(size: 13))
                subtitle
            }
            Spacer(minLength: 8)
            if let keepAwake = control.setting as? KeepAwake {
                KeepAwakeMenu(keepAwake: keepAwake, board: board)
            }
            accessory
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering && canSwitch ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { flip() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var icon: some View {
        ZStack {
            Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.08))
            Image(systemName: control.setting.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color.primary.opacity(state.isOn == nil ? 0.4 : 0.85))
        }
        .frame(width: 26, height: 26)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }

    @ViewBuilder
    private var subtitle: some View {
        if let problem = control.problem {
            HStack(spacing: 4) {
                Text(problem.localizedDescription)
                    .foregroundStyle(.red)
                if let url = problem.settingsURL {
                    Button("Open Settings") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.link)
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        } else if case .unavailable(let reason) = state {
            HStack(spacing: 4) {
                Text(reason)
                    .foregroundStyle(.secondary)
                if let ask = control.setting.askForPermission {
                    Button("Allow…", action: ask)
                        .buttonStyle(.link)
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        } else if let detail = control.reading.detail {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if control.isBusy {
            ProgressView()
                .controlSize(.small)
                .frame(width: 32)
        } else {
            Toggle(control.setting.title, isOn: Binding(get: { isOn }, set: { _ in flip() }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(!canSwitch)
        }
    }

    private func flip() {
        guard canSwitch, let current = state.isOn else { return }
        Task { await board.set(control, to: !current) }
    }
}

private struct KeepAwakeMenu: View {
    let keepAwake: KeepAwake
    let board: Board

    var body: some View {
        Menu {
            Button("Until Turned Off") { set(.indefinitely) }
            ForEach(KeepAwake.durations, id: \.seconds) { duration in
                Button(duration.title) { set(.duration(duration.seconds)) }
            }
            Divider()
            Menu("While an App Is Open") {
                if board.openApps.isEmpty {
                    Text("No apps open")
                }
                ForEach(board.openApps, id: \.pid) { app in
                    Button(app.name) { set(.whileRunning(pid: app.pid, name: app.name)) }
                }
            }
        } label: {
            Image(systemName: "clock")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Keep awake for a while, or while an app is open")
    }

    private func set(_ mode: KeepAwake.Mode) {
        Task { await board.keepAwake(mode) }
    }
}
