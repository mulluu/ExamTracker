import ExamCore
import Foundation
import SwiftUI

struct TaskImportView: View {
    let exam: Exam
    let initialURL: URL?
    let onImport: (PracticeSet) -> Void

    @Environment(\.dismiss) private var dismiss
    @TrackerState private var choosingFile = false
    @TrackerState private var source: (name: String, url: URL?)?
    @TrackerState private var document: TaskImportDocument?
    @TrackerState private var pages = ""
    @TrackerState private var numbers = ""
    @TrackerState private var topic = ""
    @TrackerState private var error: String?
    @TrackerState private var loading: (label: String, task: Task<Void, Never>)?

    init(exam: Exam, initialURL: URL? = nil, onImport: @escaping (PracticeSet) -> Void) {
        self.exam = exam
        self.initialURL = initialURL
        self.onImport = onImport
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Импорт заданий") {
                    LabeledContent("Файл") {
                        HStack {
                            if let source {
                                Text(source.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(source.name)
                            }
                            Button(source == nil ? "Выбрать файл…" : "Заменить…") { choosingFile = true }
                                .disabled(loading != nil)
                        }
                    }

                    if let loading {
                        ProgressView(loading.label)
                            .controlSize(.small)
                    }

                    if let document, document.pageCount > 1 {
                        TextField("Страницы PDF", text: $pages,
                                  prompt: Text("Все страницы (1–\(document.pageCount))"))
                    }

                    TextField("Номера заданий", text: $numbers, prompt: Text("Все найденные, или, например, 1, 3, 6–8"))

                    if !exam.topics.isEmpty {
                        Picker("Общая тема", selection: $topic) {
                            Text("Без темы").tag("")
                            ForEach(exam.topics, id: \.self) { Text($0).tag($0) }
                        }
                    }

                    Text("При импорте PDF и фото приложение сохраняет фрагменты оригинала с рисунками и таблицами.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }

            HStack {
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if let document {
                    Button(document.hasPageImages ? "Страницы целиком" : "Документ целиком") {
                        preview(asPages: true)
                    }
                        .disabled(loading != nil)
                }
                Button("Проверить задания") { preview(asPages: false) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(document == nil || loading != nil)
            }
            .padding(20)
        }
        .frame(width: 590, height: 350)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: TaskImport.fileTypes) { result in
            switch result {
            case .success(let selected):
                let subject = exam.name
                read(fileName: selected.lastPathComponent, status: "Читаем файл…") {
                    try TaskImport.readDocument(selected, preferredSubject: subject)
                }
            case .failure(let error):
                self.error = error.localizedDescription
            }
        }
        .task {
            guard let initialURL, source == nil else { return }
            let subject = exam.name
            let name = initialURL.lastPathComponent.cleaned
            read(fileName: name.isEmpty ? "Материалы" : name, sourceURL: initialURL, status: "Загружаем материалы…") {
                try await Self.downloadDocument(initialURL, preferredSubject: subject)
            }
        }
        .onDisappear { loading?.task.cancel() }
    }

    private func read(fileName: String, sourceURL: URL? = nil, status: String,
                      action: @escaping @Sendable () async throws -> TaskImportDocument) {
        loading?.task.cancel()
        error = nil
        source = (fileName, sourceURL)
        document = nil
        pages = ""
        let task = Task {
            let worker = Task.detached(priority: .userInitiated, operation: action)
            defer {
                if !Task.isCancelled { loading = nil }
            }
            do {
                let imported = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                document = imported
                if let name = imported.containedFileName { source = (name, sourceURL) }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
        loading = (status, task)
    }

    private func preview(asPages: Bool) {
        guard let source, let document, loading == nil else { return }
        do {
            let selection = asPages || numbers.cleaned.isEmpty ? [] : try TaskImport.selectedNumbers(numbers)
            let selectedPages = pages.cleaned.isEmpty ? [] : try TaskImport.selectedNumbers(pages)
            let topic = topic
            error = nil
            let job = Task {
                let worker = Task.detached(priority: .userInitiated) {
                    try asPages ? document.pageTasks(on: selectedPages, topic: topic)
                        : document.tasks(selecting: selection, on: selectedPages, topic: topic)
                }
                defer { if !Task.isCancelled { loading = nil } }
                do {
                    let tasks = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    try Task.checkCancellation()
                    let title = (source.name as NSString).deletingPathExtension.cleaned
                    var set = PracticeSet(title: title.isEmpty ? "Импортированные задания" : title, tasks: tasks)
                    set.sourceURL = source.url
                    onImport(set)
                } catch {
                    if !Task.isCancelled { self.error = error.localizedDescription }
                }
            }
            loading = ("Извлекаем задания…", job)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private nonisolated static func downloadDocument(_ url: URL, preferredSubject: String) async throws -> TaskImportDocument {
        guard url.scheme?.lowercased() == "https" else { throw DownloadError.invalidURL }
        let (download, response) = try await URLSession.shared.download(from: url)
        let files = FileManager.default
        defer { try? files.removeItem(at: download) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.url?.scheme?.lowercased() == "https" else {
            throw DownloadError.failedResponse
        }

        let handle = try FileHandle(forReadingFrom: download)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 1024) ?? Data()
        let fileExtension: String
        if header.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            fileExtension = "zip"
        } else if header.range(of: Data("%PDF-".utf8)) != nil {
            fileExtension = "pdf"
        } else {
            throw DownloadError.invalidFile
        }

        let temporaryFile = files.temporaryDirectory.appending(path: "\(UUID()).\(fileExtension)")
        defer { try? files.removeItem(at: temporaryFile) }
        try files.moveItem(at: download, to: temporaryFile)
        return try TaskImport.readDocument(temporaryFile, preferredSubject: preferredSubject)
    }

    private enum DownloadError: LocalizedError {
        case invalidURL, failedResponse, invalidFile

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Для загрузки нужна ссылка HTTPS."
            case .failedResponse: "Сайт не вернул файл. Можно выбрать скачанные материалы вручную."
            case .invalidFile: "По ссылке открывается файл другого формата. Выберите PDF или ZIP вручную."
            }
        }
    }
}
