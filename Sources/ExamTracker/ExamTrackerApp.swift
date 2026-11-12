import AppKit
import ExamCore
import SwiftUI

// Use the property wrapper on SDKs that also ship a State macro.
typealias TrackerState<Value> = SwiftUI.State<Value>

@main
struct ExamTrackerApp: App {
    @TrackerState private var store = TrackerStore()

    var body: some Scene {
        Window("Экзамены", id: "tracker") {
            TrackerView(store: store)
                .tint(.mint)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}

@MainActor @Observable
final class TrackerStore {
    private let storage = ExamStorage(url: URL.applicationSupportDirectory
        .appending(path: "ExamTracker/exams.json"))
    private(set) var exams: [Exam] = []
    private(set) var startupError: String?

    init() { reload() }

    func reload() {
        do {
            exams = try storage.load()
            startupError = nil
        } catch {
            startupError = "Не удалось прочитать данные. \(error.localizedDescription)"
        }
    }

    func save(_ exam: Exam) throws {
        var updated = exams
        if let index = updated.firstIndex(where: { $0.id == exam.id }) {
            updated[index] = exam
        } else {
            updated.append(exam)
        }
        try commit(updated)
    }

    func update(_ id: UUID, change: (inout Exam) -> Void) throws {
        guard var exam = exams.first(where: { $0.id == id }) else {
            throw ExamError.server("Экзамен недоступен.")
        }
        change(&exam)
        try save(exam)
    }

    private func commit(_ exams: [Exam]) throws {
        if let startupError { throw ExamError.server(startupError) }
        try storage.save(exams)
        self.exams = exams
    }
}

private enum TrackerTab: String, CaseIterable {
    case progress = "Прогресс"
    case practice = "Тренировки"
    case history = "История"
    case lessons = "Уроки"

    var icon: String {
        switch self {
        case .progress: "chart.xyaxis.line"
        case .practice: "square.stack"
        case .history: "clock.arrow.circlepath"
        case .lessons: "text.book.closed"
        }
    }
}

private enum TrackerSheet: String, Identifiable {
    case newExam, editExam, record, settings
    var id: Self { self }
}

struct TrackerView: View {
    let store: TrackerStore
    @AppStorage("ollamaModel") private var ollamaModel = ""
    @AppStorage("openAIModel") private var openAIModel = CloudAIService.openAI.defaultModel
    @AppStorage("anthropicModel") private var anthropicModel = CloudAIService.anthropic.defaultModel
    @AppStorage("anthropicWorkspaceID") private var anthropicWorkspaceID = ""
    @AppStorage("aiProvider") private var provider = AIProvider.offline
    @TrackerState private var hasOpenAIKey = CloudAIService.openAI.hasKey
    @TrackerState private var hasAnthropicKey = CloudAIService.anthropic.hasKey

    private var ai: AIConfiguration {
        switch provider {
        case .offline: AIConfiguration(provider: provider, model: "", hasCloudKey: false)
        case .ollama: AIConfiguration(provider: provider, model: ollamaModel, hasCloudKey: false)
        case .openAI: AIConfiguration(provider: provider, model: openAIModel, hasCloudKey: hasOpenAIKey)
        case .anthropic:
            AIConfiguration(provider: provider, model: anthropicModel, hasCloudKey: hasAnthropicKey,
                            workspaceID: anthropicWorkspaceID)
        }
    }
    @TrackerState private var selectedID: UUID?
    @TrackerState private var tab = TrackerTab.progress
    @TrackerState private var sheet: TrackerSheet?
    @TrackerState private var pendingRemoval: Attempt?
    @TrackerState private var failure: String?
    @TrackerState private var activePractice: (examID: UUID, set: PracticeSet)?

    private var selectedExam: Exam? {
        store.exams.first { $0.id == selectedID } ?? store.exams.first
    }

    var body: some View {
        if let activePractice {
            PracticeSessionView(set: activePractice.set, onRecord: { attempt in
                try record(attempt, for: activePractice.examID)
            }, onClose: {
                self.activePractice = nil
            })
            .frame(minWidth: 560, minHeight: 430)
        } else {
            examBrowser
                .frame(minWidth: 880, minHeight: 610)
        }
    }

    private var examBrowser: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 300)
        } detail: {
            if let error = store.startupError {
                ContentUnavailableView {
                    Label("Данные недоступны", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Повторить") { store.reload() }
                }
            } else if let exam = selectedExam {
                detail(exam)
            } else {
                ContentUnavailableView {
                    Label("Добавьте экзамен", systemImage: "books.vertical")
                } description: {
                    Text("Укажите название, цель и шкалу баллов.")
                } actions: {
                    Button("Новый экзамен") { sheet = .newExam }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $sheet) { item in
            switch item {
            case .newExam:
                ExamEditor(exam: nil, ai: ai) { exam in
                    try store.save(exam)
                    selectedID = exam.id
                    tab = .progress
                }
            case .editExam:
                if let exam = selectedExam {
                    ExamEditor(exam: exam, ai: ai, onSave: store.save)
                }
            case .record:
                if let exam = selectedExam {
                    ResultEditor(exam: exam, ai: ai) { attempt in
                        try record(attempt, for: exam.id)
                    }
                }
            case .settings:
                AISettings(provider: $provider, ollamaModel: $ollamaModel, openAIModel: $openAIModel,
                           anthropicModel: $anthropicModel, hasOpenAIKey: $hasOpenAIKey,
                           hasAnthropicKey: $hasAnthropicKey, anthropicWorkspaceID: $anthropicWorkspaceID)
            }
        }
        .alert("Удалить результат?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), presenting: pendingRemoval) { attempt in
            Button("Удалить", role: .destructive) {
                guard let id = selectedExam?.id else { return }
                do {
                    try store.update(id) { $0.attempts.removeAll { $0.id == attempt.id } }
                } catch {
                    failure = error.localizedDescription
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: { attempt in
            Text(attempt.title)
        }
        .alert("Не удалось сохранить", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button("ОК", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "graduationcap.fill")
                    .font(.title2)
                    .foregroundStyle(.mint)
                Text("Экзамены").font(.title2.bold())
                Spacer()
                Button { sheet = .newExam } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Новый экзамен")
                    .accessibilityLabel("Новый экзамен")
                    .disabled(store.startupError != nil)
            }
            .padding(16)
            List(selection: Binding<UUID?>(
                get: { selectedExam?.id },
                set: { id in if let id { selectedID = id; tab = .progress } }
            )) {
                ForEach(store.exams) { exam in
                    Label(exam.name, systemImage: "book.closed")
                        .tag(exam.id)
                }
            }
            .listStyle(.sidebar)
            Divider()
            Button { sheet = .settings } label: {
                Label("Настройки ИИ", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }

    private func detail(_ exam: Exam) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center) { heading(exam); Spacer(minLength: 20); recordButton }
                    VStack(alignment: .leading, spacing: 12) { heading(exam); recordButton }
                }
                HStack(spacing: 8) {
                    ForEach(TrackerTab.allCases, id: \.self) { page in
                        Button {
                            tab = page
                        } label: {
                            Label(page.rawValue, systemImage: page.icon)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(tab == page ? Color.mint.opacity(0.19) : .clear, in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tab == page ? .isSelected : [])
                    }
                }
                switch tab {
                case .progress:
                    Dashboard(exam: exam, ai: ai) { sheet = .settings }
                case .practice:
                    PracticeView(exam: exam, ai: ai, onSaveSet: { set in
                        try store.update(exam.id) { updated in
                            if let index = updated.practice.firstIndex(where: { $0.id == set.id }) {
                                updated.practice[index] = set
                            } else {
                                updated.practice.append(set)
                            }
                            var known = Set(updated.topics.map { $0.cleaned.lowercased() })
                            for task in set.tasks {
                                let topic = task.topic.cleaned
                                if topic != "Без темы", known.insert(topic.lowercased()).inserted {
                                    updated.topics.append(topic)
                                }
                            }
                        }
                    }, onSolve: { set in activePractice = (exam.id, set) })
                case .lessons:
                    LessonsView(exam: exam, ai: ai, showSettings: { sheet = .settings }) { lesson in
                        try store.update(exam.id) { updated in
                            if updated.lessons == nil { updated.lessons = [] }
                            if let index = updated.lessons?.firstIndex(where: { $0.id == lesson.id }) {
                                updated.lessons?[index] = lesson
                            } else {
                                updated.lessons?.append(lesson)
                            }
                        }
                    }
                    .id(exam.id)
                case .history:
                    HistoryView(attempts: exam.attempts) { pendingRemoval = $0 }
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity)
            .id(exam.id)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func heading(_ exam: Exam) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exam.name).font(.system(size: 34, weight: .bold))
            Button {
                sheet = .editExam
            } label: {
                Label("Цель \(points(exam.target)) из \(points(exam.maximum)) · Настроить экзамен", systemImage: "slider.horizontal.3")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var recordButton: some View {
        Button { sheet = .record } label: { Label("Записать результат", systemImage: "plus") }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }

    private func record(_ attempt: Attempt, for id: UUID) throws {
        try store.update(id) { $0.attempts.append(attempt) }
    }
}

func points(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...3)))
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary)
                    .allowsHitTesting(false)
            }
    }
}
