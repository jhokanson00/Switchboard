import AppKit

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
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                kill(app.processIdentifier, SIGTERM)
            }
            self.pending = nil
        }
        pending = task
        await task.value
    }
}

/// Restarts Finder with new preferences. Finder writes its own settings back when it
/// quits, so a change made while it's running is lost. Instead Finder quits first, the
/// changes are written while it's closed, and then it opens again with the same folders
/// it had open. Changes made close together share one restart.
@MainActor
final class FinderRestarter {
    static let shared = FinderRestarter()

    private let bundleID = "com.apple.finder"
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
        await quit()

        let batch = changes
        changes = []
        batch.forEach { $0() }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            configuration: configuration)
        // A quit Finder doesn't reopen its windows, so open the same folders again.
        for folder in folders {
            let path = folder.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            _ = try? await AppleScript.run("tell application \"Finder\" to make new Finder window to (POSIX file \"\(path)\" as alias)")
        }
    }

    /// Folders shown in Finder windows. Windows without a folder (Recents, AirDrop) are
    /// left out.
    private func openFolders() async -> [String] {
        guard !running().isEmpty,
              let result = try? await AppleScript.run("tell application \"Finder\" to get URL of target of every Finder window")
        else { return [] }
        let urls: [String]
        if result.numberOfItems > 0 {
            urls = (1...result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }
        } else {
            urls = result.stringValue.map { [$0] } ?? []
        }
        return urls.compactMap { URL(string: $0)?.path(percentEncoded: false) }
    }

    private func quit() async {
        let apps = running()
        guard !apps.isEmpty else { return }
        apps.forEach { $0.terminate() }
        if await waitForQuit(seconds: 5) { return }
        // Finder didn't respond to Quit; stop it the way `killall` would.
        running().forEach { kill($0.processIdentifier, SIGTERM) }
        _ = await waitForQuit(seconds: 3)
    }

    /// Checks every 0.1 s, only while a restart is in progress.
    private func waitForQuit(seconds: Int) async -> Bool {
        for _ in 0..<(seconds * 10) {
            if running().isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return running().isEmpty
    }

    private func running() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }
    }
}
