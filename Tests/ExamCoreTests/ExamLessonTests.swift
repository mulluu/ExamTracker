import Foundation
import Testing
@testable import ExamCore

struct ExamLessonTests {
    @Test func restoresSavedLessonWithItsFiltersAndText() throws {
        let lesson = ExamLesson(topic: "Производные", kind: "№12", content: "Правило и пример", date: .init(timeIntervalSince1970: 100))
        var exam = Exam(name: "Профильная математика")
        exam.lessons = [lesson]

        let data = try JSONEncoder().encode(exam)
        let restored = try JSONDecoder().decode(Exam.self, from: data)

        let saved = try #require(restored.lessons?.first)
        #expect(saved.id == lesson.id)
        #expect(saved.date == Date(timeIntervalSince1970: 100))
        #expect(saved.topic == "Производные")
        #expect(saved.kind == "№12")
        #expect(saved.content == "Правило и пример")
        #expect(saved.illustration == nil)
    }

    @Test func persistsOptionalIllustration() throws {
        let illustration = Data([1, 2, 3])
        let lesson = ExamLesson(topic: "Оптика", kind: "", content: "Преломление света", illustration: illustration)
        let restored = try JSONDecoder().decode(ExamLesson.self, from: JSONEncoder().encode(lesson))
        #expect(restored.illustration == illustration)
    }

    @Test func lessonPromptUsesTaskContextAndFormatting() throws {
        let request = ExamLessonRequest(exam: "SAT Math", topic: " Квадратные функции ", kind: "№5",
                                        taskContext: "График y = x^2\nТочка (2, 4)")
        let prompt = try request.prompt()
        let lastLine = try #require(prompt.split(separator: "\n").last)
        let context = try JSONDecoder().decode([String: String].self, from: Data(lastLine.utf8))
        #expect(context["exam"] == "SAT Math")
        #expect(context["topic"] == "Квадратные функции")
        #expect(context["kind"] == "№5")
        #expect(context["taskContext"] == "График y = x^2\nТочка (2, 4)")
        #expect(prompt.contains("Markdown"))
        #expect(prompt.contains("x²"))
        #expect(prompt.contains("Самопроверка"))
        #expect(!prompt.contains("отдельным запросом"))
    }

    @Test func illustrationOptInAddsInstructionsAndSeparatePrompt() throws {
        let request = ExamLessonRequest(exam: "Физика", topic: "Оптика", kind: "№12", wantsIllustration: true)
        let lesson = ExamLesson(topic: "Оптика", kind: "№12", content: "Покажи преломление света.")
        #expect(try request.prompt().contains("отдельным запросом"))
        let imagePrompt = request.illustrationPrompt(lesson: lesson)
        #expect(imagePrompt.contains("Физика"))
        #expect(imagePrompt.contains("Оптика"))
        #expect(imagePrompt.contains("Покажи преломление света."))
    }

    @Test func formatsCommonExponentsInNewAndSavedLessons() {
        let lesson = ExamLesson(topic: "Алгебра", kind: "", content: #"x^2, 10^{-3}, (a+b)^(n+1), \(2^12\), y², a^{β+(n−1)}"#)
        #expect(lesson.displayContent == "x², 10⁻³, (a+b)ⁿ⁺¹, 2¹², y², aᵝ⁺⁽ⁿ⁻¹⁾")
        let literal = ExamLesson(topic: "Алгебра", kind: "", content: "^, x^2.5, x^foo, x^{1/2}, x^2^3, `x^n`")
        #expect(literal.displayContent == literal.content)
    }

    @Test func taskContextOnlyHasReadableTitle() throws {
        let request = ExamLessonRequest(exam: "Физика", topic: "", kind: "", taskContext: "Вычислите скорость.")
        #expect(try request.prompt().contains("Вычислите скорость."))
        let lesson = ExamLesson(topic: request.topic, kind: request.kind, content: "Урок")
        #expect(lesson.title == "Урок по заданию")
    }

    @Test func emptyLessonRequestIsRejectedBeforeCallingProvider() async {
        let client = ExamAI(openAIModel: "", apiKey: "")
        do {
            _ = try await client.lesson(exam: "Математика", topic: " \n", kind: "")
            Issue.record("Expected validation error")
        } catch let error as ExamError {
            guard case .server(let message) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(message.contains("тему"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
