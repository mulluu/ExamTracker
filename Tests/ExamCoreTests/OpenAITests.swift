import Foundation
import Testing
@testable import ExamCore

struct OpenAITests {
    @Test func generatesPracticeUsingStrictResponseSchema() async throws {
        let client = ExamAI(openAIModel: "gpt-6-luna", apiKey: "test-generation", session: stubSession())
        let tasks = try await client.generate(exam: "Математика", topics: "Алгебра", kind: "№6", count: 1, sample: "")
        #expect(tasks.count == 1)
        #expect(tasks.first?.answer == "2")
        #expect(tasks.first?.kind == "№6")
    }

    @Test func explainsTopicFromMessageAfterReasoningItem() async throws {
        let client = ExamAI(openAIModel: "gpt-6-luna", apiKey: "test-explanation", session: stubSession())
        let attempt = try Attempt(title: "Пробник", scores: [
            TaskScore(topic: "Алгебра", earned: 0, maximum: 1, response: "x = 7")
        ])
        let exam = Exam(name: "Математика", attempts: [attempt])
        let topic = try #require(exam.topicStats.first)
        let explanation = try await client.explain(exam: exam, topic: topic)
        #expect(explanation == "Проверь перенос слагаемых.")
    }

    @Test func reportsAuthenticationErrorWithoutEchoingCredentials() async throws {
        let client = ExamAI(openAIModel: "gpt-6-luna", apiKey: "test-unauthorized", session: stubSession())
        do {
            try await client.checkConnection()
            Issue.record("Expected an authentication error")
        } catch {
            #expect(error.localizedDescription.contains("API-ключ"))
            #expect(!error.localizedDescription.contains("test-unauthorized"))
        }
    }

    @Test func doesNotReturnIncompleteOpenAIOutput() async throws {
        let client = ExamAI(openAIModel: "gpt-6-luna", apiKey: "test-incomplete", session: stubSession())
        await #expect(throws: ExamError.self) {
            try await client.checkConnection()
        }
    }

    @Test func extractsPrimaryAndFinalScoresWithoutFillingUnknownMaximum() async throws {
        let client = ExamAI(openAIModel: "gpt-6-luna", apiKey: "test-scores", session: stubSession())
        let scores = try await client.importScores(from: "Первичные: 0. Тестовые: 27 из 100.")
        #expect(scores.primaryEarned == 0)
        #expect(scores.primaryMaximum == nil)
        #expect(scores.finalEarned == 27)
        #expect(scores.finalMaximum == 100)
    }

    @Test func suggestsAndNormalizesExamTopics() async throws {
        let client = ExamAI(openAIModel: "gpt-6-luna", apiKey: "test-topics", session: stubSession())
        let topics = try await client.suggestTopics(for: "ЕГЭ по математике")
        #expect(topics == ["Алгебра", "Геометрия"])
    }

    @Test func classifiesByOriginalTaskNumberAndUsesExistingTopicSpelling() async throws {
        let client = ExamAI(openAIModel: "gpt-6-luna", apiKey: "test-classification", session: stubSession())
        let first = PracticeTask(prompt: "Решите уравнение")
        let second = PracticeTask(prompt: "Найдите площадь")
        let exam = Exam(name: "Математика", topics: ["Алгебра", "Геометрия"])
        let tags = try await client.classify([first, second], for: exam)
        #expect(tags[first.id] == "Алгебра")
        #expect(tags[second.id] == "Геометрия")
    }

    @Test func requestsIllustrationFromImagesEndpoint() async throws {
        let client = OpenAIImages(apiKey: "test-image", session: stubSession())
        let image = try await client.illustrate("Найдите площадь треугольника")
        #expect(image == Data([1, 2, 3]))
    }

    @Test func sendsLessonImagePromptToTheImageModel() async throws {
        let client = OpenAIImages(apiKey: "test-lesson-image", session: stubSession())
        let request = ExamLessonRequest(exam: "Физика", topic: "Преломление", kind: "", wantsIllustration: true)
        let lesson = ExamLesson(topic: "Преломление", kind: "", content: "## Правило\nПокажи границу сред.")
        let image = try await client.generate(prompt: request.illustrationPrompt(lesson: lesson))
        #expect(image == Data([1, 2, 3]))
    }

    @Test func localProviderStillUsesOnlyLoopbackAndLocalModels() async throws {
        let client = ExamAI(ollamaModel: "local-model", session: stubSession())
        try await client.checkConnection()
    }

    private func stubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenAIStub.self]
        return URLSession(configuration: config)
    }
}

private final class OpenAIStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (status, body) = try response()
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func response() throws -> (Int, Data) {
        if request.url?.host == "127.0.0.1" {
            #expect(request.url?.port == 11434)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            if request.url?.path == "/api/tags" {
                #expect(request.httpMethod == "GET")
                return (200, Data(#"{"models":[{"name":"local-model"}]}"#.utf8))
            }
            #expect(request.url?.path == "/api/chat")
            #expect(request.httpMethod == "POST")
            return (200, Data(#"{"message":{"content":"готово"},"done_reason":"stop"}"#.utf8))
        }
        #expect(request.httpMethod == "POST")
        let data = try bodyData()
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        if authorization == "Bearer test-image" {
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/images/generations")
            #expect(body["model"] as? String == "gpt-image-2.6-flare")
            #expect((body["prompt"] as? String)?.contains("Найдите площадь треугольника") == true)
            return (200, Data(#"{"data":[{"b64_json":"AQID"}]}"#.utf8))
        }
        if authorization == "Bearer test-lesson-image" {
            #expect(request.url?.path == "/v1/images/generations")
            #expect(body["model"] as? String == "gpt-image-2.6-flare")
            let prompt = try #require(body["prompt"] as? String)
            #expect(prompt.contains("Преломление"))
            #expect(prompt.contains("Покажи границу сред."))
            return (200, Data(#"{"data":[{"b64_json":"AQID"}]}"#.utf8))
        }
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(body["model"] as? String == "gpt-6-luna")
        #expect(body["store"] as? Bool == false)
        let input = try #require(body["input"] as? String)
        let text: String
        var status = "completed"
        switch authorization {
        case "Bearer test-generation":
            let settings = try #require(body["text"] as? [String: Any])
            let format = try #require(settings["format"] as? [String: Any])
            let schema = try #require(format["schema"] as? [String: Any])
            let properties = try #require(schema["properties"] as? [String: Any])
            let tasks = try #require(properties["tasks"] as? [String: Any])
            let items = try #require(tasks["items"] as? [String: Any])
            #expect(format["type"] as? String == "json_schema")
            #expect(format["strict"] as? Bool == true)
            #expect(schema["additionalProperties"] as? Bool == false)
            #expect(items["additionalProperties"] as? Bool == false)
            #expect(input.contains("№6"))
            text = #"{"tasks":[{"topic":"Алгебра","kind":"№6","prompt":"Решите x = 2","answer":"2","solution":"x уже выражен","maximum":1}]}"#
        case "Bearer test-explanation":
            #expect(body["text"] == nil)
            #expect(input.contains("x = 7"))
            text = "Проверь перенос слагаемых."
        case "Bearer test-unauthorized":
            return (401, Data(#"{"error":{"code":"invalid_api_key","message":"Invalid API key: test-unauthorized"}}"#.utf8))
        case "Bearer test-incomplete":
            status = "incomplete"
            text = "Частичный результат"
        case "Bearer test-scores":
            #expect(input.contains("Первичные: 0"))
            text = #"{"primaryEarned":0,"primaryMaximum":null,"finalEarned":27,"finalMaximum":100}"#
        case "Bearer test-topics":
            #expect(input.contains("ЕГЭ по математике"))
            text = #"{"topics":[" Алгебра","алгебра","Геометрия",""]}"#
        case "Bearer test-classification":
            #expect(input.contains("availableTopics"))
            text = #"{"assignments":[{"number":2,"topic":"геометрия"},{"number":1,"topic":"Алгебра"}]}"#
        default:
            throw URLError(.userAuthenticationRequired)
        }
        let response: [String: Any] = [
            "status": status, "output": [
                ["type": "reasoning"],
                ["type": "message", "content": [["type": "output_text", "text": text]]]
            ]
        ]
        return (200, try JSONSerialization.data(withJSONObject: response))
    }

    private func bodyData() throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count == 0 { return data }
            guard count > 0 else { throw stream.streamError ?? URLError(.cannotParseResponse) }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
