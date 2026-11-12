import ExamCore
import Foundation
import Security

enum AIProvider: String, CaseIterable, Identifiable {
    case offline, ollama, openAI, anthropic

    var id: Self { self }

    var title: String {
        switch self {
        case .offline: "Без ИИ"
        case .ollama: "Ollama"
        case .openAI: "ChatGPT · OpenAI API"
        case .anthropic: "Claude · Anthropic API"
        }
    }

    var cloud: CloudAIService? {
        switch self {
        case .offline, .ollama: nil
        case .openAI: .openAI
        case .anthropic: .anthropic
        }
    }
}

struct AIModelOption: Identifiable {
    let id: String
    let title: String

    init(_ id: String, _ title: String) {
        self.id = id
        self.title = title
    }
}

struct AIConfiguration {
    let provider: AIProvider
    let model: String
    let hasCloudKey: Bool
    var workspaceID = ""

    var isConfigured: Bool {
        provider != .offline && !model.cleaned.isEmpty && (provider == .ollama || hasCloudKey)
    }

    var canGenerateImages: Bool { provider == .openAI && isConfigured }

    func client() throws -> ExamAI {
        if let cloud = provider.cloud {
            return try cloud.client(model: model, workspaceID: workspaceID)
        }
        guard provider == .ollama else {
            throw ExamError.server("ИИ выключен. Выберите провайдера в настройках ИИ.")
        }
        return ExamAI(ollamaModel: model)
    }
}

enum CloudAIService: String {
    case openAI, anthropic

    var name: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        }
    }

    var modelLabel: String {
        switch self {
        case .openAI: "Модель ChatGPT"
        case .anthropic: "Модель Claude"
        }
    }

    var models: [AIModelOption] {
        switch self {
        case .openAI: [
            AIModelOption("gpt-6-luna", "GPT-6 Luna · Экономная"),
            AIModelOption("gpt-6.1-terra", "GPT-6.1 Terra · Сбалансированная"),
            AIModelOption("gpt-6.1-sol", "GPT-6.1 Sol · Для сложных задач")
        ]
        case .anthropic: [
            AIModelOption("claude-haiku-5-5", "Claude Haiku 5.5 · Экономная"),
            AIModelOption("claude-sonnet-5-5", "Claude Sonnet 5.5 · Сбалансированная"),
            AIModelOption("claude-opus-5-5", "Claude Opus 5.5 · Для сложных задач")
        ]
        }
    }

    var defaultModel: String { models[0].id }

    func client(model: String, workspaceID: String = "") throws -> ExamAI {
        let key = try loadKey()
        switch self {
        case .openAI: return ExamAI(openAIModel: model, apiKey: key)
        case .anthropic: return ExamAI(anthropicModel: model, apiKey: key, workspaceID: workspaceID)
        }
    }

    private var keyQuery: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "app.examtracker.mac.\(rawValue.lowercased())",
        kSecAttrAccount as String: "\(name) API"
    ] }

    var hasKey: Bool {
        SecItemCopyMatching(keyQuery as CFDictionary, nil) == errSecSuccess
    }

    func loadKey() throws -> String {
        var result: CFTypeRef?
        var lookup = keyQuery
        lookup[kSecReturnData as String] = true
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        guard status != errSecItemNotFound else {
            throw ExamError.server("Сохраните API-ключ \(name) в настройках ИИ.")
        }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw ExamError.server("Не удалось прочитать ключ \(name) из Связки ключей macOS.")
        }
        return key
    }

    func saveKey(_ key: String) throws {
        let key = key.cleaned
        let prefix = self == .anthropic ? "sk-ant-" : "sk-"
        guard key.hasPrefix(prefix), key.count > prefix.count, !key.contains(where: \.isWhitespace),
              self != .openAI || !key.hasPrefix("sk-ant-") else {
            throw ExamError.server("Введите API-ключ \(name) целиком.")
        }
        let value = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(keyQuery as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(keyQuery.merging(value) { current, _ in current } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw ExamError.server("Не удалось сохранить ключ в Связке ключей macOS.")
        }
    }

    func removeKey() throws {
        let status = SecItemDelete(keyQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ExamError.server("Не удалось удалить ключ из Связки ключей macOS.")
        }
    }
}
