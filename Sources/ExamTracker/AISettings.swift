import ExamCore
import SwiftUI

struct AISettings: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var provider: AIProvider
    @Binding var ollamaModel: String
    @Binding var openAIModel: String
    @Binding var anthropicModel: String
    @Binding var hasOpenAIKey: Bool
    @Binding var hasAnthropicKey: Bool
    @Binding var anthropicWorkspaceID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Настройки ИИ").font(.title2.bold())
            Picker("Провайдер", selection: $provider) {
                ForEach(AIProvider.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            switch provider {
            case .offline:
                Text("Импорт, тренировки, таймер и статистика доступны без ИИ.")
                    .foregroundStyle(.secondary)
            case .ollama:
                OllamaSettings(model: $ollamaModel)
            case .openAI:
                CloudAISettings(service: .openAI, model: $openAIModel, hasKey: $hasOpenAIKey)
            case .anthropic:
                CloudAISettings(service: .anthropic, model: $anthropicModel, hasKey: $hasAnthropicKey,
                                workspaceID: $anthropicWorkspaceID)
            }
            HStack {
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

private struct CloudAISettings: View {
    let service: CloudAIService
    @Binding var model: String
    @Binding var hasKey: Bool
    @Binding var workspaceID: String
    @TrackerState private var usesCustomModel: Bool
    @TrackerState private var draftKey = ""
    @TrackerState private var status: String?
    @TrackerState private var error: String?
    @TrackerState private var check: Task<Void, Never>?

    init(service: CloudAIService, model: Binding<String>, hasKey: Binding<Bool>,
         workspaceID: Binding<String> = .constant("")) {
        self.service = service
        _model = model
        _hasKey = hasKey
        _workspaceID = workspaceID
        _usesCustomModel = TrackerState(initialValue: !service.models.contains { $0.id == model.wrappedValue.cleaned })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Выбранные условия, ответы и заметки могут отправляться в \(service.name). Запросы используют квоту API.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker(service.modelLabel, selection: modelChoice) {
                ForEach(service.models) { option in
                    Text(option.title).tag(option.id)
                }
                Text("Другая модель API").tag("")
            }
            if usesCustomModel {
                TextField("Идентификатор модели", text: $model,
                          prompt: Text(service.defaultModel))
            }
            SecureField(hasKey ? "Новый API-ключ" : "API-ключ \(service.name)", text: $draftKey)
                .textContentType(.password)
            if service == .anthropic {
                TextField("Рабочая область Anthropic", text: $workspaceID, prompt: Text("wrkspc_…"))
                Text("Укажите ID рабочей области, если ключ Anthropic к ней не привязан.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Сохранить ключ") { saveKey() }
                    .disabled(draftKey.cleaned.isEmpty || check != nil)
                if hasKey {
                    Button("Удалить ключ", role: .destructive) { removeKey() }
                        .disabled(check != nil)
                }
            }
            if hasKey {
                Label("Ключ сохранён в Связке ключей macOS", systemImage: "key.fill")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            HStack {
                Button("Проверить подключение") { checkConnection() }
                    .disabled(!hasKey || model.cleaned.isEmpty || check != nil)
                if check != nil { ProgressView().controlSize(.small) }
            }
            if let error { Text(error).foregroundStyle(.red) }
            if let status { Label(status, systemImage: "checkmark.circle").foregroundStyle(.green) }
        }
        .onChange(of: model) { status = nil; error = nil }
        .onChange(of: workspaceID) { status = nil; error = nil }
        .onDisappear { check?.cancel(); draftKey = "" }
    }

    private var modelChoice: Binding<String> {
        Binding(
            get: { usesCustomModel ? "" : model.cleaned },
            set: { selected in
                usesCustomModel = selected.isEmpty
                model = selected
            }
        )
    }

    private func saveKey() {
        status = nil
        error = nil
        do {
            try service.saveKey(draftKey)
            draftKey = ""
            hasKey = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func removeKey() {
        status = nil
        error = nil
        do {
            try service.removeKey()
            hasKey = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func checkConnection() {
        status = nil
        error = nil
        let selected = model.cleaned
        let workspace = workspaceID.cleaned
        check = Task {
            defer { check = nil }
            do {
                try await service.client(model: selected, workspaceID: workspace).checkConnection()
                if !Task.isCancelled && selected == model.cleaned && workspace == workspaceID.cleaned { status = "\(service.name) отвечает" }
            } catch where !Task.isCancelled && selected == model.cleaned && workspace == workspaceID.cleaned {
                self.error = error.localizedDescription
            } catch {}
        }
    }
}

private struct OllamaSettings: View {
    @Binding var model: String
    @TrackerState private var models: [String] = []
    @TrackerState private var reload = 0
    @TrackerState private var loading = false
    @TrackerState private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Выберите локальную модель для разбора тем и генерации тренировок.").foregroundStyle(.secondary)
            if loading {
                ProgressView("Поиск установленных моделей…")
            } else if let failure {
                Text(failure).foregroundStyle(.red)
            } else if models.isEmpty {
                if !model.isEmpty {
                    LabeledContent("Текущая модель", value: model)
                }
                Text(reload == 0 ? "Нажмите «Обновить список», чтобы увидеть установленные модели."
                    : "Установите модель в Ollama и обновите список.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Модель", selection: $model) {
                    Text("Выберите модель").tag("")
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
            }
            Button("Обновить список") { reload += 1 }.disabled(loading)
        }
        .task(id: reload) {
            guard reload > 0 else { return }
            loading = true
            failure = nil
            defer { loading = false }
            do {
                models = try await Ollama().models()
                if !models.contains(model) {
                    model = models.first { $0 == "qwen3.5:9b" } ?? models.first ?? ""
                }
            } catch where !Task.isCancelled {
                failure = error.localizedDescription
            } catch {}
        }
    }
}
