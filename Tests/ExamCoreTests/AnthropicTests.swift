import Foundation
import Testing
@testable import ExamCore

struct AnthropicTests {
    @Test func sendsMessagesAndReadsTextAfterThinkingBlocks() async throws {
        let text = try await client().chat(model: " claude-sonnet-5-5 ", prompt: "plain", output: nil)
        #expect(text == "Проверь формулу.")
    }

    @Test func requestsStructuredScoresWithNullableFields() async throws {
        let text = try await client().chat(model: "claude-haiku-5-5", prompt: "scores", output: .scores)
        let scores = try JSONDecoder().decode(ImportedScores.self, from: Data(text.utf8))
        #expect(scores.primaryEarned == 0)
        #expect(scores.primaryMaximum == nil)
        #expect(scores.finalEarned == 42)
    }

    @Test func examAIImportsScoresUsingAnthropicWorkspace() async throws {
        let api = ExamAI(anthropicModel: "claude-haiku-5-5", apiKey: "test-anthropic-secret",
                         workspaceID: " wrkspc_test ", session: stubSession())
        let result = try await api.importScores(from: "Первичные: 0. Тестовые: 42.")
        #expect(result.primaryEarned == 0)
        #expect(result.finalEarned == 42)
    }

    @Test(arguments: [
        ("401", "API-ключ"), ("402", "баланс"), ("429", "лимит"), ("529", "временно недоступен")
    ])
    func reportsHttpErrorsWithoutEchoingServerMessages(status: String, description: String) async throws {
        do {
            _ = try await client().chat(model: "claude-opus-5-5", prompt: status, output: nil)
            Issue.record("Expected an HTTP error for \(status)")
        } catch let error as ExamError {
            #expect(error.localizedDescription.contains(description))
            #expect(!error.localizedDescription.contains("test-anthropic-secret"))
        }
    }

    @Test(arguments: [
        ("max_tokens", "неполным"), ("model_context_window_exceeded", "неполным"),
        ("refusal", "отказался"), ("tool_use", "не завершил"), ("stop_sequence", "не завершил")
    ])
    func doesNotReturnPartialOrRefusedResponses(reason: String, description: String) async throws {
        do {
            _ = try await client().chat(model: "claude-opus-5-5", prompt: reason, output: .topics)
            Issue.record("Expected a stop error for \(reason)")
        } catch let error as ExamError {
            #expect(error.localizedDescription.contains(description))
            #expect(!error.localizedDescription.contains("Частичный текст"))
        }
    }

    @Test func rejectsCompletedResponsesWithNoText() async throws {
        do {
            _ = try await client().chat(model: "claude-opus-5-5", prompt: "empty", output: nil)
            Issue.record("Expected an empty response error")
        } catch ExamError.emptyResponse {
        }
    }

    private func client() -> Anthropic {
        Anthropic(apiKey: "test-anthropic-secret", session: stubSession())
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnthropicStub.self]
        return URLSession(configuration: configuration)
    }
}

private final class AnthropicStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try #require(request.url)
            let (status, body) = try response()
            let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                                        headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: body))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func response() throws -> (Int, [String: Any]) {
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-anthropic-secret")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(JSONSerialization.jsonObject(with: bodyData()) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: String]])
        let message = try #require(messages.first)
        #expect(messages.count == 1)
        #expect(message["role"] == "user")
        #expect((body["max_tokens"] as? Int ?? 0) > 0)
        let prompt = try #require(message["content"])
        let workspace = request.value(forHTTPHeaderField: "anthropic-workspace-id")
        let scoreImport = prompt.contains("Первичные: 0. Тестовые: 42.")
        #expect(workspace == (scoreImport ? "wrkspc_test" : nil))
        switch scoreImport ? "scores" : prompt {
        case "plain":
            #expect(body["model"] as? String == "claude-sonnet-5-5")
            #expect(body["output_config"] == nil)
            return (200, ["stop_reason": "end_turn", "content": [
                ["type": "thinking", "thinking": "Internal reasoning"],
                ["type": "text", "text": " Проверь "],
                ["type": "text", "text": "формулу. "]
            ]])
        case "scores":
            #expect(body["model"] as? String == "claude-haiku-5-5")
            let output = try #require(body["output_config"] as? [String: Any])
            let format = try #require(output["format"] as? [String: Any])
            let schema = try #require(format["schema"] as? [String: Any])
            let properties = try #require(schema["properties"] as? [String: [String: [String]]])
            #expect(format["type"] as? String == "json_schema")
            #expect(schema["additionalProperties"] as? Bool == false)
            #expect(properties["primaryMaximum"]?["type"] == ["number", "null"])
            let text = #"{"primaryEarned":0,"primaryMaximum":null,"finalEarned":42,"finalMaximum":null}"#
            return (200, ["stop_reason": "end_turn", "content": [["type": "text", "text": text]]])
        case "empty":
            return (200, ["stop_reason": "end_turn", "content": [["type": "thinking"]]])
        default:
            if let status = Int(prompt) {
                return (status, ["type": "error", "error": ["message": "test-anthropic-secret"]])
            }
            return (200, ["stop_reason": prompt, "content": [["type": "text", "text": "Частичный текст"]]])
        }
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
