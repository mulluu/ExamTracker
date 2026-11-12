import ExamCore
import SwiftUI

struct ScoreImportView: View {
    let ai: AIConfiguration
    let onImport: (ImportedScores) -> Void

    @Environment(\.dismiss) private var dismiss
    @TrackerState private var choosingFile = false
    @TrackerState private var fileName: String?
    @TrackerState private var text = ""
    @TrackerState private var operation: Operation?
    @TrackerState private var error: String?

    private enum Operation: Equatable {
        case read(URL)
        case extract(String)

        var status: String {
            switch self {
            case .read: "Читаем файл…"
            case .extract: "Извлекаем баллы…"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Импорт результата пробника") {
                    HStack {
                        Button("Выбрать файл…") { choosingFile = true }
                        if let fileName {
                            Text(fileName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(fileName)
                        } else {
                            Text("PDF, DOCX, TXT или изображение")
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Текст результата")
                        TextEditor(text: $text)
                            .font(.body)
                            .frame(height: 175)
                            .border(.quaternary)
                            .accessibilityLabel("Текст результата")
                            .overlay(alignment: .topLeading) {
                                if text.isEmpty {
                                    Text("Вставьте текст или выберите файл.")
                                        .foregroundStyle(.secondary)
                                        .padding(6)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                            }
                    }

                    if let providerNotice {
                        Text(providerNotice)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if !ai.isConfigured {
                        Text("Выберите и настройте провайдера в разделе «Настройки ИИ».")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(operation != nil)

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
                if let operation {
                    ProgressView(operation.status)
                        .controlSize(.small)
                }
                Button("Извлечь баллы") { start(.extract(text.cleaned)) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!ai.isConfigured || operation != nil || text.cleaned.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 590, height: 455)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: TaskImport.fileTypes) { result in
            switch result {
            case .success(let file): start(.read(file))
            case .failure(let error): self.error = error.localizedDescription
            }
        }
        .task(id: operation) { [operation] in
            if let operation { await run(operation) }
        }
    }

    private var providerNotice: String? {
        switch ai.provider {
        case .offline:
            nil
        case .openAI, .anthropic:
            ai.provider.cloud.map { "При нажатии «Извлечь баллы» текст отправится в \($0.name). Перед отправкой его можно отредактировать." }
        case .ollama:
            "Текст обработает локальная модель Ollama. Его можно отредактировать перед извлечением баллов."
        }
    }

    private func start(_ operation: Operation) {
        error = nil
        self.operation = operation
    }

    private func run(_ operation: Operation) async {
        defer {
            if !Task.isCancelled { self.operation = nil }
        }
        do {
            try Task.checkCancellation()
            switch operation {
            case .read(let file):
                let worker = Task.detached(priority: .userInitiated) { try TaskImport.read(file) }
                let document = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                text = document
                fileName = file.lastPathComponent
            case .extract(let text):
                let scores = try await ai.client().importScores(from: text)
                try Task.checkCancellation()
                onImport(scores)
                dismiss()
            }
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
