import Foundation
import Observation
import SwitchboardKit
import UserNotifications

/// Drives the Pomodoro timer with one-shot wake-ups (once a minute at most, for the menu
/// bar countdown) and schedules its notifications in advance, so they arrive on time
/// even if macOS naps the app.
@MainActor
@Observable
final class PomodoroModel {
    private(set) var timer: Pomodoro {
        didSet { Self.save(timer) }
    }
    /// Minutes left, for the menu bar. Nil when the timer isn't running.
    private(set) var menuBarText: String?

    private var wake: Task<Void, Never>?
    private let notifications = NotificationPresenter()

    init() {
        timer = Self.load()
        catchUp()
    }

    func start() {
        notifications.requestPermissionOnce()
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

    /// Finishes any phases whose time is up. Their notifications were already scheduled.
    func catchUp() {
        _ = timer.advance(to: .now)
        changed()
    }

    private func changed() {
        notifications.schedule(timer.upcomingEvents(), settings: timer.settings)
        updateMenuBarText()
        scheduleWake()
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
            content.sound = .default
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
