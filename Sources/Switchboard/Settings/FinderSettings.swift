import Foundation

private let finder = "com.apple.finder"

/// "Show Items: On Desktop" in System Settings → Desktop & Dock, stored as
/// WindowManager's StandardHideDesktopIcons. The desktop follows it at once. Items in
/// Stage Manager have their own setting, which is left alone.
///
/// Finder's older CreateDesktop hides the icons too, and Switchboard 1.0.x used it, so
/// it counts as on as well. Showing the icons again turns it back on, which needs a
/// Finder restart because Finder only reads it at launch.
@MainActor
final class HideDesktopIcons: SystemSetting {
    let id = "hideDesktopIcons"
    let title = "Hide Desktop Icons"
    let symbol = "eye.slash"

    private let windowManager = "com.apple.WindowManager"

    func read() -> Reading {
        let hidden = Prefs.bool("StandardHideDesktopIcons", in: windowManager) ?? false
        return Reading(state: hidden || finderHidesDesktop ? .on : .off)
    }

    func write(_ on: Bool) async throws {
        Prefs.set("StandardHideDesktopIcons", on, in: windowManager)
        if !on && finderHidesDesktop {
            await FinderRestarter.shared.restart { Prefs.set("CreateDesktop", true, in: finder) }
        }
    }

    private var finderHidesDesktop: Bool {
        !(Prefs.bool("CreateDesktop", in: finder) ?? true)
    }
}

/// Finder's AppleShowAllFiles. The desktop follows it at once, but Finder windows only
/// read it at launch, so Finder restarts.
@MainActor
final class ShowHiddenFiles: SystemSetting {
    let id = "showHiddenFiles"
    let title = "Show Hidden Files"
    let symbol = "doc.text.magnifyingglass"

    func read() -> Reading {
        Reading(state: Prefs.bool("AppleShowAllFiles", in: finder) ?? false ? .on : .off)
    }

    func write(_ on: Bool) async throws {
        await FinderRestarter.shared.restart { Prefs.set("AppleShowAllFiles", on, in: finder) }
    }
}

/// The hidden flag on ~/Library, the same one `chflags hidden` sets. It only affects the
/// home folder: a Library shortcut in Finder's sidebar stays either way, and the folder
/// still shows while Show Hidden Files is on. macOS updates sometimes hide it again; the
/// row shows it when they do.
@MainActor
final class ShowLibraryFolder: SystemSetting {
    let id = "showLibraryFolder"
    let title = "Show Library Folder"
    let symbol = "building.columns"

    private var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library", directoryHint: .isDirectory)
    }

    func read() -> Reading {
        var url = url
        url.removeAllCachedResourceValues()
        guard let hidden = try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden else {
            return Reading(state: .unavailable("Couldn't read ~/Library"))
        }
        return Reading(state: hidden ? .off : .on, detail: "In your home folder")
    }

    func write(_ on: Bool) async throws {
        var url = url
        var values = URLResourceValues()
        values.isHidden = !on
        try url.setResourceValues(values)
    }
}
