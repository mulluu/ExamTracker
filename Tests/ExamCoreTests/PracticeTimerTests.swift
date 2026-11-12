import Testing
@testable import ExamCore

struct PracticeTimerTests {
    @Test func countdownUsesElapsedTimeAndStopsAtZero() {
        let start = ContinuousClock.now
        var timer = PracticeTimer()
        timer.start(minutes: 2, at: start)

        let delayedUpdate = start.advanced(by: .seconds(65) + .milliseconds(200))
        #expect(timer.status(at: delayedUpdate) == .running)
        #expect(timer.remainingSeconds(at: delayedUpdate) == 55)

        let deadline = start.advanced(by: .seconds(120))
        #expect(timer.status(at: deadline) == .finished)
        #expect(timer.remainingSeconds(at: deadline) == 0)
        let latePause = deadline.advanced(by: .seconds(5))
        timer.pause(at: latePause)
        #expect(timer.status(at: latePause) == .finished)
        #expect(timer.remainingSeconds(at: latePause) == 0)
    }

    @Test func pauseAndResumePreserveFractionalSeconds() {
        let start = ContinuousClock.now
        var timer = PracticeTimer()
        timer.start(minutes: 1, at: start)
        timer.pause(at: start.advanced(by: .seconds(58) + .milliseconds(750)))

        let resumedAt = start.advanced(by: .seconds(150))
        #expect(timer.status(at: resumedAt) == .paused)
        #expect(timer.remainingSeconds(at: resumedAt) == 2)

        timer.resume(at: resumedAt)
        let stillRunning = resumedAt.advanced(by: .milliseconds(1_249))
        #expect(timer.status(at: stillRunning) == .running)
        #expect(timer.remainingSeconds(at: stillRunning) == 1)
        #expect(timer.status(at: resumedAt.advanced(by: .milliseconds(1_250))) == .finished)
    }

    @Test func resetAllowsStartingWithANewDuration() {
        let start = ContinuousClock.now
        var timer = PracticeTimer()
        timer.start(minutes: 1, at: start)

        let restart = start.advanced(by: .seconds(65))
        timer.reset()
        #expect(timer.status(at: restart) == .ready)

        timer.start(minutes: 3, at: restart)
        #expect(timer.status(at: restart) == .running)
        #expect(timer.remainingSeconds(at: restart) == 180)
    }

    @Test(arguments: [0, -1, Int.max])
    func invalidDurationLeavesTimerReady(minutes: Int) {
        let now = ContinuousClock.now
        var timer = PracticeTimer()
        timer.start(minutes: minutes, at: now)
        #expect(timer.status(at: now) == .ready)
    }
}
