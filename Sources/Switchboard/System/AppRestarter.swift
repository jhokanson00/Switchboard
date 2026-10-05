import AppKit

/// The running copies of an app. NSRunningApplication's own lookup by bundle ID
/// sometimes comes back empty while the app is running (seen with Finder on macOS 27),
/// which made a restart skip the quit; the workspace's list doesn't.
@MainActor
private func runningApplications(_ bundleID: String) -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID && !$0.isTerminated }
}

/// Restarts the Dock so it rereads its preferences, like `killall Dock`. launchd starts
/// it again at once. Requests that arrive close together share one restart.
@MainActor
final class DockRestarter {
    static let shared = DockRestarter()

    private let bundleID = "com.apple.dock"
    private var pending: Task<Void, Never>?

    func restart() async {
        if let pending { return await pending.value }
        let task = Task {
            // Gather any other changes made in the same moment.
            try? await Task.sleep(for: .milliseconds(300))
            for app in runningApplications(self.bundleID) {
                kill(app.processIdentifier, SIGTERM)
            }
            self.pending = nil
        }
        pending = task
        await task.value
    }
}

/// Restarts Finder with new preferences. Finder writes its own settings back when it
/// quits, so a change made only while it's running is lost. So changes are written
/// before Finder quits (in case it has to be forced, when macOS starts it again at once)
/// and again once it's closed; then it opens again. Afterwards any folder windows Finder
/// didn't restore by itself are reopened where they were. Changes made close together
/// share one restart.
@MainActor
final class FinderRestarter {
    static let shared = FinderRestarter()

    private let bundleID = "com.apple.finder"
    private let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    private var changes: [() -> Void] = []
    private var pending: Task<Void, Never>?

    /// A Finder window showing a folder, e.g. "/Users/me/Documents/", and its left, top,
    /// right and bottom edges.
    private struct FolderWindow {
        let path: String
        let bounds: [Int]?
    }

    func restart(applying change: @escaping () -> Void) async {
        changes.append(change)
        // A change that arrives after a restart has written its batch waits for that
        // restart, then gets one of its own.
        while !changes.isEmpty {
            if let pending {
                await pending.value
                continue
            }
            let task = Task {
                await self.run()
                self.pending = nil
            }
            pending = task
            await task.value
        }
    }

    private func run() async {
        try? await Task.sleep(for: .milliseconds(300))
        let windows = await openFolders()
        let batch = changes
        changes = []

        batch.forEach { $0() }
        if await quit() {
            // Finder may have saved its old values on the way out.
            batch.forEach { $0() }
        }

        // If macOS already started it again, this just brings it forward.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        await reopen(windows)
    }

    /// Finder's folder windows, front to back. Windows without a folder (Recents,
    /// AirDrop) are left out.
    private func openFolders() async -> [FolderWindow] {
        // One window per line, its URL and edges separated by a tab: URLs never contain
        // tabs or line breaks, but folder names can contain commas, which AppleScript's own
        // list output would be split on.
        let script = """
            tell application "Finder"
                set folderURLs to URL of target of every Finder window
                set windowBounds to bounds of every Finder window
            end tell
            set windowLines to {}
            repeat with i from 1 to count of folderURLs
                set {l, t, r, b} to item i of windowBounds
                set end of windowLines to (item i of folderURLs as text) & tab & l & "," & t & "," & r & "," & b
            end repeat
            set AppleScript's text item delimiters to linefeed
            return windowLines as text
            """
        guard !running().isEmpty, let result = try? await AppleScript.run(script) else { return [] }
        return result.components(separatedBy: .newlines).compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 2, let path = URL(string: parts[0])?.path(percentEncoded: false) else { return nil }
            let bounds = parts[1].components(separatedBy: ",").compactMap { Int($0) }
            return FolderWindow(path: path, bounds: bounds.count == 4 ? bounds : nil)
        }
    }

    /// Reopens the folder windows Finder had open, where they were, except those it
    /// restored by itself: with "Close windows when quitting an application" off in
    /// System Settings, Finder brings its windows back on its own.
    private func reopen(_ windows: [FolderWindow]) async {
        guard !windows.isEmpty else { return }
        // Give Finder a moment to put its own windows back.
        try? await Task.sleep(for: .milliseconds(1500))
        var missing = windows
        for open in await openFolders() {
            if let index = missing.firstIndex(where: { $0.path == open.path }) { missing.remove(at: index) }
        }
        // Back to front, so the window that was in front ends up in front again.
        for window in missing.reversed() {
            let path = window.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            var script = """
                tell application "Finder"
                    set newWindow to make new Finder window to (POSIX file "\(path)" as alias)
                """
            if let bounds = window.bounds {
                script += "\n    set bounds of newWindow to {\(bounds.map(String.init).joined(separator: ", "))}"
            }
            script += "\nend tell"
            _ = try? await AppleScript.run(script)
        }
    }

    /// Quits Finder. Returns true if it quit normally, false if it had to be forced.
    private func quit() async -> Bool {
        let apps = running()
        guard !apps.isEmpty else { return true }
        let pids = Set(apps.map(\.processIdentifier))
        apps.forEach { $0.terminate() }
        if await waitForExit(of: pids, seconds: 5) { return true }
        // Finder didn't respond to Quit. Forced, it saves nothing on the way out, and
        // macOS starts it again with the settings already written.
        apps.forEach { $0.forceTerminate() }
        _ = await waitForExit(of: pids, seconds: 3)
        return false
    }

    /// Checks every 0.1 s, only while a restart is in progress. Asks the system about
    /// each process directly, since the workspace's list catches up a moment later.
    private func waitForExit(of pids: Set<pid_t>, seconds: Int) async -> Bool {
        func exited() -> Bool { pids.allSatisfy { kill($0, 0) != 0 && errno == ESRCH } }
        for _ in 0..<(seconds * 10) {
            if exited() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return exited()
    }

    private func running() -> [NSRunningApplication] {
        runningApplications(bundleID)
    }
}
