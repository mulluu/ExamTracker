import ExamCore
import SwiftUI

struct PracticeView: View {
    let exam: Exam
    let ai: AIConfiguration
    let onSaveSet: (PracticeSet) throws -> Void
    let onSolve: (PracticeSet) -> Void

    @TrackerState private var sheet: Sheet?

    private enum Sheet: Identifiable {
        case edit(PracticeSet, imported: Bool = false)
        case importFile(URL?)
        case official
        case generate
        case diagrams

        var id: String {
            switch self {
            case .edit(let set, _): "edit-\(set.id)"
            case .importFile(let url): "import-\(url?.absoluteString ?? "local")"
            case .official: "official"
            case .generate: "generate"
            case .diagrams: "diagrams"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Тренировочные наборы").font(.title2.weight(.semibold))
                Spacer()
                Button("Графики и фигуры", systemImage: "chart.xyaxis.line") { sheet = .diagrams }
            }
            HStack {
                Button("Официальные варианты", systemImage: "building.columns") { sheet = .official }
                    .buttonStyle(.borderedProminent)
                Button("Импорт файла", systemImage: "square.and.arrow.down") { sheet = .importFile(nil) }
                Button("Новый набор", systemImage: "plus") {
                    sheet = .edit(PracticeSet(title: "", tasks: [PracticeTask()]))
                }
                if ai.provider != .offline {
                    Button("Создать с ИИ", systemImage: "sparkles") { sheet = .generate }
                }
            }

            if exam.practice.isEmpty {
                ContentUnavailableView(
                    "Пока нет наборов",
                    systemImage: "list.clipboard",
                    description: Text("Загрузите официальный вариант или добавьте свои задания.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            }

            ForEach(exam.practice) { set in
                HStack(spacing: 14) {
                    Image(systemName: "list.clipboard")
                        .font(.title3)
                        .foregroundStyle(.mint)
                        .frame(width: 36, height: 36)
                        .background(.mint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(set.title)
                            .font(.headline)
                        let topics = Array(Set(set.tasks.map(\.topic))).sorted().joined(separator: ", ")
                        Label("\(set.tasks.count) · \(topics)", systemImage: "list.bullet")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 12)
                    if let source = set.sourceURL {
                        Link(destination: source) { Image(systemName: "link") }
                            .help("Открыть официальный источник")
                            .accessibilityLabel("Официальный источник")
                    }
                    Button("Изменить") { sheet = .edit(set) }
                    Button("Решать", systemImage: "arrow.right") { onSolve(set) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(16)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .tint(.mint)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit(let set, let imported):
                PracticeEditor(set: set, exam: exam, ai: ai, imported: imported, onSave: onSaveSet)
            case .importFile(let url):
                TaskImportView(exam: exam, initialURL: url) { set in self.sheet = .edit(set, imported: true) }
            case .official:
                VStack(alignment: .trailing, spacing: 14) {
                    OfficialSourcesView(exam: exam, onImport: { self.sheet = .importFile(nil) },
                                        onDownload: { self.sheet = .importFile($0) })
                    Button("Закрыть") { self.sheet = nil }.keyboardShortcut(.cancelAction)
                }
                .padding(20)
                .frame(width: 620)
            case .generate:
                PracticeGenerator(exam: exam, ai: ai, onSave: onSaveSet)
            case .diagrams:
                StudyDiagramWorkspace { task in
                    self.sheet = .edit(PracticeSet(title: "Графики и фигуры", tasks: [task]))
                }
            }
        }
    }
}

private struct PracticeEditor: View {
    let exam: Exam
    let ai: AIConfiguration
    let onSave: (PracticeSet) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @TrackerState private var draft: PracticeSet
    @TrackerState private var error: String?
    private let generated: Bool
    private let imported: Bool
    @TrackerState private var topicJob: Task<Void, Never>?
    @TrackerState private var solutionJob: Task<Void, Never>?
    @TrackerState private var suggestions: [UUID: PracticeSolutionSuggestion] = [:]
    @TrackerState private var attemptedSolutions: Set<UUID> = []
    @TrackerState private var solutionMessage: String?

    private var topics: [String] { exam.topics }
    private var isWorking: Bool { topicJob != nil || solutionJob != nil }
    private var solutionCandidates: [PracticeTask] {
        draft.tasks.filter { $0.canSuggestSolutionFromText && !attemptedSolutions.contains($0.id) }
    }

    init(set: PracticeSet, exam: Exam, ai: AIConfiguration, generated: Bool = false, imported: Bool = false,
         onSave: @escaping (PracticeSet) throws -> Void) {
        _draft = TrackerState(initialValue: set)
        self.exam = exam
        self.ai = ai
        self.generated = generated
        self.imported = imported
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Набор") {
                    TextField("Название", text: $draft.title, prompt: Text("Например, пробник по стереометрии"))
                    if generated || imported {
                        Text("Проверьте условия, ответы и темы перед сохранением.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if ai.isConfigured {
                        Button("Определить темы с ИИ", systemImage: "sparkles") { classify() }
                            .disabled(draft.tasks.allSatisfy { $0.prompt.cleaned.isEmpty })
                            .help(ai.provider.cloud.map { "Условия будут отправлены в \($0.name)" } ?? "Локальная классификация через Ollama")
                    }
                    if draft.tasks.contains(where: { $0.answer.cleaned.isEmpty && $0.solution.cleaned.isEmpty }) {
                        Button("Вычислить ответы локально", systemImage: "function", action: solveLocally)
                    }
                    if ai.isConfigured && !solutionCandidates.isEmpty {
                        Button("Решить задания без ключа с ИИ", systemImage: "sparkles", action: suggestSolutions)
                            .help(ai.provider.cloud.map { "До восьми условий отправятся в \($0.name)." }
                                  ?? "До восьми условий обработает модель Ollama.")
                    }
                    if topicJob != nil { ProgressView("Определяем темы…") }
                    if solutionJob != nil { ProgressView("Ищем ответы…") }
                    if let solutionMessage {
                        Text(solutionMessage).font(.callout).foregroundStyle(.secondary)
                    }
                }

                ForEach($draft.tasks) { binding in
                    let task = binding.wrappedValue
                    Section(task.kind.cleaned.isEmpty ? "Задание" : "Задание \(task.kind)") {
                        HStack {
                            TextField("Тема", text: binding.topic, prompt: Text("Например, объём конуса"))
                            if !topics.isEmpty {
                                Menu("Темы экзамена") {
                                    ForEach(topics, id: \.self) { topic in
                                        Button(topic) { binding.wrappedValue.topic = topic }
                                    }
                                }
                                .fixedSize()
                            }
                        }
                        TextField("Тип", text: binding.kind, prompt: Text("Например, №3 · необязательно"))
                        TextField("Условие", text: binding.prompt, axis: .vertical)
                            .lineLimit(2...7)
                            .onChange(of: task.prompt) {
                                if binding.wrappedValue.diagramIsAutomatic == true {
                                    binding.wrappedValue.diagramDescription = nil
                                    binding.wrappedValue.diagramInQuestion = nil
                                    binding.wrappedValue.diagramIsAutomatic = nil
                                }
                                suggestions.removeValue(forKey: task.id)
                                attemptedSolutions.remove(task.id)
                                if binding.wrappedValue.answerOrigin != nil {
                                    binding.wrappedValue.answer = ""
                                    binding.wrappedValue.solution = ""
                                    binding.wrappedValue.answerOrigin = nil
                                }
                            }
                        TextField("Ответ", text: Binding(
                            get: { binding.wrappedValue.answer },
                            set: { value in
                                binding.wrappedValue.answer = value
                                binding.wrappedValue.answerOrigin = nil
                                suggestions.removeValue(forKey: task.id)
                            }
                        ), prompt: Text("Если известен"), axis: .vertical)
                        .lineLimit(1...5)
                        if let origin = task.answerOrigin {
                            Label(origin == .localSolution ? "Ответ вычислен локально" : "Принятый ответ ИИ",
                                  systemImage: origin == .localSolution ? "function" : "sparkles")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let suggestion = suggestions[task.id], task.answer.cleaned.isEmpty {
                            suggestionRow(suggestion, task: binding)
                        }
                        TextField("Решение", text: binding.solution, prompt: Text("Необязательно"), axis: .vertical)
                            .lineLimit(1...7)
                        TaskSourceFragmentsView(task: task, expanded: imported)
                        if task.sourceFragments?.isEmpty == false {
                            Toggle("Показывать оригинал в условии", isOn: Binding(
                                get: { binding.wrappedValue.showsSourceInQuestion },
                                set: { binding.wrappedValue.sourceInQuestion = $0 }
                            ))
                            .help("Включите, если на фрагменте только условие и иллюстрации к нему.")
                        }
                        TaskIllustrationEditor(task: binding, ai: ai)
                        StudyDiagramEditor(description: binding.diagramDescription, inQuestion: binding.diagramInQuestion,
                                           isAutomatic: binding.diagramIsAutomatic, condition: task.prompt,
                                           fragments: task.sourceFragments ?? [], illustration: task.illustration)
                        TextField("Максимум баллов", value: binding.maximum, format: .number)
                        if draft.tasks.count > 1 {
                            Button("Удалить задание", role: .destructive) {
                                draft.tasks.removeAll { $0.id == task.id }
                            }
                        }
                    }
                }
                Button("Добавить задание", systemImage: "plus") { draft.tasks.append(PracticeTask()) }
            }
            .formStyle(.grouped)
            .disabled(isWorking)

            PracticeSheetFooter(error: error, actionTitle: "Сохранить набор",
                                disabled: isWorking || draft.title.cleaned.isEmpty || draft.tasks.isEmpty || !draft.tasks.allSatisfy(\.isValid)) {
                var set = draft
                set.title = set.title.cleaned
                for index in set.tasks.indices where set.tasks[index].diagramDescription == nil {
                    set.tasks[index].updateDiagramFromCondition()
                }
                do {
                    try onSave(set)
                    dismiss()
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
        .frame(width: 640, height: 620)
        .onDisappear {
            topicJob?.cancel()
            solutionJob?.cancel()
        }
    }

    private func suggestionRow(_ suggestion: PracticeSolutionSuggestion, task: Binding<PracticeTask>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ответ, предложенный ИИ", systemImage: "sparkles").font(.subheadline.weight(.medium))
            Text(suggestion.answer).textSelection(.enabled)
            Text(suggestion.explanation).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button("Принять ответ") {
                    let id = task.wrappedValue.id
                    task.wrappedValue.answer = suggestion.answer
                    if task.wrappedValue.solution.cleaned.isEmpty {
                        task.wrappedValue.solution = suggestion.explanation
                    }
                    task.wrappedValue.answerOrigin = .acceptedSuggestion
                    suggestions.removeValue(forKey: id)
                }
                Button("Отклонить") { suggestions.removeValue(forKey: task.wrappedValue.id) }
            }
        }
    }

    private func solveLocally() {
        var count = 0
        for index in draft.tasks.indices {
            if draft.tasks[index].fillMissingAnswerLocally() {
                suggestions.removeValue(forKey: draft.tasks[index].id)
                count += 1
            }
        }
        solutionMessage = count == 0 ? "Подходящих для локального решения заданий нет."
            : "Локально вычислено ответов: \(count)."
    }

    private func suggestSolutions() {
        guard !isWorking else { return }
        let batch = Array(solutionCandidates.prefix(8))
        guard !batch.isEmpty else { return }
        error = nil
        solutionMessage = nil
        solutionJob = Task {
            defer { solutionJob = nil }
            do {
                let found = try await ai.client().suggestSolutions(for: batch, exam: exam.name)
                try Task.checkCancellation()
                attemptedSolutions.formUnion(batch.map(\.id))
                suggestions.merge(found) { _, new in new }
                solutionMessage = found.isEmpty
                    ? "Модель не смогла однозначно решить выбранные задания."
                    : "Предложено ответов: \(found.count) из \(batch.count). Проверьте их перед сохранением."
            } catch where !Task.isCancelled {
                self.error = error.localizedDescription
            } catch {}
        }
    }

    private func classify() {
        guard !isWorking else { return }
        error = nil
        let candidates = draft.tasks.filter { !$0.prompt.cleaned.isEmpty }
        topicJob = Task {
            defer { topicJob = nil }
            do {
                let topics = try await ai.client().classify(candidates, for: exam)
                try Task.checkCancellation()
                for index in draft.tasks.indices {
                    if let topic = topics[draft.tasks[index].id] {
                        draft.tasks[index].topic = topic
                    }
                }
            } catch where !Task.isCancelled {
                self.error = error.localizedDescription
            } catch {}
        }
    }
}

private struct PracticeGenerator: View {
    let exam: Exam
    let ai: AIConfiguration
    let onSave: (PracticeSet) throws -> Void

    @TrackerState private var topics = ""
    @TrackerState private var kind = ""
    @TrackerState private var sample = ""
    @TrackerState private var count = 3
    @TrackerState private var preferDiagrams = false
    @TrackerState private var generated: PracticeSet?
    @TrackerState private var job: Task<Void, Never>?
    @TrackerState private var error: String?

    var body: some View {
        if let generated {
            PracticeEditor(set: generated, exam: exam, ai: ai, generated: true, onSave: onSave)
        } else {
            VStack(spacing: 0) {
                Form {
                    Section("Генерация заданий") {
                        if !ai.isConfigured {
                            Text("Настройте выбранного провайдера в разделе «Настройки ИИ».")
                                .foregroundStyle(.secondary)
                        } else {
                            LabeledContent("Модель", value: ai.model)
                        }
                        TextField("Тема или несколько тем", text: $topics, prompt: Text("Например, уравнения и неравенства"))
                        if !exam.topics.isEmpty {
                            Menu("Добавить тему экзамена") {
                                ForEach(exam.topics, id: \.self) { topic in
                                    Button(topic) {
                                        topics = topics.cleaned.isEmpty ? topic : "\(topics.cleaned), \(topic)"
                                    }
                                }
                            }
                        }
                        TextField("Тип задания", text: $kind, prompt: Text("Укажите один тип, чтобы получить его варианты"))
                        TextField("Условие образца", text: $sample, prompt: Text("Необязательно"), axis: .vertical)
                            .lineLimit(2...7)
                        Toggle("Задания с графиками и фигурами", isOn: $preferDiagrams)
                        Stepper("Количество заданий — \(count)", value: $count, in: 1...12)
                        if job != nil {
                            ProgressView("Модель составляет задания…")
                        }
                    }
                }
                .formStyle(.grouped)
                .disabled(job != nil)

                PracticeSheetFooter(error: error, actionTitle: "Сгенерировать",
                                    disabled: !ai.isConfigured || job != nil || !hasPrompt,
                                    action: generate)
            }
            .frame(width: 640, height: 460)
            .onDisappear { job?.cancel() }
        }
    }

    private var hasPrompt: Bool {
        preferDiagrams || [topics, kind, sample].contains { !$0.cleaned.isEmpty }
    }

    private func generate() {
        error = nil
        job = Task {
            defer { job = nil }
            do {
                let tasks = try await ai.client().generate(
                    exam: exam.name, topics: topics.cleaned, kind: kind.cleaned, count: count,
                    sample: sample.cleaned, preferDiagrams: preferDiagrams
                )
                try Task.checkCancellation()
                let label = kind.cleaned.isEmpty ? topics.cleaned : kind.cleaned
                generated = PracticeSet(title: label.isEmpty ? "Новый набор" : label, tasks: tasks)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
}

private struct PracticeSheetFooter: View {
    let error: String?
    let actionTitle: String
    let disabled: Bool
    let action: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Divider()
        HStack(spacing: 12) {
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Spacer()
            Button("Отмена", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .disabled(disabled)
        }
        .padding(16)
    }
}
