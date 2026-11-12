import Foundation
import Testing
@testable import ExamCore

struct PracticeSolutionSuggestionsTests {
    @Test func sendsOnlyEligibleTextAndKeepsOriginalTaskIDs() async throws {
        var math = PracticeTask(kind: "№8", prompt: "Найдите произведение 6 и 7.")
        math.sourceFragments = [Data([1, 2, 3])]
        let keyed = PracticeTask(prompt: "Задание с ключом", answer: "0")
        let picture = PracticeTask(prompt: "На рисунке показан график. Определите значение функции.")
        let uncertain = PracticeTask(prompt: "Определите результат, используя неизвестный параметр.")
        let result = try await client("valid").suggestSolutions(for: [math, keyed, picture, uncertain], exam: "ЕГЭ")
        #expect(result.count == 1)
        #expect(result[math.id]?.answer == "42")
        #expect(result[math.id]?.explanation == "Умножаем 6 на 7.")
        #expect(result[keyed.id] == nil)
        #expect(result[picture.id] == nil)
        #expect(result[uncertain.id] == nil)
        #expect(math.answer.isEmpty)
    }

    @Test func neverContactsProviderWhenNoTextTaskNeedsAKey() async throws {
        let client = ExamAI(openAIModel: "", apiKey: "")
        let keyed = PracticeTask(prompt: "Найдите число.", answer: "5")
        let page = PracticeTask(prompt: "Решите задания на приложенной странице.")
        let english = PracticeTask(prompt: "Find the slope from the graph shown below.")
        let file = PracticeTask(prompt: "Найдите среднее по данным приложенного файла.")
        let image = PracticeTask(prompt: "Определите форму. ![рисунок](source.png)")
        #expect(!page.canSuggestSolutionFromText)
        #expect(!english.canSuggestSolutionFromText)
        #expect(!file.canSuggestSolutionFromText)
        #expect(!image.canSuggestSolutionFromText)
        let result = try await client.suggestSolutions(for: [keyed, page, english, file, image, PracticeTask()], exam: "SAT")
        #expect(result.isEmpty)
    }

    @Test(arguments: ["duplicate", "unknown-index", "partial", "omitted", "blank"])
    func rejectsMalformedSuggestions(_ scenario: String) async {
        let task = PracticeTask(prompt: "Чему равно 6 × 7?")
        await #expect(throws: ExamError.self) {
            try await client(scenario).suggestSolutions(for: [task], exam: "Математика")
        }
    }

    private func client(_ scenario: String) -> ExamAI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SolutionSuggestionStub.self]
        return ExamAI(openAIModel: "test", apiKey: scenario, session: URLSession(configuration: config))
    }
}

private final class SolutionSuggestionStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let reply = try replyText()
            let data = try JSONSerialization.data(withJSONObject: [
                "status": "completed",
                "output": [["type": "message", "content": [["type": "output_text", "text": reply]]]]
            ])
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func replyText() throws -> String {
        switch request.value(forHTTPHeaderField: "Authorization") {
        case "Bearer valid":
            let body = try #require(JSONSerialization.jsonObject(with: requestBody()) as? [String: Any])
            let input = try #require(body["input"] as? String)
            #expect(input.contains("Найдите произведение 6 и 7."))
            #expect(input.contains("Определите результат"))
            #expect(!input.contains("Задание с ключом"))
            #expect(!input.contains("На рисунке показан график"))
            #expect(!input.contains("AQID"))
            let text = try #require(body["text"] as? [String: Any])
            let format = try #require(text["format"] as? [String: Any])
            #expect(format["type"] as? String == "json_schema")
            return #"{"suggestions":[{"number":2,"answer":null,"explanation":null},{"number":1,"answer":" 42 ","explanation":" Умножаем 6 на 7. "}]}"#
        case "Bearer duplicate":
            return #"{"suggestions":[{"number":1,"answer":"42","explanation":"6 × 7"},{"number":1,"answer":null,"explanation":null}]}"#
        case "Bearer unknown-index":
            return #"{"suggestions":[{"number":2,"answer":"42","explanation":"6 × 7"}]}"#
        case "Bearer partial":
            return #"{"suggestions":[{"number":1,"answer":"42","explanation":null}]}"#
        case "Bearer omitted":
            return #"{"suggestions":[{"number":1}]}"#
        case "Bearer blank":
            return #"{"suggestions":[{"number":1,"answer":" ","explanation":"6 × 7"}]}"#
        default:
            throw URLError(.cannotParseResponse)
        }
    }

    private func requestBody() throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotParseResponse) }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
