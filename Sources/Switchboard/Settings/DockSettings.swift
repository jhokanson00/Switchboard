import Foundation

private let dock = "com.apple.dock"

/// Through System Events, which applies the change at once without restarting the Dock.
@MainActor
final class AutohideDock: SystemSetting {
    let id = "autohideDock"
    let title = "Autohide Dock"
    let symbol = "dock.rectangle"

    func read() -> Reading {
        Reading(state: Prefs.bool("autohide", in: dock) ?? false ? .on : .off)
    }

    func write(_ on: Bool) async throws {
        try await AppleScript.run("tell application \"System Events\" to tell dock preferences to set autohide to \(on)")
    }
}

/// Hides the menu bar on the desktop. System Events changes only `_HIHideMenuBar`, so
/// the separate "in full screen" choice in System Settings is left as it was. The menu
/// bar stays up while the pointer is near it, which includes while this panel is open.
@MainActor
final class AutohideMenuBar: SystemSetting {
    let id = "autohideMenuBar"
    let title = "Autohide Menu Bar"
    let symbol = "menubar.rectangle"
    let closesPanel = true

    func read() -> Reading {
        Reading(state: Prefs.bool("_HIHideMenuBar", in: Prefs.global) ?? false ? .on : .off)
    }

    func write(_ on: Bool) async throws {
        try await AppleScript.run("tell application \"System Events\" to tell dock preferences to set autohide menu bar to \(on)")
    }
}

/// The Dock only reads show-recents at launch, so it restarts (a brief flicker).
@MainActor
final class ShowRecentApps: SystemSetting {
    let id = "showRecentApps"
    let title = "Show Recent Apps in Dock"
    let symbol = "clock.arrow.circlepath"

    func read() -> Reading {
        Reading(state: Prefs.bool("show-recents", in: dock) ?? true ? .on : .off)
    }

    func write(_ on: Bool) async throws {
        Prefs.set("show-recents", on, in: dock)
        await DockRestarter.shared.restart()
    }
}
