import Charts
import ExamCore
import SwiftUI

struct Dashboard: View {
    let exam: Exam
    let ai: AIConfiguration
    let showSettings: () -> Void
    @TrackerState private var explanation: TopicStat?

    @TrackerState private var primaryScale = false

    var body: some View {
        let attempts = exam.examAttempts
        let finalAttempts = attempts.filter(\.hasFinalScore)
        let primaryAttempts = attempts.filter { $0.primaryScore != nil }
        let usingPrimary = !primaryAttempts.isEmpty && (finalAttempts.isEmpty || primaryScale)
        let recent = usingPrimary ? primaryAttempts : finalAttempts
        let maxima = Set(recent.map { usingPrimary ? ($0.primaryScore?.maximum ?? $0.maximum) : $0.maximum })
        let uniformMaximum = maxima.count == 1 ? maxima.first : nil
        let latest = recent.last.map { attempt in
            let primary = usingPrimary ? attempt.primaryScore : nil
            return "\(points(primary?.earned ?? attempt.earned)) / \(points(primary?.maximum ?? attempt.maximum))"
        } ?? "—"
        let topics = exam.topicStats
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                metric(usingPrimary ? "Последний первичный балл" : "Последний итоговый балл", latest, icon: "flag.checkered")
                metric("Всего попыток", "\(exam.attempts.count)", icon: "checkmark.circle")
                metric("Тем с результатами", "\(topics.count)", icon: "list.bullet.rectangle")
            }
            Surface {
                HStack {
                    Label("Динамика пробников", systemImage: "chart.xyaxis.line").font(.headline)
                    Spacer()
                    if !primaryAttempts.isEmpty && !finalAttempts.isEmpty {
                        Picker("Шкала", selection: $primaryScale) {
                            Text("Итоговые").tag(false)
                            Text("Первичные").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    } else if usingPrimary {
                        Text("Первичные баллы").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if recent.isEmpty {
                    Text("Запишите результат пробника, чтобы увидеть график.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 22)
                } else {
                    scoreChart(recent: recent, usingPrimary: usingPrimary, scale: uniformMaximum)
                    if uniformMaximum == nil {
                        Text("В пробниках разные максимумы. График показывает долю набранных баллов.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Surface {
                Label("Успеваемость по темам", systemImage: "scope").font(.headline)
                if topics.isEmpty {
                    Text("При записи результата добавьте баллы по заданиям или решите тренировку.")
                        .foregroundStyle(.secondary)
                }
                ForEach(topics) { topic in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(topic.name).font(.subheadline.weight(.semibold))
                            ProgressView(value: topic.ratio)
                                .tint(topic.ratio < 0.6 ? .orange : .mint)
                            Text(topic.maximum.isFinite ? "Оценено заданий — \(topic.count) · \(points(topic.earned)) из \(points(topic.maximum)) баллов" : "Оценено заданий — \(topic.count)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(topic.ratio.formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                        if ai.provider != .offline && topic.ratio < 1 {
                            Button("Разобрать с ИИ") {
                                if !ai.isConfigured { showSettings() } else { explanation = topic }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $explanation) { topic in
            ExplanationView(exam: exam, topic: topic, ai: ai)
        }
    }

    private func scoreChart(recent: [Attempt], usingPrimary: Bool, scale: Double?) -> some View {
        let upper = scale ?? 1
        let target = (exam.target / exam.maximum) * upper
        return Chart {
            if !usingPrimary && (0...upper).contains(target) {
                RuleMark(y: .value("Цель", target))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
            ForEach(Array(recent.enumerated()), id: \.element.id) { index, attempt in
                let earned = usingPrimary ? (attempt.primaryScore?.earned ?? attempt.earned) : attempt.earned
                let maximum = usingPrimary ? (attempt.primaryScore?.maximum ?? attempt.maximum) : attempt.maximum
                let score = scale == nil ? earned / maximum : earned
                LineMark(x: .value("Номер пробника", index + 1), y: .value("Результат", score))
                    .foregroundStyle(.mint)
                PointMark(x: .value("Номер пробника", index + 1), y: .value("Результат", score))
                    .foregroundStyle(.mint)
                    .accessibilityLabel(attempt.title)
                    .accessibilityValue("\(points(earned)) из \(points(maximum))")
            }
        }
        .chartYScale(domain: 0...upper)
        .chartXScale(domain: 0.5...(Double(recent.count) + 0.5))
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 5)) { value in
            AxisGridLine()
            AxisValueLabel {
                if let mark = value.as(Double.self) {
                    Text(scale == nil ? mark.formatted(.percent) : points(mark))
                }
            }
        } }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: min(7, recent.count))) { value in
            if let index = value.as(Double.self), index.rounded() == index, index >= 1, index <= Double(recent.count) {
                AxisTick()
                AxisValueLabel { Text("\(Int(index))") }
            }
        } }
        .frame(height: 180)
        .accessibilityLabel("График результатов пробников")
    }

    private func metric(_ title: String, _ value: String, icon: String) -> some View {
        Surface {
            Image(systemName: icon).font(.title3).foregroundStyle(.mint)
            Text(value).font(.system(.title, design: .rounded).weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct HistoryView: View {
    let attempts: [Attempt]
    let remove: (Attempt) -> Void

    var body: some View {
        Surface {
            Label("История результатов", systemImage: "clock").font(.headline)
            if attempts.isEmpty {
                Text("Здесь появятся пробники и результаты тренировок.")
                    .foregroundStyle(.secondary)
            }
            ForEach(attempts.sorted { $0.date > $1.date }) { attempt in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        if !attempt.isPractice && !attempt.scores.contains(where: { $0.earned != nil }) {
                            Text("Сохранён общий балл.").foregroundStyle(.secondary)
                        }
                        ForEach(attempt.scores) { score in
                            if attempt.isPractice || score.earned != nil {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let earned = score.earned {
                                        Text("\(score.topic) · \(points(earned)) / \(points(score.maximum))")
                                    } else {
                                        Text("\(score.topic) · Без оценки")
                                    }
                                    if let question = score.question { Text(question) }
                                    if let response = score.response { LabeledContent("Ваш ответ", value: response) }
                                    if let answer = score.expectedAnswer { LabeledContent("Ответ в наборе", value: answer) }
                                    if !score.note.isEmpty { Text(score.note).foregroundStyle(.secondary) }
                                }
                            }
                        }
                        Button("Удалить результат", role: .destructive) { remove(attempt) }
                    }
                    .padding(.vertical, 8)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(attempt.title).fontWeight(.semibold)
                            Text("\(attempt.isPractice ? "Тренировка" : "Пробник") · \(attempt.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            if attempt.isPractice && attempt.maximum == 0 {
                                Text("Без оценки").foregroundStyle(.secondary)
                            } else if attempt.isPractice || attempt.hasFinalScore {
                                Text("\(points(attempt.earned)) / \(points(attempt.maximum))").monospacedDigit()
                            }
                            if let score = attempt.primaryScore {
                                Text("Первичные \(points(score.earned)) / \(points(score.maximum))")
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }
}

private struct ExplanationView: View {
    let exam: Exam
    let topic: TopicStat
    let ai: AIConfiguration
    @Environment(\.dismiss) private var dismiss
    @TrackerState private var response = ""
    @TrackerState private var error: String?
    @TrackerState private var request = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(topic.name).font(.title2.bold())
            Text("Разбор \(ai.provider.title) · оценено заданий — \(topic.count)").foregroundStyle(.secondary)
            Divider()
            if let error {
                Text(error).foregroundStyle(.red)
                Button("Повторить") { self.error = nil; request += 1 }
            } else if response.isEmpty {
                ProgressView("Модель разбирает результаты…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView { Text(response).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Закрыть") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 600, height: 420)
        .task(id: request) {
            do {
                response = try await ai.client().explain(exam: exam, topic: topic)
            } catch where !Task.isCancelled {
                self.error = error.localizedDescription
            } catch {}
        }
    }
}
