import Foundation

struct OpenAI: Sendable {
    let apiKey: String
    let session: URLSession

    func chat(model: String, prompt: String, output: AIOutput?) async throws -> String {
        guard !model.cleaned.isEmpty else {
            throw ExamError.server("Укажите модель OpenAI в настройках ИИ.")
        }
        guard !apiKey.cleaned.isEmpty else {
            throw ExamError.server("Сохраните API-ключ OpenAI в настройках ИИ.")
        }
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "model": model.cleaned, "input": prompt, "store": false,
            "max_output_tokens": output != nil ? 8192 : 3000
        ]
        if let output {
            body["text"] = ["format": [
                "type": "json_schema", "name": "exam_tracker_result",
                "strict": true, "schema": output.schema(enforceCount: false)
            ]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExamError.server("Не удалось получить ответ OpenAI.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.failure(status: http.statusCode, data: data)
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw ExamError.server("OpenAI вернул ответ в неожиданном формате.")
        }
        switch reply.status {
        case "completed":
            break
        case "incomplete":
            throw ExamError.server("Ответ OpenAI получился неполным. Попробуйте сократить запрос или уменьшить число заданий.")
        default:
            throw ExamError.server("OpenAI не завершил запрос. Попробуйте повторить.")
        }

        let content = reply.output.filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        if content.contains(where: { $0.type == "refusal" }) {
            throw ExamError.server("OpenAI отказался отвечать на запрос. Попробуйте изменить формулировку.")
        }
        let text = content.filter { $0.type == "output_text" }.compactMap(\.text).joined().cleaned
        guard !text.isEmpty else { throw ExamError.emptyResponse }
        return text
    }

    static func failure(status: Int, data: Data) -> ExamError {
        struct APIError: Decodable {
            struct Details: Decodable { let code: String? }
            let error: Details
        }
        let code = (try? JSONDecoder().decode(APIError.self, from: data))?.error.code
        switch status {
        case 400:
            return .server("OpenAI отклонил запрос. Проверьте модель и поддержку Responses API со структурированным выводом.")
        case 401:
            return .server("OpenAI отклонил API-ключ. Проверьте или замените его в настройках ИИ.")
        case 403, 404:
            return .server("OpenAI не предоставил доступ. Проверьте название модели, доступ к ней и права API-ключа.")
        case 429 where code == "insufficient_quota":
            return .server("В проекте OpenAI закончилась доступная квота. Проверьте баланс и лимиты API.")
        case 429:
            return .server("OpenAI ограничил частоту запросов. Попробуйте немного позже.")
        case 500...599:
            return .server("Сервис OpenAI временно недоступен. Попробуйте позже.")
        default:
            return .server("OpenAI вернул ошибку HTTP \(status).")
        }
    }

    private struct Reply: Decodable {
        struct Item: Decodable {
            struct Part: Decodable {
                let type: String
                let text: String?
            }
            let type: String
            let content: [Part]?
        }
        let status: String
        let output: [Item]
    }
}
