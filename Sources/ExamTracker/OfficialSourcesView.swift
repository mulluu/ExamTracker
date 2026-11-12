import ExamCore
import SwiftUI

struct OfficialSourcesView: View {
    let exam: Exam
    let onImport: () -> Void
    let onDownload: ((URL) -> Void)?

    init(exam: Exam, onImport: @escaping () -> Void, onDownload: ((URL) -> Void)? = nil) {
        self.exam = exam
        self.onImport = onImport
        self.onDownload = onDownload
    }

    var body: some View {
        let sources = OfficialSources.sources(for: exam)

        VStack(alignment: .leading, spacing: 12) {
            Label("Официальные источники", systemImage: "building.columns")
                .font(.headline)

            ForEach(sources) { source in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Link(destination: source.url) {
                            Label(source.title, systemImage: source.isArchive ? "archivebox" : source.isPDF ? "doc" : "arrow.up.right.square")
                        }
                        Text(source.organization)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if (source.isPDF || source.isArchive), let onDownload {
                        Spacer(minLength: 0)
                        Button("Загрузить в приложение", systemImage: "arrow.down.to.line") { onDownload(source.url) }
                            .buttonStyle(.bordered)
                    }
                }
            }

            Text(importInstructions(for: sources))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Импортировать скачанный файл…", systemImage: "square.and.arrow.down", action: onImport)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private func importInstructions(for sources: [OfficialSource]) -> String {
        if sources.isEmpty {
            return "Скачайте пробный вариант на сайте организатора экзамена, затем выберите файл для импорта."
        }
        if sources.first?.organization == "ФИПИ" {
            return "Из ZIP импортируется PDF. Аудио и дополнительные файлы можно открыть из распакованного архива."
        }
        return "Для пробников с повторяющимися номерами укажите страницы одного раздела."
    }
}
