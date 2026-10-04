import SwiftUI

@main
struct SwitchboardApp: App {
    @State private var board = Board()

    var body: some Scene {
        MenuBarExtra {
            PanelView(board: board)
        } label: {
            MenuBarLabel(pomodoro: board.pomodoro)
        }
        .menuBarExtraStyle(.window)

        Window("Keyboard Shortcuts", id: ShortcutsView.windowID) {
            ShortcutsView(board: board)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// A light switch, or the Pomodoro's minutes left while it runs.
private struct MenuBarLabel: View {
    let pomodoro: PomodoroModel

    var body: some View {
        if let text = pomodoro.menuBarText {
            HStack(spacing: 3) {
                Image(systemName: pomodoro.timer.phase == .focus ? "timer" : "cup.and.saucer")
                Text(text).monospacedDigit()
            }
        } else {
            Image(systemName: "lightswitch.on")
        }
    }
}
