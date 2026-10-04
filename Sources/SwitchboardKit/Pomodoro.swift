import Foundation

public enum PomodoroPhase: String, Codable, Sendable {
    case focus, shortBreak, longBreak

    public var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }
}

public struct PomodoroSettings: Codable, Equatable, Sendable {
    public var focus: TimeInterval = 25 * 60
    public var shortBreak: TimeInterval = 5 * 60
    public var longBreak: TimeInterval = 15 * 60
    public var sessionsBeforeLongBreak = 4

    /// Focus lengths offered in the panel, in minutes.
    public static let focusChoices = [5, 25, 30, 45, 60]

    public init() {}

    public func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}

/// The Pomodoro cycle as plain values: every change takes the current time, so nothing
/// needs a ticking timer. A break starts by itself when focus ends; the next focus
/// waits for you.
public struct Pomodoro: Codable, Equatable, Sendable {
    public enum Status: Codable, Equatable, Sendable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
    }

    public enum Event: Equatable, Sendable {
        case focusEnded(next: PomodoroPhase)
        case breakEnded
    }

    public var settings: PomodoroSettings
    public private(set) var phase: PomodoroPhase = .focus
    public private(set) var status: Status = .idle
    /// Focus sessions finished since the last long break.
    public private(set) var completedInCycle = 0

    public init(settings: PomodoroSettings = PomodoroSettings()) {
        self.settings = settings
    }

    public var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    public func remaining(at now: Date) -> TimeInterval {
        switch status {
        case .idle: settings.duration(of: phase)
        case .paused(let remaining): remaining
        case .running(let end): max(0, end.timeIntervalSince(now))
        }
    }

    /// Starts the current phase, or resumes it when paused.
    public mutating func start(at now: Date) {
        switch status {
        case .idle: status = .running(endsAt: now + settings.duration(of: phase))
        case .paused(let remaining): status = .running(endsAt: now + remaining)
        case .running: break
        }
    }

    public mutating func pause(at now: Date) {
        if case .running(let end) = status {
            status = .paused(remaining: max(0, end.timeIntervalSince(now)))
        }
    }

    public mutating func reset() {
        phase = .focus
        status = .idle
        completedInCycle = 0
    }

    /// Ends the current phase now, exactly as if its time had run out.
    @discardableResult
    public mutating func skip(at now: Date) -> Event {
        finishPhase(endedAt: now)
    }

    /// Catches up with the clock: finishes every phase whose end time has passed. Works
    /// however late it's called (after sleep, or when App Nap delays the app).
    public mutating func advance(to now: Date) -> [Event] {
        var events: [Event] = []
        while case .running(let end) = status, end <= now {
            events.append(finishPhase(endedAt: end))
        }
        return events
    }

    /// What will happen, and when, if nobody touches the timer. Used to schedule
    /// notifications ahead of time so they arrive on time even if the app is napping.
    public func upcomingEvents() -> [(date: Date, event: Event)] {
        var copy = self
        var upcoming: [(date: Date, event: Event)] = []
        while case .running(let end) = copy.status {
            upcoming.append((end, copy.finishPhase(endedAt: end)))
        }
        return upcoming
    }

    private mutating func finishPhase(endedAt end: Date) -> Event {
        switch phase {
        case .focus:
            completedInCycle += 1
            phase = completedInCycle >= settings.sessionsBeforeLongBreak ? .longBreak : .shortBreak
            status = .running(endsAt: end + settings.duration(of: phase))
            return .focusEnded(next: phase)
        case .shortBreak, .longBreak:
            if phase == .longBreak { completedInCycle = 0 }
            phase = .focus
            status = .idle
            return .breakEnded
        }
    }
}
