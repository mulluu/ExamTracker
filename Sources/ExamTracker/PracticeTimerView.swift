import ExamCore
import SwiftUI

struct PracticeTimerView: View {
    @TrackerState private var timer = PracticeTimer()
    @TrackerState private var minutesInput = "25"
    @TrackerState private var now = ContinuousClock.now

    var body: some View {
        let deadline = timer.deadline
        let status = timer.status(at: now)

        Group {
            switch status {
            case .ready:
                settings
            case .running:
                HStack(spacing: 8) {
                    Text("Осталось").foregroundStyle(.secondary)
                    controls {
                        Button("Пауза", systemImage: "pause.fill") {
                            now = ContinuousClock.now
                            timer.pause(at: now)
                        }
                    }
                }
            case .paused:
                HStack(spacing: 8) {
                    Text("На паузе").foregroundStyle(.secondary)
                    controls {
                        Button("Продолжить", systemImage: "play.fill") {
                            now = ContinuousClock.now
                            timer.resume(at: now)
                        }
                    }
                }
            case .finished:
                HStack(spacing: 8) {
                    Label("Время вышло", systemImage: "clock.badge.exclamationmark")
                    controls {}
                }
            }
        }
        .task(id: deadline) {
            guard let deadline else { return }
            let clock = ContinuousClock()
            while !Task.isCancelled {
                let current = clock.now
                now = current
                if current >= deadline { return }
                do {
                    try await clock.sleep(until: min(deadline, current.advanced(by: .seconds(1))))
                } catch {
                    return
                }
            }
        }
    }

    private var settings: some View {
        let minutes = validatedMinutes
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Таймер").foregroundStyle(.secondary)
                TextField("Длительность в минутах", text: $minutesInput)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                Text("мин")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Button("Запустить", systemImage: "play.fill") {
                    guard let minutes else { return }
                    now = ContinuousClock.now
                    timer.start(minutes: minutes, at: now)
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .disabled(minutes == nil)
            }
            if minutes == nil && !minutesInput.cleaned.isEmpty {
                Text("Введите положительное целое число минут.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var validatedMinutes: Int? {
        guard let minutes = Int(minutesInput.cleaned), PracticeTimer.supports(minutes: minutes) else {
            return nil
        }
        return minutes
    }

    private func controls<Actions: View>(@ViewBuilder actions: () -> Actions) -> some View {
        let duration = Duration.seconds(timer.remainingSeconds(at: now))
        return HStack(spacing: 8) {
            Text(duration.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2))))
                .font(.headline.monospacedDigit())
                .accessibilityLabel(duration.formatted(.units(allowed: [.minutes, .seconds])))
            actions()
            Button("Сбросить") { timer.reset() }
        }
        .buttonStyle(.bordered)
    }
}
