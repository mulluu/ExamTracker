import ExamCore
import SwiftUI

struct PracticeSessionView: View {
    let set: PracticeSet
    let onRecord: (Attempt) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @TrackerState private var entries: [PracticeEntry]
    @TrackerState private var selection: Int?
    @TrackerState private var isFinished = false
    @TrackerState private var confirmClose = false
    @TrackerState private var confirmFinish = false
    @TrackerState private var error: String?

    init(set: PracticeSet, onRecord: @escaping (Attempt) throws -> Void) {
        self.set = set
        self.onRecord = onRecord
        _entries = TrackerState(initialValue: set.tasks.map { PracticeEntry(task: $0) })
        _selection = TrackerState(initialValue: set.tasks.isEmpty ? nil : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                sidebar
                    .frame(minWidth: 175, idealWidth: 204, maxWidth: 214)
                if let selection {
                    PracticeQuestionView(entry: $entries[selection], number: selection + 1, isFinished: isFinished)
                        .id(selection)
                        .frame(minWidth: 475, maxWidth: .infinity, maxHeight: .infinity)
                } else if isFinished {
                    summary
                        .frame(minWidth: 475, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("Нет заданий", systemImage: "list.bullet.clipboard")
                        .frame(minWidth: 475, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 740, idealWidth: 870, minHeight: 480, idealHeight: 620)
        .tint(Color(nsColor: .controlAccentColor))
        .interactiveDismissDisabled(entries.contains(where: \.hasWork))
        .confirmationDialog("Закрыть тренировку?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Закрыть без записи", role: .destructive) { dismiss() }
            Button("Продолжить тренировку", role: .cancel) {}
        } message: {
            Text("Введённые ответы и баллы будут удалены.")
        }
        .alert("Завершить тренировку?", isPresented: $confirmFinish) {
            Button("Завершить", action: finish)
            Button("Продолжить решение", role: .cancel) {}
        } message: {
            Text("Без ответа осталось \(entries.filter { !$0.hasAnswer }.count). После завершения откроется ключ.")
        }
    }

    private var header: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(set.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                let answered = entries.filter(\.hasAnswer).count
                Text("Заполнено \(answered) из \(entries.count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isFinished {
                Label("Тренировка завершена", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                PracticeTimerView()
                    .frame(minWidth: 300, alignment: .trailing)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var sidebar: some View {
        List(selection: Binding(
            get: { selection },
            set: { next in
                if next != nil || isFinished { selection = next }
            }
        )) {
            Section("Задания") {
                ForEach(entries.indices, id: \.self) { index in
                    let entry = entries[index]
                    HStack(spacing: 9) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .frame(minWidth: 19, alignment: .trailing)
                        Text(entry.task.kind.cleaned.isEmpty ? entry.task.topic : entry.task.kind)
                            .lineLimit(2)
                        Spacer(minLength: 3)
                        Image(systemName: entry.status.symbol)
                            .foregroundStyle(selection == index ? Color.primary : entry.status.color)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(entry.status.title)
                    .help(entry.status.title)
                    .tag(index)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Список заданий")
    }

    private var summary: some View {
        let scored = entries.filter { $0.earned != nil }
        let earned = scored.compactMap(\.earned).reduce(0, +)
        let maximum = scored.map(\.task.maximum).reduce(0, +)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Итог тренировки")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                if scored.isEmpty {
                    Text("Без оценки").font(.title2.weight(.medium))
                    Text(entries.contains(where: \.hasWork)
                         ? "Ответы и заметки сохранятся в истории. Баллы можно выставить в разборе."
                         : "В разборе можно посмотреть ключ и выставить баллы вручную.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(points(earned)) из \(points(maximum)) баллов")
                        .font(.title2.weight(.medium).monospacedDigit())
                    Text("Оценено заданий: \(scored.count) из \(entries.count).")
                        .foregroundStyle(.secondary)
                    if scored.count < entries.count {
                        Text("В итог входят задания с выставленными баллами.")
                            .foregroundStyle(.secondary)
                    }
                }
                if entries.contains(where: { !$0.hasValidScore }) {
                    Label("Исправьте баллы вне допустимого диапазона.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
                VStack(spacing: 0) {
                    ForEach(entries.indices, id: \.self) { index in
                        if index > 0 { Divider() }
                        let entry = entries[index]
                        Button {
                            selection = index
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(index + 1). \(entry.task.topic)")
                                    if !entry.response.cleaned.isEmpty {
                                        Text("Ваш ответ: \(entry.response.cleaned)")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    if !entry.task.answer.cleaned.isEmpty {
                                        Text("\(entry.answerLabel): \(entry.task.answer.cleaned)")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Label(entry.status.title, systemImage: entry.status.symbol)
                                    .foregroundStyle(entry.status.color)
                                if let earned = entry.earned {
                                    Text("\(points(earned))/\(points(entry.task.maximum))")
                                        .monospacedDigit()
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 650, alignment: .leading)
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var footer: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
            HStack(spacing: 10) {
                Button("Закрыть", role: .cancel) {
                    if entries.contains(where: \.hasWork) { confirmClose = true }
                    else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                if let selection {
                    Button("Назад", systemImage: "chevron.left") { self.selection = selection - 1 }
                        .disabled(selection == 0)
                    Button("Далее", systemImage: "chevron.right") { self.selection = selection + 1 }
                        .disabled(selection + 1 == entries.count)
                } else if !entries.isEmpty {
                    Button("К разбору", systemImage: "chevron.left") {
                        selection = entries.firstIndex { $0.status == .manual || $0.status == .invalid } ?? 0
                    }
                }
                Spacer()
                if !isFinished {
                    Button("Завершить и проверить") {
                        if entries.contains(where: { !$0.hasAnswer }) { confirmFinish = true }
                        else { finish() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(entries.isEmpty)
                } else if selection != nil {
                    Button("К итогу") { selection = nil }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Записать результат", action: record)
                        .buttonStyle(.borderedProminent)
                        .disabled(!entries.contains(where: \.hasWork) || !entries.allSatisfy(\.hasValidScore))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func finish() {
        guard !isFinished else { return }
        for index in entries.indices { entries[index].check() }
        isFinished = true
        selection = nil
    }

    private func record() {
        guard isFinished else { return }
        let scores = entries.compactMap(\.taskScore)
        guard !scores.isEmpty, entries.allSatisfy(\.hasValidScore) else { return }
        do {
            try onRecord(Attempt(title: set.title, scores: scores))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct PracticeQuestionView: View {
    @Binding var entry: PracticeEntry
    let number: Int
    let isFinished: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heading
                    Text(entry.task.prompt)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                    if let description = entry.task.diagramDescription, isFinished || entry.task.diagramInQuestion == true {
                        StudyDiagramView(description: description)
                    }
                    if isFinished || entry.task.showsIllustrationInQuestion {
                        TaskIllustrationView(task: entry.task)
                    }
                    if isFinished || entry.task.sourceInQuestion == true {
                        TaskSourceFragmentsView(task: entry.task, expanded: entry.task.kind.hasPrefix("Страница "))
                    } else if entry.task.kind.hasPrefix("Страница "), entry.task.sourceFragments?.isEmpty == false {
                        Text("Оригинал доступен в разборе. Если страница содержит только условие, её можно открыть для решения в редакторе набора.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if isFinished { reference }
                }
                .frame(maxWidth: 650, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 110, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))

            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if isFinished {
                    feedback
                    manualEditor
                } else {
                    answerEditor
                }
            }
            .frame(maxWidth: 650, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Задание \(number)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Максимум: \(points(entry.task.maximum))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(entry.task.topic)
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            if !entry.task.kind.cleaned.isEmpty, entry.task.kind != entry.task.topic {
                Text(entry.task.kind)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var answerEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ваш ответ").font(.headline)
            TextField("Ваш ответ", text: $entry.response, prompt: Text("Введите ответ"), axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var feedback: some View {
        HStack {
            Label(entry.status.title, systemImage: entry.status.symbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(entry.status.color)
            Spacer()
            if let earned = entry.earned {
                Text("\(points(earned)) из \(points(entry.task.maximum))")
                    .monospacedDigit()
            }
        }
        .padding(10)
        .background(entry.status.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var reference: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Разбор задания").font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Ваш ответ").font(.subheadline.weight(.medium))
            Text(entry.response.cleaned.isEmpty ? "Ответ не введён" : entry.response.cleaned)
                .textSelection(.enabled)
            if !entry.task.answer.cleaned.isEmpty {
                Text(entry.answerLabel).font(.subheadline.weight(.medium))
                Text(entry.task.answer).textSelection(.enabled)
            }
            if !entry.task.solution.cleaned.isEmpty {
                Text("Решение").font(.subheadline.weight(.medium))
                Text(entry.task.solution).textSelection(.enabled)
            }
        }
    }

    private var manualEditor: some View {
        DisclosureGroup("Балл вручную и заметка", isExpanded: $entry.showsManual) {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Ваш балл") {
                    TextField("Ваш балл", text: $entry.manualScore,
                              prompt: Text("0–\(points(entry.task.maximum))"))
                        .labelsHidden()
                        .frame(width: 94)
                }
                if !entry.hasValidScore {
                    Text("Введите балл от 0 до \(points(entry.task.maximum)).")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                TextField("Заметка об ошибке", text: $entry.note, prompt: Text("Заметка об ошибке"), axis: .vertical)
                    .lineLimit(1...5)
            }
            .padding(.top, 7)
        }
    }
}

private struct PracticeEntry {
    let task: PracticeTask
    var response = ""
    var manualScore = ""
    var note = ""
    var grade: PracticeGrade?
    var showsManual = false

    var answerLabel: String {
        switch task.answerOrigin {
        case .localSolution: "Ответ, вычисленный локально"
        case .acceptedSuggestion: "Подтверждённый ответ ИИ"
        case nil: "Ответ в ключе"
        }
    }

    var hasAnswer: Bool { !response.cleaned.isEmpty || earned != nil }
    var hasWork: Bool { !response.cleaned.isEmpty || !manualScore.cleaned.isEmpty || !note.cleaned.isEmpty }

    var hasValidScore: Bool {
        guard !manualScore.cleaned.isEmpty else { return true }
        guard let value = manualScore.scoreValue else { return false }
        return (0...task.maximum).contains(value)
    }

    var earned: Double? {
        guard hasValidScore else { return nil }
        if let manual = manualScore.scoreValue { return manual }
        switch grade {
        case .correct: return task.maximum
        case .incorrect: return 0
        case .manual, .unanswered, nil: return nil
        }
    }

    var taskScore: TaskScore? {
        guard hasWork else { return nil }
        return TaskScore(topic: task.topic, earned: earned, maximum: task.maximum, note: note.cleaned,
                         question: task.prompt, response: response.cleaned.isEmpty ? nil : response.cleaned,
                         expectedAnswer: task.answer.cleaned.isEmpty ? nil : task.answer)
    }

    var status: PracticeStatus {
        if !hasValidScore { return .invalid }
        if manualScore.scoreValue != nil { return .scored }
        switch grade {
        case .correct: return .correct
        case .incorrect: return .incorrect
        case .manual: return .manual
        case .unanswered, nil: return response.cleaned.isEmpty ? .unanswered : .answered
        }
    }

    mutating func check() {
        let result = task.grade(response: response)
        grade = result == .unanswered ? nil : result
        if result == .manual { showsManual = true }
    }
}

private enum PracticeStatus {
    case unanswered, answered, correct, incorrect, manual, scored, invalid

    var title: String {
        switch self {
        case .unanswered: "Без ответа"
        case .answered: "Ответ введён"
        case .correct: "Верно"
        case .incorrect: "Не совпало с ключом"
        case .manual: "Нужна ручная проверка"
        case .scored: "Оценено вручную"
        case .invalid: "Проверьте балл"
        }
    }

    var symbol: String {
        switch self {
        case .unanswered: "circle"
        case .answered: "circle.inset.filled"
        case .correct: "checkmark.circle.fill"
        case .incorrect: "xmark.circle.fill"
        case .manual: "pencil.circle"
        case .scored: "checkmark.circle"
        case .invalid: "exclamationmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .unanswered, .manual, .scored: .secondary
        case .answered: Color(nsColor: .controlAccentColor)
        case .correct: .green
        case .incorrect, .invalid: .red
        }
    }
}
