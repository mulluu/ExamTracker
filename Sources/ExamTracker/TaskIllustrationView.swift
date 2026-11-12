import ExamCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct TaskIllustrationView: View {
    let task: PracticeTask

    var body: some View {
        if let data = task.illustration, let image = NSImage(data: data) {
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 500, maxHeight: 260)
                    .accessibilityLabel("Иллюстрация к заданию")
                if task.generatedIllustration == true {
                    Text("Иллюстрация ИИ. Обозначения и пропорции могут отличаться от условия.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct TaskIllustrationEditor: View {
    @Binding var task: PracticeTask
    let ai: AIConfiguration
    @TrackerState private var picker = false
    @TrackerState private var job: Task<Void, Never>?
    @TrackerState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TaskIllustrationView(task: task)
            if task.illustration != nil {
                Toggle("Показывать иллюстрацию в условии", isOn: Binding(
                    get: { task.showsIllustrationInQuestion },
                    set: { task.illustrationInQuestion = $0 }
                ))
            }
            HStack {
                Button("Прикрепить изображение", systemImage: "photo") { picker = true }
                if ai.canGenerateImages {
                    Button("Создать иллюстрацию", systemImage: "sparkles") { generate() }
                        .disabled(task.prompt.cleaned.isEmpty)
                        .help("Условие отправится в OpenAI для генерации изображения")
                }
                if task.illustration != nil {
                    Button("Убрать", role: .destructive) {
                        task.illustration = nil
                        task.generatedIllustration = nil
                        task.illustrationInQuestion = nil
                    }
                }
            }
            .disabled(job != nil)
            if job != nil { ProgressView("Подготавливаем иллюстрацию…").controlSize(.small) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .fileImporter(isPresented: $picker, allowedContentTypes: [.image]) { result in
            error = nil
            do {
                let url = try result.get()
                run(generated: false) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try Self.thumbnail(from: url)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
        .onDisappear { job?.cancel() }
    }

    private func generate() {
        let prompt = task.prompt
        do {
            let client = OpenAIImages(apiKey: try CloudAIService.openAI.loadKey())
            run(generated: true) { try await client.illustrate(prompt) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func run(generated: Bool, operation: @escaping @Sendable () async throws -> Data) {
        error = nil
        job = Task {
            defer { job = nil }
            do {
                let data = try await operation()
                try Task.checkCancellation()
                guard NSImage(data: data) != nil else { throw ExamError.server("Не удалось открыть изображение.") }
                task.illustration = data
                task.generatedIllustration = generated ? true : nil
                task.illustrationInQuestion = nil
            } catch where !Task.isCancelled {
                self.error = error.localizedDescription
            } catch {}
        }
    }

    private nonisolated static func thumbnail(from url: URL) throws -> Data {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ExamError.server("Не удалось открыть изображение.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExamError.server("Не удалось подготовить изображение.")
        }
        return data as Data
    }
}

struct TaskSourceFragmentsView: View {
    let task: PracticeTask
    @TrackerState private var expanded: Bool
    @TrackerState private var selectedImage: SourceImage?

    init(task: PracticeTask, expanded: Bool) {
        self.task = task
        _expanded = TrackerState(initialValue: expanded)
    }

    var body: some View {
        if let fragments = task.sourceFragments, !fragments.isEmpty {
            DisclosureGroup("Оригинал из файла", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(fragments.indices, id: \.self) { index in
                        if let image = NSImage(data: fragments[index]) {
                            Button {
                                selectedImage = SourceImage(id: index, image: image)
                            } label: {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 520, maxHeight: 260)
                            }
                            .buttonStyle(.plain)
                            .help("Увеличить фрагмент оригинала")
                            .accessibilityLabel("Увеличить фрагмент \(index + 1)")
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .sheet(item: $selectedImage) { source in
                VStack(alignment: .trailing, spacing: 12) {
                    ScrollView([.vertical, .horizontal]) {
                        Image(nsImage: source.image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 740)
                            .accessibilityLabel("Фрагмент оригинала")
                    }
                    Button("Закрыть") { selectedImage = nil }.keyboardShortcut(.cancelAction)
                }
                .padding(16)
                .frame(width: 800, height: 650)
            }
        }
    }

    private struct SourceImage: Identifiable {
        let id: Int
        let image: NSImage
    }
}
