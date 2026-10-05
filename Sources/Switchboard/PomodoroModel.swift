import Foundation
import Observation
import SwitchboardKit
import UserNotifications

/// Drives the Pomodoro timer with one-shot wake-ups (once a minute at most, for the menu
/// bar countdown). When a phase ends it plays a sound and shows a pop-up; with the
/// pop-up turned off, it schedules notifications instead. While the timer runs, macOS
/// is asked not to nap the app, so the end arrives on time.
@MainActor
@Observable
final class PomodoroModel {
    private(set) var timer: Pomodoro {
        didSet { Self.save(timer) }
    }
    /// Minutes left, for the menu bar. Nil when the timer isn't running.
    private(set) var menuBarText: String?

    /// The sound played three times when a phase ends; nil for none.
    private(set) var alertSound: String? = UserDefaults.standard.object(forKey: soundKey) == nil
        ? "Glass" : UserDefaults.standard.string(forKey: soundKey)
    /// A pop-up in the middle of the screen when a phase ends, instead of a notification.
    private(set) var showsPopUp = UserDefaults.standard.object(forKey: popUpKey) as? Bool ?? true

    private var wake: Task<Void, Never>?
    private var activity: NSObjectProtocol?
    private let notifications = NotificationPresenter()

    init() {
        timer = Self.load()
        catchUp()
    }

    func start() {
        if !showsPopUp { notifications.requestPermissionOnce() }
        timer.start(at: .now)
        changed()
    }

    func pause() {
        timer.pause(at: .now)
        changed()
    }

    func skip() {
        timer.skip(at: .now)
        changed()
    }

    func reset() {
        timer.reset()
        changed()
    }

    var focusMinutes: Int { Int(timer.settings.focus / 60) }

    /// Takes effect from the next focus session; one already running keeps its end time.
    func setFocusMinutes(_ minutes: Int) {
        timer.settings.focus = TimeInterval(minutes * 60)
        changed()
    }

    /// Finishes any phases whose time is up, and announces the last one. Not one that
    /// ended long ago, while the Mac slept or Switchboard wasn't running.
    func catchUp() {
        let now = Date.now
        let ended = timer.upcomingEvents().filter { $0.date <= now }
        _ = timer.advance(to: now)
        changed()
        if let last = ended.last, now.timeIntervalSince(last.date) < 10 * 60 {
            announce(last.event)
        }
    }

    // MARK: Alerts

    /// Plays the new sound once, as a preview.
    func setAlertSound(_ name: String?) {
        alertSound = name
        UserDefaults.standard.set(name ?? "", forKey: Self.soundKey)
        if let name { PomodoroAlert.play(name, times: 1) }
        changed()
    }

    func setShowsPopUp(_ on: Bool) {
        showsPopUp = on
        UserDefaults.standard.set(on, forKey: Self.popUpKey)
        if !on { notifications.requestPermissionOnce() }
        changed()
    }

    /// What the end of a focus session will look and sound like.
    func testAlert() {
        if let alertSound { PomodoroAlert.play(alertSound) }
        guard showsPopUp else { return }
        PomodoroAlert.show(
            symbol: "bell", title: "Focus session done",
            message: "This is a test. When a focus session or break ends, you'll hear and see this.",
            choices: [.init(title: "OK") {}])
    }

    private func announce(_ event: Pomodoro.Event) {
        if let alertSound { PomodoroAlert.play(alertSound) }
        guard showsPopUp else { return }
        switch event {
        case .focusEnded(let next):
            let minutes = Int(timer.settings.duration(of: next) / 60)
            let kind = next == .longBreak ? "long break" : "break"
            PomodoroAlert.show(
                symbol: "cup.and.saucer", title: "Focus session done",
                message: "Your \(minutes)-minute \(kind) has started.",
                choices: [
                    .init(title: "Skip Break") { [weak self] in self?.skipBreak() },
                    .init(title: "OK") {},
                ])
        case .breakEnded:
            PomodoroAlert.show(
                symbol: "timer", title: "Break's over",
                message: "Start the next focus session when you're ready.",
                choices: [
                    .init(title: "Later") {},
                    .init(title: "Start Focus") { [weak self] in self?.start() },
                ])
        }
    }

    /// Ends the break, if it's still going, and starts the next focus session.
    private func skipBreak() {
        if timer.phase != .focus { timer.skip(at: .now) }
        start()
    }

    private func changed() {
        notifications.schedule(showsPopUp ? [] : timer.upcomingEvents(), settings: timer.settings)
        updateMenuBarText()
        scheduleWake()
        keepAwakeWhileRunning()
    }

    /// Without this, macOS may nap Switchboard while it has no windows open and wake it
    /// late, so the sound and pop-up would come after the phase ended.
    private func keepAwakeWhileRunning() {
        if timer.isRunning, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Pomodoro timer running")
        } else if !timer.isRunning, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func updateMenuBarText() {
        guard timer.isRunning else {
            menuBarText = nil
            return
        }
        let minutes = Int((timer.remaining(at: .now) / 60).rounded(.up))
        let text = "\(max(minutes, 1))m"
        if text != menuBarText { menuBarText = text }
    }

    /// Wakes when the menu bar's minute count next changes (or the phase ends).
    private func scheduleWake() {
        wake?.cancel()
        guard timer.isRunning else { return }
        let remaining = timer.remaining(at: .now)
        let minutesShown = (remaining / 60).rounded(.up)
        let delay = max(0.5, remaining - (minutesShown - 1) * 60)
        wake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.catchUp()
        }
    }

    // MARK: Storage

    private static let key = "pomodoro"
    private static let soundKey = "pomodoroSound"
    private static let popUpKey = "pomodoroPopUp"

    private static func load() -> Pomodoro {
        guard let data = UserDefaults.standard.data(forKey: key),
              let timer = try? JSONDecoder().decode(Pomodoro.self, from: data)
        else { return Pomodoro() }
        return timer
    }

    private static func save(_ timer: Pomodoro) {
        UserDefaults.standard.set(try? JSONEncoder().encode(timer), forKey: key)
    }
}

/// Pomodoro notifications. Also shows them while the panel is open, which macOS
/// otherwise suppresses for the active app.
private final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var askedForPermission = false

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermissionOnce() {
        guard !askedForPermission else { return }
        askedForPermission = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func schedule(_ upcoming: [(date: Date, event: Pomodoro.Event)], settings: PomodoroSettings) {
        center.removeAllPendingNotificationRequests()
        for (index, item) in upcoming.enumerated() {
            let interval = item.date.timeIntervalSinceNow
            guard interval > 0 else { continue }
            let content = UNMutableNotificationContent()
            switch item.event {
            case .focusEnded(let next):
                let minutes = Int(settings.duration(of: next) / 60)
                content.title = "Focus session done"
                content.body = "Take a \(minutes)-minute break."
            case .breakEnded:
                content.title = "Break's over"
                content.body = "Start the next focus session when you're ready."
            }
            // Switchboard plays its own sound when the phase ends.
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: "pomodoro-\(index)", content: content, trigger: trigger))
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
