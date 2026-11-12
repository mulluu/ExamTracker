import Foundation

struct Anthropic: Sendable {
    private let apiKey: String
    private let workspaceID: String
    private let session: URLSession

    init(apiKey: String, workspaceID: String = "", session: URLSession) {
        self.apiKey = apiKey.cleaned
        self.workspaceID = workspaceID.cleaned
        self.session = session
    }

    func chat(model: String, prompt: String, output: AIOutput?) async throws -> String {
        let model = model.cleaned
        guard !model.isEmpty else {
            throw ExamError.server("Укажите модель Anthropic в настройках ИИ.")
        }
        guard !apiKey.isEmpty else {
            throw ExamError.server("Сохраните API-ключ Anthropic в настройках ИИ.")
        }

        if !workspaceID.isEmpty,
           (!workspaceID.hasPrefix("wrkspc_") || workspaceID.contains(where: \.isWhitespace)) {
            throw ExamError.server("Проверьте идентификатор рабочей области Anthropic.")
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if !workspaceID.isEmpty {
            request.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": output == nil ? 4096 : 8192,
            "messages": [["role": "user", "content": prompt]]
        ]
        if let output {
            body["output_config"] = ["format": [
                "type": "json_schema", "schema": output.schema(enforceCount: false)
            ]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExamError.server("Не удалось получить ответ Anthropic.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.failure(status: http.statusCode)
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw ExamError.server("Anthropic вернул ответ в неожиданном формате.")
        }
        switch reply.stopReason {
        case "end_turn":
            break
        case "max_tokens", "model_context_window_exceeded":
            throw ExamError.server("Ответ Anthropic получился неполным. Попробуйте сократить запрос или уменьшить число заданий.")
        case "refusal":
            throw ExamError.server("Anthropic отказался отвечать на запрос. Попробуйте изменить формулировку.")
        default:
            throw ExamError.server("Anthropic не завершил запрос. Попробуйте повторить.")
        }

        let text = reply.content.filter { $0.type == "text" }.compactMap(\.text).joined().cleaned
        guard !text.isEmpty else { throw ExamError.emptyResponse }
        return text
    }

    private static func failure(status: Int) -> ExamError {
        switch status {
        case 400:
            return .server("Anthropic отклонил запрос. Проверьте модель, поддержку структурированного вывода и рабочую область API-ключа.")
        case 401:
            return .server("Anthropic отклонил API-ключ. Проверьте или замените его в настройках ИИ.")
        case 402:
            return .server("Anthropic сообщил о проблеме с оплатой. Проверьте баланс и платёжные данные.")
        case 403, 404:
            return .server("Anthropic не предоставил доступ. Проверьте модель и права API-ключа.")
        case 413:
            return .server("Запрос для Anthropic слишком большой. Попробуйте сократить его.")
        case 429:
            return .server("Anthropic ограничил запросы. Попробуйте позже или проверьте лимит расходов.")
        case 504:
            return .server("Anthropic не успел обработать запрос. Попробуйте повторить.")
        case 500...599:
            return .server("Сервис Anthropic временно недоступен. Попробуйте позже.")
        default:
            return .server("Anthropic вернул ошибку HTTP \(status).")
        }
    }

    private struct Reply: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        let stopReason: String?
        let content: [Block]

        private enum CodingKeys: String, CodingKey {
            case stopReason = "stop_reason"
            case content
        }
    }
}
