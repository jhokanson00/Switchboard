import Foundation
import Testing
@testable import SwitchboardKit

private let t0 = Date(timeIntervalSinceReferenceDate: 0)
private func minutes(_ m: Double) -> TimeInterval { m * 60 }

@Test func startsIdleOnFocus() {
    let p = Pomodoro()
    #expect(p.phase == .focus)
    #expect(p.status == .idle)
    #expect(p.remaining(at: t0) == minutes(25))
}

@Test func focusEndingStartsShortBreakFromTheScheduledEnd() {
    var p = Pomodoro()
    p.start(at: t0)
    // Checked late, as after App Nap: the break still started when focus ended.
    let events = p.advance(to: t0 + minutes(27))
    #expect(events == [.focusEnded(next: .shortBreak)])
    #expect(p.status == .running(endsAt: t0 + minutes(30)))
    #expect(p.remaining(at: t0 + minutes(27)) == minutes(3))
}

@Test func breakEndingWaitsForTheNextFocus() {
    var p = Pomodoro()
    p.start(at: t0)
    let events = p.advance(to: t0 + minutes(60))
    #expect(events == [.focusEnded(next: .shortBreak), .breakEnded])
    #expect(p.phase == .focus)
    #expect(p.status == .idle)
    #expect(p.completedInCycle == 1)
}

@Test func fourthFocusEndsInLongBreakThenCycleResets() {
    var p = Pomodoro()
    var now = t0
    for _ in 0..<3 {
        p.start(at: now)
        now += minutes(30)
        _ = p.advance(to: now)
    }
    p.start(at: now)
    #expect(p.advance(to: now + minutes(25)) == [.focusEnded(next: .longBreak)])
    #expect(p.advance(to: now + minutes(40)) == [.breakEnded])
    #expect(p.completedInCycle == 0)
}

@Test func pauseAndResumeKeepTheRemainingTime() {
    var p = Pomodoro()
    p.start(at: t0)
    p.pause(at: t0 + minutes(10))
    #expect(p.remaining(at: t0 + minutes(100)) == minutes(15))
    #expect(p.advance(to: t0 + minutes(100)).isEmpty)
    p.start(at: t0 + minutes(100))
    #expect(p.status == .running(endsAt: t0 + minutes(115)))
}

@Test func skipEndsThePhaseNow() {
    var p = Pomodoro()
    p.start(at: t0)
    #expect(p.skip(at: t0 + minutes(5)) == .focusEnded(next: .shortBreak))
    #expect(p.status == .running(endsAt: t0 + minutes(10)))
}

@Test func upcomingEventsCoverFocusAndTheBreakAfterIt() {
    var p = Pomodoro()
    p.start(at: t0)
    let upcoming = p.upcomingEvents()
    #expect(upcoming.map(\.date) == [t0 + minutes(25), t0 + minutes(30)])
    #expect(upcoming.map(\.event) == [.focusEnded(next: .shortBreak), .breakEnded])
    // Asking doesn't change anything.
    #expect(p.status == .running(endsAt: t0 + minutes(25)))
}

@Test func noUpcomingEventsWhenPausedOrIdle() {
    var p = Pomodoro()
    #expect(p.upcomingEvents().isEmpty)
    p.start(at: t0)
    p.pause(at: t0 + 1)
    #expect(p.upcomingEvents().isEmpty)
}
