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
/// didn't restore by itself are reopened. Changes made close together share one restart.
@MainActor
final class FinderRestarter {
    static let shared = FinderRestarter()

    private let bundleID = "com.apple.finder"
    private let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    private var changes: [() -> Void] = []
    private var pending: Task<Void, Never>?

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
        let folders = await openFolders()
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
        await reopen(folders)
    }

    /// Folders shown in Finder windows, e.g. "/Users/me/Documents/". Windows without a
    /// folder (Recents, AirDrop) are left out.
    private func openFolders() async -> [String] {
        // One URL per line: URLs never contain line breaks, but folder names can contain
        // commas, which AppleScript's own list output would be split on.
        let script = """
            tell application "Finder" to set folderURLs to URL of target of every Finder window
            set AppleScript's text item delimiters to linefeed
            return folderURLs as text
            """
        guard !running().isEmpty, let result = try? await AppleScript.run(script) else { return [] }
        return result.components(separatedBy: .newlines)
            .compactMap { URL(string: $0)?.path(percentEncoded: false) }
    }

    /// Reopens the folders Finder had open, except those it restored by itself: with
    /// "Close windows when quitting an application" off in System Settings, Finder
    /// brings its windows back on its own.
    private func reopen(_ folders: [String]) async {
        guard !folders.isEmpty else { return }
        // Give Finder a moment to put its own windows back.
        try? await Task.sleep(for: .milliseconds(1500))
        var missing = folders
        for open in await openFolders() {
            if let index = missing.firstIndex(of: open) { missing.remove(at: index) }
        }
        for folder in missing {
            let path = folder.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            _ = try? await AppleScript.run("tell application \"Finder\" to make new Finder window to (POSIX file \"\(path)\" as alias)")
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
