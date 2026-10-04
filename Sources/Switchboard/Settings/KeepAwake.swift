import AppKit
import IOKit.pwr_mgt

/// Keeps the display (and so the Mac) awake with a power assertion, like `caffeinate -d`
/// but without a separate process. macOS drops the assertion if Switchboard quits.
@MainActor
final class KeepAwake: SystemSetting {
    let id = "keepAwake"
    let title = "Keep Awake"
    let symbol = "cup.and.saucer"
    let restorable = false

    enum Mode: Equatable {
        case indefinitely
        case duration(TimeInterval)
        /// Until that app quits, e.g. while Final Cut Pro exports.
        case whileRunning(pid: pid_t, name: String)
    }

    static let durations: [(title: String, seconds: TimeInterval)] = [
        ("1 Hour", 3600), ("2 Hours", 2 * 3600), ("4 Hours", 4 * 3600), ("8 Hours", 8 * 3600),
    ]

    /// Used the next time Keep Awake turns on.
    var mode: Mode = .indefinitely

    private var assertion: IOPMAssertionID?
    private var activeMode: Mode?
    private var endsAt: Date?
    private var expiry: Task<Void, Never>?
    private var appObserver: NSObjectProtocol?
    private var changed: (@MainActor () -> Void)?

    func read() -> Reading {
        guard assertion != nil, let activeMode else { return Reading(state: .off) }
        let detail: String
        switch activeMode {
        case .indefinitely: detail = "Until turned off"
        case .duration: detail = "Until \(endsAt?.formatted(date: .omitted, time: .shortened) ?? "later")"
        case .whileRunning(_, let name): detail = "While \(name) is open"
        }
        return Reading(state: .on, detail: detail)
    }

    func write(_ on: Bool) async throws {
        release()
        guard on else { return }

        if case .whileRunning(let pid, let name) = mode {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
                throw SwitchboardError.failed("\(name) isn't open anymore.")
            }
        }

        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Switchboard: Keep Awake" as CFString,
            &id)
        guard result == kIOReturnSuccess else {
            throw SwitchboardError.failed("macOS refused to keep the Mac awake (\(result)).")
        }
        assertion = id
        activeMode = mode

        switch mode {
        case .indefinitely:
            break
        case .duration(let seconds):
            endsAt = Date.now.addingTimeInterval(seconds)
            // One wake-up at the end, not a ticking timer.
            expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds), tolerance: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.expire()
            }
        case .whileRunning(let pid, _):
            // macOS announces when an app quits; nothing is checked in between.
            appObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.processIdentifier == pid else { return }
                MainActor.assumeIsolated { self?.expire() }
            }
        }
    }

    func startObserving(_ changed: @escaping @MainActor () -> Void) {
        self.changed = changed
    }

    /// Apps in the Dock that Keep Awake can wait for, sorted by name.
    static func openApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0 != .current && $0.localizedName != nil }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func expire() {
        release()
        changed?()
    }

    private func release() {
        expiry?.cancel()
        expiry = nil
        endsAt = nil
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        appObserver = nil
        activeMode = nil
        if let assertion { IOPMAssertionRelease(assertion) }
        assertion = nil
    }
}
