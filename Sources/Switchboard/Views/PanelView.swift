import AppKit
import SwiftUI

struct PanelView: View {
    let board: Board
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LoadMeters(monitor: board.monitor)

            ForEach(board.sections) { section in
                SectionHeader(title: section.title)
                VStack(spacing: 0) {
                    ForEach(section.controls) { control in
                        ToggleRow(control: control, board: board)
                    }
                }
            }

            SectionHeader(title: "Actions")
            HStack(spacing: 6) {
                ActionButton(title: "Screen Saver", symbol: "sparkles") {
                    dismiss()
                    board.startScreenSaver()
                }
                ActionButton(title: "Empty Trash…", symbol: "trash", busy: board.isEmptyingTrash) {
                    Task { await board.emptyTrash() }
                }
                ActionButton(title: board.drives.drives.isEmpty ? "Nothing to Eject" : "Eject (\(board.drives.drives.count))",
                             symbol: "eject", busy: board.drives.isEjecting) {
                    Task { _ = await board.ejectAll() }
                }
                .disabled(board.drives.drives.isEmpty)
                .help(board.drives.drives.isEmpty
                      ? "Ejects USB sticks, SD cards, disk images and network drives. Hard disks stay connected."
                      : "Ejects " + board.drives.drives.map(\.name).joined(separator: ", ") + ". Hard disks stay connected.")
            }
            .padding(.horizontal, 6)
            Text("Eject only removes disk images, network drives, USB sticks and SD cards. Hard disks stay connected.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)

            SectionHeader(title: "Pomodoro")
            PomodoroSection(model: board.pomodoro, isVisible: board.isPanelOpen)

            if let problem = board.actionProblem {
                Text(problem.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
            } else if let note = board.actionNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }

            Divider().padding(.top, 4)
            Footer(board: board)
        }
        .padding(10)
        .frame(width: 300)
        // The menu bar panel's own glass is nearly clear on macOS 26 and later, so
        // windows behind it showed through the rows. A solid backing keeps it readable.
        .background(Color(nsColor: .windowBackgroundColor))
        .background(PanelVisibilityObserver { board.panelVisibilityChanged($0) })
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.top, 4)
    }
}

private struct ActionButton: View {
    let title: String
    let symbol: String
    var busy = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if busy {
                    ProgressView().controlSize(.small).frame(height: 16)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 14))
                        .frame(height: 16)
                }
                Text(title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(hovering ? 0.12 : 0.07))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { hovering = $0 }
    }
}

private struct Footer: View {
    let board: Board
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let changed = board.changedSettings
        VStack(alignment: .leading, spacing: 6) {
            if !changed.isEmpty {
                Button {
                    Task { await board.restoreOriginalSettings() }
                } label: {
                    Label(changed.count == 1 ? "Restore 1 original setting" : "Restore \(changed.count) original settings",
                          systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.link)
                .font(.caption)
                .help("Put back: " + changed.map(\.setting.title).joined(separator: ", "))
            }
            HStack {
                Toggle("Launch at Login", isOn: Binding(
                    get: { board.launchAtLogin },
                    set: { board.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button("Shortcuts…") {
                    openWindow(id: ShortcutsView.windowID)
                    NSApp.activate()
                }
                .buttonStyle(.link)
                .font(.caption)
                Menu {
                    Button("Check for Updates…") { Support.checkForUpdates() }
                    Button("Report a Bug…") { Support.reportBug() }
                    Button("Switchboard on GitHub") { Support.openRepo() }
                    Divider()
                    Text("Version \(Support.appVersion)")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Updates, bug reports and more")
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .keyboardShortcut("q")
            }
        }
        .padding(.horizontal, 6)
    }
}

/// Tells the board when the menu bar panel opens and closes, so it can reread every
/// setting on open and stop the countdown on close.
private struct PanelVisibilityObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let window else { return }
            let center = NotificationCenter.default
            tokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.onChange?(true)
            })
            tokens.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.onChange?(false)
            })
            if window.isKeyWindow { onChange?(true) }
        }
    }
}
