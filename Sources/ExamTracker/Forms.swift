import ExamCore
import SwiftUI

struct ExamEditor: View {
    @Environment(\.dismiss) private var dismiss
    let exam: Exam?
    let ai: AIConfiguration
    let onSave: (Exam) throws -> Void
    @TrackerState private var name: String
    @TrackerState private var maximum: String
    @TrackerState private var target: String
    @TrackerState private var primaryMaximum: String
    @TrackerState private var topicsJob: Task<Void, Never>?
    @TrackerState private var suggested = false
    @TrackerState private var topics: String
    @TrackerState private var failure: String?

    init(exam: Exam?, ai: AIConfiguration, onSave: @escaping (Exam) throws -> Void) {
        self.exam = exam
        self.ai = ai
        self.onSave = onSave
        _name = TrackerState(initialValue: exam?.name ?? "")
        _maximum = TrackerState(initialValue: exam.map { String($0.maximum) } ?? "100")
        _target = TrackerState(initialValue: exam.map { String($0.target) } ?? "70")
        _primaryMaximum = TrackerState(initialValue: exam?.primaryMaximum.map { String($0) } ?? "")
        _topics = TrackerState(initialValue: exam?.topics.joined(separator: "\n") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(exam == nil ? "Новый экзамен" : "Настройки экзамена").font(.title2.bold())
            Form {
                if exam == nil {
                    Menu("Выбрать экзамен", systemImage: "books.vertical") {
                        Menu("ЕГЭ") {
                            ForEach(ExamPreset.ege) { preset in
                                Button(preset.name.replacingOccurrences(of: "ЕГЭ · ", with: "")) { apply(preset) }
                            }
                        }
                        ForEach(ExamPreset.international) { preset in
                            Button(preset.name) { apply(preset) }
                        }
                    }
                }
                TextField("Название", text: $name, prompt: Text("Например, ЕГЭ · Информатика"))
                TextField("Максимум итоговых баллов", text: $maximum)
                TextField("Максимум первичных баллов", text: $primaryMaximum, prompt: Text("Если есть отдельная шкала"))
                TextField("Целевой балл", text: $target)
                VStack(alignment: .leading) {
                    Text("Темы, по одной в строке")
                    TextEditor(text: $topics)
                        .font(.body)
                        .frame(minHeight: 115)
                        .border(.quaternary)
                    if ai.isConfigured {
                        Button("Подобрать темы с ИИ", systemImage: "sparkles") { suggestTopics() }
                            .disabled(name.cleaned.isEmpty)
                    }
                    if suggested {
                        Text("Проверьте предложенные темы перед сохранением.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(topicsJob != nil)
            if topicsJob != nil { ProgressView("Подбираем темы…") }
            SheetActions(error: failure, action: "Сохранить", cancel: { dismiss() }, save: save,
                         disabled: topicsJob != nil)
        }
        .padding(24)
        .frame(width: 530)
        .onDisappear { topicsJob?.cancel() }
        .onChange(of: name) {
            suggested = false
        }
    }

    private func apply(_ preset: ExamPreset) {
        name = preset.name
        maximum = String(preset.maximum)
        target = String(preset.target)
        primaryMaximum = ""
        topics = preset.topics.joined(separator: "\n")
        failure = nil
    }

    private func suggestTopics() {
        failure = nil
        let examName = name.cleaned
        topicsJob = Task {
            defer { topicsJob = nil }
            do {
                let proposals = try await ai.client().suggestTopics(for: examName)
                try Task.checkCancellation()
                if proposals.isEmpty {
                    failure = "Модель не определила предмет. Уточните название или добавьте темы вручную."
                    return
                }
                let combined = topics.components(separatedBy: .newlines) + proposals
                var seen: Set<String> = []
                topics = combined.map(\.cleaned).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
                    .joined(separator: "\n")
                suggested = true
            } catch where !Task.isCancelled {
                self.failure = error.localizedDescription
            } catch {}
        }
    }

    private func save() {
        guard !name.cleaned.isEmpty, let max = maximum.scoreValue, max > 0,
              let goal = target.scoreValue, (0...max).contains(goal) else {
            failure = "Введите название и целевой балл от нуля до максимума."
            return
        }
        let primaryMax = primaryMaximum.scoreValue
        guard primaryMaximum.cleaned.isEmpty || primaryMax.map({ $0 > 0 }) == true else {
            failure = "Введите положительный максимум первичных баллов или оставьте поле пустым."
            return
        }
        var updated = exam ?? Exam(name: name)
        updated.primaryMaximum = primaryMax
        updated.name = name.cleaned
        updated.maximum = max
        updated.target = goal
        var seen: Set<String> = []
        updated.topics = topics.components(separatedBy: .newlines).map(\.cleaned)
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        do {
            try onSave(updated)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct ScoreDraft: Identifiable {
    let id = UUID()
    var topic = ""
    var earned = ""
    var maximum = "1"
    var note = ""

    func score() throws -> TaskScore? {
        guard !earned.cleaned.isEmpty else { return nil }
        guard let earned = earned.scoreValue, let maximum = maximum.scoreValue else {
            throw ExamError.invalidScore
        }
        return TaskScore(topic: topic.cleaned, earned: earned, maximum: maximum, note: note.cleaned)
    }
}

struct ResultEditor: View {
    @Environment(\.dismiss) private var dismiss
    let exam: Exam
    let ai: AIConfiguration
    let onSave: (Attempt) throws -> Void
    @TrackerState private var title = "Пробник"
    @TrackerState private var date = Date.now
    @TrackerState private var earned = ""
    @TrackerState private var maximum: String
    @TrackerState private var primaryEarned = ""
    @TrackerState private var primaryMaximum: String
    @TrackerState private var showingImport = false
    @TrackerState private var imported = false
    @TrackerState private var scores: [ScoreDraft] = []
    @TrackerState private var failure: String?

    init(exam: Exam, ai: AIConfiguration, onSave: @escaping (Attempt) throws -> Void) {
        self.exam = exam
        self.ai = ai
        self.onSave = onSave
        _maximum = TrackerState(initialValue: String(exam.maximum))
        _primaryMaximum = TrackerState(initialValue: exam.primaryMaximum.map { String($0) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Записать результат").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Form {
                        TextField("Название", text: $title)
                        DatePicker("Дата", selection: $date, displayedComponents: .date)
                        TextField("Итоговый балл", text: $earned)
                        TextField("Максимум итоговых", text: $maximum)
                        TextField("Первичный балл", text: $primaryEarned, prompt: Text("Если есть"))
                        TextField("Максимум первичных", text: $primaryMaximum, prompt: Text("Если есть"))
                        if ai.isConfigured {
                            Button("Импортировать баллы с ИИ", systemImage: "doc.badge.plus") { showingImport = true }
                        }
                        if imported {
                            Text("Проверьте извлечённые баллы и максимумы перед сохранением.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    Text("Баллы по заданиям").font(.headline)
                    Text("Для статистики по темам. Пустой балл пропускается, ноль считается ошибкой.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach($scores) { $score in
                        Surface {
                            HStack {
                                TextField("Тема", text: $score.topic)
                                if !exam.topics.isEmpty {
                                    Menu("Темы") {
                                        ForEach(exam.topics, id: \.self) { topic in
                                            Button(topic) { score.topic = topic }
                                        }
                                    }
                                    .fixedSize()
                                }
                                Button(role: .destructive) {
                                    scores.removeAll { $0.id == score.id }
                                } label: { Image(systemName: "minus.circle") }
                                .help("Убрать строку")
                                .accessibilityLabel("Убрать строку")
                            }
                            HStack {
                                TextField("Баллы", text: $score.earned)
                                TextField("Максимум", text: $score.maximum)
                            }
                            TextField("Заметка об ошибке", text: $score.note)
                        }
                    }
                    Button { scores.append(ScoreDraft()) } label: { Label("Добавить задание", systemImage: "plus") }
                }
                .padding(2)
            }
            SheetActions(error: failure, action: "Сохранить", cancel: { dismiss() }, save: save)
        }
        .padding(24)
        .frame(width: 560, height: 560)
        .sheet(isPresented: $showingImport) {
            ScoreImportView(ai: ai) { result in
                if let value = result.primaryEarned { primaryEarned = String(value) }
                if let value = result.primaryMaximum { primaryMaximum = String(value) }
                if let value = result.finalEarned { earned = String(value) }
                if let value = result.finalMaximum { maximum = String(value) }
                imported = true
                failure = nil
            }
        }
    }

    private func save() {
        do {
            let details = try scores.compactMap { try $0.score() }
            let primary = try readScore(earned: primaryEarned, maximum: primaryMaximum)
            let final = try readScore(earned: earned, maximum: maximum)
            let attempt: Attempt
            if let final {
                attempt = try Attempt(title: title, date: date, earned: final.earned, maximum: final.maximum,
                                      scores: details, primaryScore: primary)
            } else if let primary {
                attempt = try Attempt(title: title, date: date, primaryScore: primary, scores: details)
            } else {
                throw ExamError.server("Введите итоговый или первичный балл пробника.")
            }
            try onSave(attempt)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
    private func readScore(earned: String, maximum: String) throws -> ExamScore? {
        guard !earned.cleaned.isEmpty else { return nil }
        guard let score = earned.scoreValue, let limit = maximum.scoreValue else { throw ExamError.invalidScore }
        return try ExamScore(earned: score, maximum: limit)
    }
}

struct SheetActions: View {
    let error: String?
    let action: String
    let cancel: () -> Void
    let save: () -> Void
    var disabled = false

    var body: some View {
        if let error {
            Text(error).foregroundStyle(.red)
        }
        HStack {
            Spacer()
            Button("Отмена", action: cancel).keyboardShortcut(.cancelAction)
            Button(action, action: save).keyboardShortcut(.defaultAction).disabled(disabled)
        }
    }
}
