public struct PracticeTimer {
    public enum Status {
        case ready, running, paused, finished
    }

    private enum Countdown {
        case running(ContinuousClock.Instant)
        case paused(Duration)
    }

    private var countdown: Countdown?

    public init() {}

    public var deadline: ContinuousClock.Instant? {
        guard case .running(let deadline) = countdown else { return nil }
        return deadline
    }

    public static func supports(minutes: Int) -> Bool {
        (1...(Int.max / 60)).contains(minutes)
    }

    public func status(at now: ContinuousClock.Instant) -> Status {
        switch countdown {
        case nil: .ready
        case .running(let deadline): now < deadline ? .running : .finished
        case .paused: .paused
        }
    }

    public func remainingSeconds(at now: ContinuousClock.Instant) -> Int {
        let remaining: Duration
        switch countdown {
        case nil: remaining = .zero
        case .running(let deadline): remaining = max(.zero, now.duration(to: deadline))
        case .paused(let duration): remaining = duration
        }
        let (seconds, attoseconds) = remaining.components
        return Int(seconds) + (attoseconds > 0 ? 1 : 0)
    }

    public mutating func start(minutes: Int, at now: ContinuousClock.Instant) {
        guard countdown == nil, Self.supports(minutes: minutes) else { return }
        countdown = .running(now.advanced(by: .seconds(minutes * 60)))
    }

    public mutating func pause(at now: ContinuousClock.Instant) {
        guard let deadline, now < deadline else { return }
        countdown = .paused(now.duration(to: deadline))
    }

    public mutating func resume(at now: ContinuousClock.Instant) {
        guard case .paused(let remaining) = countdown else { return }
        countdown = .running(now.advanced(by: remaining))
    }

    public mutating func reset() {
        countdown = nil
    }
}
