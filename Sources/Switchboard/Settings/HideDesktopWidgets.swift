import Foundation

/// "Show Widgets: On Desktop" in System Settings → Desktop & Dock, stored as
/// WindowManager's StandardHideWidgets. Widgets in Stage Manager have their own
/// setting, which is left alone.
@MainActor
final class HideDesktopWidgets: SystemSetting {
    let id = "hideDesktopWidgets"
    let title = "Hide Desktop Widgets"
    let symbol = "widget.small"

    private let domain = "com.apple.WindowManager"

    func read() -> Reading {
        Reading(state: Prefs.bool("StandardHideWidgets", in: domain) ?? false ? .on : .off)
    }

    func write(_ on: Bool) async throws {
        Prefs.set("StandardHideWidgets", on, in: domain)
    }
}
