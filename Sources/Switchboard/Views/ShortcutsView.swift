import AppKit
import SwiftUI
import SwitchboardKit

/// The Keyboard Shortcuts window: a global shortcut for any row or action.
struct ShortcutsView: View {
    static let windowID = "shortcuts"

    let board: Board

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Suggested: ⌃⌥⌘ with a letter for each, like ⌃⌥⌘D for Dark Mode. macOS and most apps leave these free.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Button("Use Suggested") { board.useSuggestedShortcuts() }
                        Button("Clear All") { board.clearShortcuts() }
                            .disabled(board.shortcuts.isEmpty)
                    }
                    .controlSize(.small)
                }
            }
            Section {
                ForEach(board.settingTargets) { target in
                    ShortcutRow(target: target, board: board)
                }
            } header: {
                Text("Settings")
            } footer: {
                Text("A shortcut switches the setting on or off from any app. Press it with the panel closed to see a brief confirmation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Actions") {
                ForEach(Board.actionTargets) { target in
                    ShortcutRow(target: target, board: board)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .frame(minHeight: 420, idealHeight: 640)
    }
}

private struct ShortcutRow: View {
    let target: Board.ShortcutTarget
    let board: Board

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                ShortcutField(
                    shortcut: board.shortcuts[target.id],
                    onChange: { board.setShortcut($0, for: target.id) },
                    onRecordingChange: { recording in
                        recording ? board.pauseShortcuts() : board.registerShortcuts()
                    })
                if board.refusedShortcuts.contains(target.id) {
                    Text("In use by another app")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } label: {
            Label(target.title, systemImage: target.symbol)
        }
    }
}

/// Click, then press the shortcut. Esc cancels; Delete clears it.
private struct ShortcutField: View {
    let shortcut: HotKey?
    let onChange: (HotKey?) -> Void
    let onRecordingChange: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Type shortcut…" : (shortcut?.label ?? "Record Shortcut"))
                    .font(.system(size: 12, weight: shortcut == nil || isRecording ? .regular : .medium))
                    .foregroundStyle(shortcut == nil && !isRecording ? .secondary : .primary)
                    .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)

            if shortcut != nil, !isRecording {
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove shortcut")
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        onRecordingChange(false)
    }

    private func handle(_ event: NSEvent) {
        switch event.keyCode {
        case 53:  // Esc
            stopRecording()
            return
        case 51, 117:  // Delete, Forward Delete
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                onChange(nil)
                stopRecording()
                return
            }
        default:
            break
        }
        var modifiers: HotKey.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        let key = HotKey(
            keyCode: event.keyCode, modifiers: modifiers,
            keyName: KeyNames.name(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers))
        guard key.isUsable else {
            // Plain typing can't be a global shortcut; wait for a proper one.
            NSSound.beep()
            return
        }
        onChange(key)
        stopRecording()
    }
}
