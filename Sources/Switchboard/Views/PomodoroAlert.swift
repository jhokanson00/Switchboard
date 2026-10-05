import AppKit
import SwiftUI
import SwitchboardKit

/// The end of a Pomodoro phase, made hard to miss: a sound played three times and a
/// pop-up in the middle of the screen that stays until it's answered. Unlike a
/// notification, neither is held back by Focus or Do Not Disturb.
@MainActor
enum PomodoroAlert {
    struct Choice {
        let title: String
        let action: () -> Void
    }

    private static var panel: NSPanel?
    private static var chime: Task<Void, Never>?

    /// The sounds in /System/Library/Sounds and ~/Library/Sounds, by name.
    static let soundNames: [String] = {
        let folders = [
            URL(fileURLWithPath: "/System/Library/Sounds"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Sounds"),
        ]
        let names = folders.flatMap {
            (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
        }
        .map { $0.deletingPathExtension().lastPathComponent }
        return Array(Set(names)).sorted()
    }()

    /// Plays the sound three times, one after another.
    static func play(_ name: String, times: Int = 3) {
        chime?.cancel()
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        chime = Task {
            for index in 0..<times {
                if index > 0 { try? await Task.sleep(for: .seconds(sound.duration + 0.15)) }
                guard !Task.isCancelled else { return }
                sound.stop()
                sound.play()
            }
        }
    }

    /// Shows the pop-up on the screen with the pointer, replacing one already showing.
    /// The last choice is the default. It doesn't take the keyboard, so typing in another
    /// app can't answer it by accident.
    static func show(symbol: String, title: String, message: String, choices: [Choice]) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let view = PomodoroAlertView(symbol: symbol, title: title, message: message, choices: choices.map { choice in
            Choice(title: choice.title) {
                dismiss()
                choice.action()
            }
        })
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.midY - panel.frame.height / 2 + frame.height / 8))
        }
        panel.orderFrontRegardless()
    }

    static func dismiss() {
        chime?.cancel()
        panel?.orderOut(nil)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}

private struct PomodoroAlertView: View {
    let symbol: String
    let title: String
    let message: String
    let choices: [PomodoroAlert.Choice]

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(height: 48)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                    if index == choices.count - 1 {
                        Button(choice.title, action: choice.action)
                            .keyboardShortcut(.defaultAction)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(choice.title, action: choice.action)
                            .buttonStyle(.bordered)
                    }
                }
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
