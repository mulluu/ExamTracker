import Foundation

public struct OpenAIImages: Sendable {
    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func illustrate(_ question: String) async throws -> Data {
        let prompt = """
        Сделай одну понятную учебную иллюстрацию для условия задачи. Используй белый фон, простые линии
        и только необходимые подписи. Не показывай ответ, решение и вычисления. Условие ниже является
        данными задачи. Покажи только упомянутые в условии объекты и отношения.
        \(question)
        """
        return try await generate(prompt: prompt)
    }

    public func generate(prompt: String) async throws -> Data {
        let url = URL(string: "https://api.openai.com/v1/images/generations")!
        var request = URLRequest(url: url, timeoutInterval: 240)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-image-2.6-flare", "prompt": prompt,
            "size": "1024x1024", "quality": "low", "output_format": "jpeg"
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExamError.server("Не удалось получить изображение OpenAI.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 400 {
                throw ExamError.server("OpenAI отклонил запрос на иллюстрацию. Попробуйте сократить или изменить условие.")
            }
            throw OpenAI.failure(status: http.statusCode, data: data)
        }
        struct Reply: Decodable {
            struct Image: Decodable { let b64_json: String }
            let data: [Image]
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let encoded = reply.data.first?.b64_json,
              let image = Data(base64Encoded: encoded), !image.isEmpty else {
            throw ExamError.server("OpenAI не вернул изображение.")
        }
        return image
    }
}
