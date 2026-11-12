import Foundation

public struct Ollama: Sendable {
    private let session: URLSession
    private let baseURL = URL(string: "http://127.0.0.1:11434")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func models() async throws -> [String] {
        struct ModelList: Decodable {
            struct Model: Decodable {
                let name: String
                let remote_host: String?
                let remote_model: String?
            }
            let models: [Model]
        }
        let data = try await send(URLRequest(url: baseURL.appending(path: "api/tags"), timeoutInterval: 5))
        return try JSONDecoder().decode(ModelList.self, from: data).models
            .filter { $0.remote_host == nil && $0.remote_model == nil && !$0.name.hasSuffix("-cloud") && !$0.name.hasSuffix(":cloud") }
            .map(\.name)
            .sorted()
    }

    func chat(model: String, prompt: String, output: AIOutput?) async throws -> String {
        guard !model.cleaned.isEmpty else { throw ExamError.noModel }
        guard try await models().contains(model) else {
            throw ExamError.server("Модель «\(model)» недоступна. Выберите локальную модель в настройках.")
        }
        var request = URLRequest(url: baseURL.appending(path: "api/chat"), timeoutInterval: 600)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model, "stream": false,
            "messages": [["role": "user", "content": prompt]],
            "options": ["temperature": 0.3, "num_predict": 6500]
        ]
        if let output {
            body["format"] = output.schema(enforceCount: true)
            if model.lowercased().hasPrefix("qwen3") {
                body["think"] = false
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        struct Reply: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
            let done_reason: String?
        }
        let reply = try JSONDecoder().decode(Reply.self, from: await send(request))
        if reply.done_reason == "length" {
            throw ExamError.server("Ответ модели оборвался. Попробуйте уменьшить количество заданий.")
        }
        let content = reply.message.content.cleaned
        guard !content.isEmpty else { throw ExamError.emptyResponse }
        return content
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .notConnectedToInternet {
            throw ExamError.server("Ollama недоступен. Запустите Ollama на этом Mac и повторите запрос.")
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            struct Failure: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? "Не удалось получить ответ."
            throw ExamError.server("Ollama: \(message)")
        }
        return data
    }
}
