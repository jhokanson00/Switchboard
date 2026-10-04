import AppKit

/// Reads the system appearance from the app's own effective appearance (which follows
/// the system and notifies on change); switches it through System Events.
@MainActor
final class DarkMode: SystemSetting {
    let id = "darkMode"
    let title = "Dark Mode"
    let symbol = "circle.lefthalf.filled"

    private var observation: NSKeyValueObservation?

    func read() -> Reading {
        let dark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let automatic = Prefs.bool("AppleInterfaceStyleSwitchesAutomatically", in: Prefs.global) ?? false
        return Reading(state: dark ? .on : .off, detail: automatic ? "Appearance is set to Auto" : nil)
    }

    func write(_ on: Bool) async throws {
        try await AppleScript.run("tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)")
    }

    func startObserving(_ changed: @escaping @MainActor () -> Void) {
        observation = NSApplication.shared.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in changed() }
        }
    }
}
