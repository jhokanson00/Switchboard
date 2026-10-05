import AppKit
import Observation
import ServiceManagement
import SwitchboardKit

/// Everything the panel shows: the settings, the actions, the Pomodoro timer.
@MainActor
@Observable
final class Board {
    struct Section: Identifiable {
        let title: String
        let controls: [Control]
        var id: String { title }
    }

    let sections: [Section]
    let keepAwake: KeepAwake
    let pomodoro = PomodoroModel()
    let monitor = SystemMonitor()
    let drives = DriveEjector()

    /// Apps Keep Awake can wait for, refreshed when the panel opens.
    private(set) var openApps: [(pid: pid_t, name: String)] = []

    private(set) var isPanelOpen = false
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Problem from the last action (Empty Trash, Launch at Login), shown above the footer.
    var actionProblem: SwitchboardError?
    /// A passing notice, like "The Trash is already empty."
    var actionNote: String?
    private(set) var isEmptyingTrash = false

    /// Keyboard shortcuts by row or action id.
    private(set) var shortcuts: [String: HotKey] = [:] {
        didSet { Self.saveShortcuts(shortcuts) }
    }
    /// Shortcuts macOS refused, usually because another app already uses them.
    private(set) var refusedShortcuts: Set<String> = []
    @ObservationIgnored private let hotKeys = HotKeyCenter()

    private(set) var originals: OriginalSettings {
        didSet { Self.save(originals) }
    }

    init() {
        let keepAwake = KeepAwake()
        self.keepAwake = keepAwake
        sections = [
            Section(title: "Appearance", controls: [Control(DarkMode()), Control(NightShift())]),
            Section(title: "Desktop & Dock", controls: [
                Control(HideDesktopIcons()), Control(HideDesktopWidgets()), Control(AutohideDock()),
                Control(AutohideMenuBar()), Control(ShowRecentApps()),
            ]),
            Section(title: "Finder", controls: [Control(ShowHiddenFiles()), Control(ShowLibraryFolder())]),
            Section(title: "System", controls: [
                Control(AudioMute(.output)), Control(AudioMute(.input)), Control(keepAwake), Control(Bluetooth()),
            ]),
        ]
        originals = Self.loadOriginals()
        shortcuts = Self.loadShortcuts()
        hotKeys.onPress = { [weak self] id in self?.performShortcut(id) }
        registerShortcuts()
    }

    var controls: [Control] { sections.flatMap(\.controls) }

    func panelVisibilityChanged(_ open: Bool) {
        guard open != isPanelOpen else { return }
        isPanelOpen = open
        if open {
            refreshAll()
            monitor.start()
        } else {
            monitor.stop()
        }
    }

    func refreshAll() {
        controls.forEach { $0.refresh() }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        pomodoro.catchUp()
        drives.refresh()
        openApps = KeepAwake.openApps().map { ($0.processIdentifier, $0.localizedName ?? "App") }
    }

    // MARK: Settings

    func set(_ control: Control, to on: Bool) async {
        guard !control.isBusy, let current = control.reading.state.isOn, current != on else { return }
        control.problem = nil
        guard await control.setting.confirmChange(to: on) else { return }

        if control.setting.restorable { originals.willChange(control.id, from: current) }
        let panelWasOpen = isPanelOpen
        control.isBusy = true
        do {
            try await control.setting.write(on)
        } catch let error as SwitchboardError {
            control.problem = error
        } catch {
            control.problem = .failed(error.localizedDescription)
        }
        control.isBusy = false
        control.refresh()
        if let now = control.reading.state.isOn { originals.didChange(control.id, to: now) }

        if control.setting.closesPanel, panelWasOpen {
            // Give the menu bar a moment to settle, then put the panel back.
            try? await Task.sleep(for: .milliseconds(400))
            if !isPanelOpen { StatusItemPanel.open() }
        }
    }

    func keepAwake(_ mode: KeepAwake.Mode) async {
        guard let control = controls.first(where: { $0.setting === keepAwake }) else { return }
        keepAwake.mode = mode
        if control.reading.state == .on {
            // Already on: start again with the new mode.
            control.problem = nil
            do { try await keepAwake.write(true) } catch let error as SwitchboardError { control.problem = error } catch {}
            control.refresh()
        } else {
            await set(control, to: true)
        }
    }

    /// Settings Switchboard changed that aren't back to what they were.
    var changedSettings: [Control] {
        controls.filter { control in
            guard let original = originals.values[control.id] else { return false }
            return control.reading.state.isOn != original
        }
    }

    func restoreOriginalSettings() async {
        for control in controls {
            guard let original = originals.values[control.id] else { continue }
            if control.reading.state.isOn == original {
                originals.forget(control.id)
            } else {
                await set(control, to: original)
            }
        }
    }

    // MARK: Actions

    func startScreenSaver() {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"),
            configuration: configuration)
    }

    /// Asks Finder how much is in the Trash, confirms, then empties it. Finder does the
    /// counting so Switchboard doesn't need Full Disk Access to look in ~/.Trash.
    func emptyTrash() async {
        guard !isEmptyingTrash else { return }
        actionProblem = nil
        actionNote = nil
        isEmptyingTrash = true
        defer { isEmptyingTrash = false }
        do {
            let count = Int(try await AppleScript.run("tell application \"Finder\" to count items of trash")) ?? 0
            guard count > 0 else {
                actionNote = "The Trash is already empty."
                return
            }
            let items = count == 1 ? "1 item" : "\(count) items"
            guard Alerts.confirm(
                title: "Empty the Trash?",
                message: "\(items) will be deleted permanently. This can't be undone.",
                confirm: "Empty Trash")
            else { return }
            try await AppleScript.run("tell application \"Finder\" to empty trash", timeout: 600)
        } catch let error as SwitchboardError {
            actionProblem = error
        } catch {
            actionProblem = .failed(error.localizedDescription)
        }
    }

    func ejectAll() async -> String {
        actionProblem = nil
        actionNote = nil
        let count = drives.drives.count
        guard count > 0 else { return "Nothing to eject" }
        let failures = await drives.ejectAll()
        if failures.isEmpty {
            let message = count == 1 ? "Ejected 1 drive" : "Ejected \(count) drives"
            actionNote = message + "."
            return message
        }
        let message = failures.joined(separator: ". ") + "."
        actionProblem = .failed(message)
        return message
    }

    func setLaunchAtLogin(_ on: Bool) {
        actionProblem = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            actionProblem = .failed("Couldn't change Launch at Login: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Keyboard shortcuts

    struct ShortcutTarget: Identifiable {
        let id: String
        let title: String
        let symbol: String
    }

    static let actionTargets = [
        ShortcutTarget(id: "screenSaver", title: "Start Screen Saver", symbol: "sparkles"),
        ShortcutTarget(id: "emptyTrash", title: "Empty Trash…", symbol: "trash"),
        ShortcutTarget(id: "ejectAll", title: "Eject Removable Drives", symbol: "eject"),
        ShortcutTarget(id: "pomodoro", title: "Start or Pause Pomodoro", symbol: "timer"),
    ]

    /// ⌃⌥⌘ plus a letter: macOS uses that combination only with digits and punctuation,
    /// and apps rarely use it at all. Key codes are positions on the keyboard.
    static let suggestedShortcuts: [String: (keyCode: UInt16, letter: String)] = [
        "darkMode": (2, "D"), "nightShift": (45, "N"),
        "hideDesktopIcons": (34, "I"), "hideDesktopWidgets": (13, "W"), "autohideDock": (40, "K"),
        "autohideMenuBar": (32, "U"), "showRecentApps": (15, "R"),
        "showHiddenFiles": (4, "H"), "showLibraryFolder": (37, "L"),
        "mute": (46, "M"), "muteMicrophone": (9, "V"), "keepAwake": (0, "A"), "bluetooth": (11, "B"),
        "screenSaver": (1, "S"), "emptyTrash": (17, "T"), "ejectAll": (14, "E"), "pomodoro": (35, "P"),
    ]

    /// Replaces every shortcut with the suggested set.
    func useSuggestedShortcuts() {
        shortcuts = Self.suggestedShortcuts.mapValues {
            HotKey(keyCode: $0.keyCode, modifiers: [.control, .option, .command], keyName: $0.letter)
        }
        registerShortcuts()
    }

    func clearShortcuts() {
        shortcuts = [:]
        registerShortcuts()
    }

    var settingTargets: [ShortcutTarget] {
        controls.map { ShortcutTarget(id: $0.id, title: $0.setting.title, symbol: $0.setting.symbol) }
    }

    /// Sets or clears a shortcut. A shortcut can only do one thing, so it's taken off
    /// anything else that had it.
    func setShortcut(_ key: HotKey?, for id: String) {
        var updated = shortcuts.filter { $0.value != key }
        updated[id] = key
        shortcuts = updated
        registerShortcuts()
    }

    /// While a shortcut is being typed in, the existing ones mustn't fire.
    func pauseShortcuts() {
        hotKeys.unregisterAll()
    }

    func registerShortcuts() {
        hotKeys.register(shortcuts)
        refusedShortcuts = hotKeys.refused
    }

    private func performShortcut(_ id: String) {
        Task {
            if let control = controls.first(where: { $0.id == id }) {
                await toggleFromShortcut(control)
                return
            }
            switch id {
            case "screenSaver":
                startScreenSaver()
            case "emptyTrash":
                await emptyTrash()
            case "ejectAll":
                showHUD(symbol: "eject", title: "Eject Removable Drives", detail: await ejectAll())
            case "pomodoro":
                pomodoro.timer.isRunning ? pomodoro.pause() : pomodoro.start()
                showHUD(symbol: "timer", title: pomodoro.timer.phase.title,
                        detail: pomodoro.timer.isRunning ? "Started" : "Paused")
            default:
                break
            }
        }
    }

    private func toggleFromShortcut(_ control: Control) async {
        let setting = control.setting
        control.refresh()
        guard let current = control.reading.state.isOn else {
            // A new user's first press asks for the permission, as the row's Allow… does.
            if let ask = setting.askForPermission {
                ask()
            } else if case .unavailable(let reason) = control.reading.state {
                showHUD(symbol: setting.symbol, title: setting.title, detail: reason)
            }
            return
        }
        await set(control, to: !current)
        if let problem = control.problem {
            showHUD(symbol: setting.symbol, title: setting.title, detail: problem.localizedDescription)
        } else if let now = control.reading.state.isOn, now != current {
            showHUD(symbol: setting.symbol, title: setting.title, detail: now ? "On" : "Off")
        }
    }

    /// The panel shows its own state; the HUD is for when it's closed.
    private func showHUD(symbol: String, title: String, detail: String) {
        guard !isPanelOpen else { return }
        HUD.show(symbol: symbol, title: title, detail: detail)
    }

    // MARK: Storage

    private static let shortcutsKey = "shortcuts"

    private static func loadShortcuts() -> [String: HotKey] {
        guard let data = UserDefaults.standard.data(forKey: shortcutsKey),
              let keys = try? JSONDecoder().decode([String: HotKey].self, from: data)
        else { return [:] }
        return keys
    }

    private static func saveShortcuts(_ keys: [String: HotKey]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(keys), forKey: shortcutsKey)
    }

    private static let originalsKey = "originalSettings"

    private static func loadOriginals() -> OriginalSettings {
        guard let data = UserDefaults.standard.data(forKey: originalsKey),
              let originals = try? JSONDecoder().decode(OriginalSettings.self, from: data)
        else { return OriginalSettings() }
        return originals
    }

    private static func save(_ originals: OriginalSettings) {
        UserDefaults.standard.set(try? JSONEncoder().encode(originals), forKey: originalsKey)
    }
}
