import ExamCore
import SwiftUI

struct LessonsView: View {
    let exam: Exam
    let ai: AIConfiguration
    let showSettings: () -> Void
    let onSave: (ExamLesson) throws -> Void

    @TrackerState private var topic = ""
    @TrackerState private var kind = ""
    @TrackerState private var taskContext = ""
    @TrackerState private var wantsIllustration = false
    @TrackerState private var drawing = false
    @TrackerState private var illustrationError: String?
    @TrackerState private var topicFilter = ""
    @TrackerState private var kindFilter = ""
    @TrackerState private var sort = LessonSort.newest
    @TrackerState private var expandedID: UUID?
    @TrackerState private var job: Task<Void, Never>?
    @TrackerState private var error: String?
    @TrackerState private var unsaved: ExamLesson?

    private var lessons: [ExamLesson] { exam.lessons ?? [] }

    private var filteredLessons: [ExamLesson] {
        lessons.filter { lesson in
            (topicFilter.isEmpty || lesson.topic.lowercased() == topicFilter) &&
            (kindFilter.isEmpty || lesson.kind.lowercased() == kindFilter)
        }.sorted(by: sort.precedes)
    }

    private var lessonRequest: ExamLessonRequest {
        ExamLessonRequest(exam: exam.name, topic: topic, kind: kind, taskContext: taskContext,
                          wantsIllustration: wantsIllustration && ai.canGenerateImages)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            composer
            history
        }
        .onDisappear { job?.cancel() }
    }

    private var composer: some View {
        let prompt = try? lessonRequest.prompt()
        return Surface {
            Label("Урок с ИИ", systemImage: "sparkles").font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Тема").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("Тема", text: $topic, prompt: Text("Например, производные"))
                        if !exam.topics.isEmpty {
                            Menu("Темы экзамена") {
                                ForEach(exam.topics, id: \.self) { name in
                                    Button(name) { topic = name }
                                }
                            }
                            .fixedSize()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Номер или тип задания").font(.caption).foregroundStyle(.secondary)
                    TextField("Номер или тип задания", text: $kind, prompt: Text("Например, №12 или уравнения"))
                }
                DisclosureGroup("Условие или контекст задания") {
                    TextField("Контекст задания", text: $taskContext,
                              prompt: Text("Можно вставить условие или уточнить, что вызывает трудности"), axis: .vertical)
                        .lineLimit(2...5)
                        .padding(.top, 6)
                }
                if ai.provider == .openAI {
                    Toggle("Сгенерировать иллюстрацию", isOn: $wantsIllustration)
                        .toggleStyle(.checkbox)
                        .disabled(!ai.canGenerateImages)
                    if wantsIllustration {
                        Text("Иллюстрация использует отдельный запрос к GPT Image и квоту API.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(job != nil || unsaved != nil)

            if let prompt {
                DisclosureGroup("Промпт урока") {
                    ScrollView {
                        Text(prompt)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 210)
                    .padding(.top, 6)
                }
            }

            if ai.isConfigured {
                HStack {
                    Button("Составить урок", systemImage: "sparkles", action: generate)
                        .buttonStyle(.borderedProminent)
                        .disabled(job != nil || unsaved != nil || prompt == nil)
                        .help(ai.provider.cloud.map { "Тема, номер и контекст отправятся в \($0.name)." } ?? "Урок составит модель Ollama.")
                    if job != nil {
                        ProgressView(drawing ? "Создаём иллюстрацию…" : "Составляем урок…").controlSize(.small)
                    }
                }
            } else {
                Button("Настроить ИИ", systemImage: "gearshape", action: showSettings)
            }

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            if let illustrationError {
                Label(illustrationError, systemImage: "photo.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let unsaved {
                LessonContentView(lesson: unsaved)
                HStack {
                    Button("Повторить сохранение") { save(unsaved) }
                    Button("Закрыть урок", role: .destructive) {
                        self.unsaved = nil
                        error = nil
                    }
                }
            }
        }
    }

    private var history: some View {
        Surface {
            Label("Сохранённые уроки", systemImage: "books.vertical").font(.headline)
            if lessons.isEmpty {
                Text("Здесь появятся уроки, которые можно читать без интернета.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    filter("Тема", all: "Все темы", options: filterOptions(\.topic), selection: $topicFilter)
                    filter("Номер или тип", all: "Все задания", options: filterOptions(\.kind), selection: $kindFilter)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Сортировка").font(.caption).foregroundStyle(.secondary)
                        Picker("Сортировка", selection: $sort) {
                            ForEach(LessonSort.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .labelsHidden()
                    }
                }

                let visible = filteredLessons
                if visible.isEmpty {
                    Text("По этим фильтрам уроков нет.").foregroundStyle(.secondary)
                    Button("Сбросить фильтры") {
                        topicFilter = ""
                        kindFilter = ""
                    }
                }
                ForEach(visible) { lesson in
                    Divider()
                    lessonRow(lesson)
                }
            }
        }
    }

    private func filter(_ title: String, all: String, options: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text(all).tag("")
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option.lowercased())
                }
            }
            .labelsHidden()
        }
    }

    private func filterOptions(_ keyPath: KeyPath<ExamLesson, String>) -> [String] {
        var known: Set<String> = []
        return lessons.map { $0[keyPath: keyPath] }
            .filter { !$0.isEmpty && known.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func lessonRow(_ lesson: ExamLesson) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedID == lesson.id },
            set: { expandedID = $0 ? lesson.id : nil }
        )) {
            LessonContentView(lesson: lesson)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.title).font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    if !lesson.topic.isEmpty && !lesson.kind.isEmpty {
                        Text(lesson.kind)
                        Text("·")
                    }
                    Text(lesson.date.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func generate() {
        guard job == nil, unsaved == nil, ai.isConfigured else { return }
        error = nil
        illustrationError = nil
        let request = lessonRequest
        wantsIllustration = false
        job = Task {
            defer {
                job = nil
                drawing = false
            }
            do {
                var lesson = try await ai.client().lesson(request)
                try Task.checkCancellation()
                guard save(lesson), request.wantsIllustration else { return }
                do {
                    drawing = true
                    let generator = OpenAIImages(apiKey: try CloudAIService.openAI.loadKey())
                    let data = try await generator.generate(prompt: request.illustrationPrompt(lesson: lesson))
                    try Task.checkCancellation()
                    guard NSImage(data: data) != nil else {
                        throw ExamError.server("Не удалось открыть изображение.")
                    }
                    lesson.illustration = data
                    save(lesson)
                } catch where !Task.isCancelled {
                    illustrationError = "Урок готов. Иллюстрация недоступна. \(error.localizedDescription)"
                }
            } catch where !Task.isCancelled {
                self.error = error.localizedDescription
            } catch {}
        }
    }

    @discardableResult
    private func save(_ lesson: ExamLesson) -> Bool {
        do {
            try onSave(lesson)
            unsaved = nil
            error = nil
            if topicFilter != lesson.topic.lowercased() { topicFilter = "" }
            if kindFilter != lesson.kind.lowercased() { kindFilter = "" }
            expandedID = lesson.id
            return true
        } catch {
            unsaved = lesson
            self.error = "Не удалось сохранить урок. \(error.localizedDescription)"
            return false
        }
    }
}

private enum LessonSort: String, CaseIterable {
    case newest = "Сначала новые"
    case oldest = "Сначала старые"
    case topic = "По теме"
    case kind = "По номеру или типу"

    func precedes(_ first: ExamLesson, _ second: ExamLesson) -> Bool {
        switch self {
        case .newest: first.date > second.date
        case .oldest: first.date < second.date
        case .topic: compare(first.topic, second.topic, first, second)
        case .kind: compare(first.kind, second.kind, first, second)
        }
    }

    private func compare(_ firstValue: String, _ secondValue: String, _ first: ExamLesson, _ second: ExamLesson) -> Bool {
        if firstValue.isEmpty != secondValue.isEmpty { return !firstValue.isEmpty }
        let comparison = firstValue.localizedStandardCompare(secondValue)
        return comparison == .orderedSame ? first.date > second.date : comparison == .orderedAscending
    }
}
