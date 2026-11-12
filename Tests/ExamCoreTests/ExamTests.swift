import Foundation
import Testing
@testable import ExamCore

struct ExamTests {
    @Test func testTopicAccuracyUsesOnlyMarkedTasksAndWeightsPoints() throws {
        let attempt = try Attempt(title: "Пробник", scores: [
            TaskScore(topic: "Геометрия", earned: 0, maximum: 1),
            TaskScore(topic: "геометрия ", earned: 2, maximum: 3),
            TaskScore(topic: "Алгебра", earned: nil, maximum: 1)
        ])
        let exam = Exam(name: "Математика", attempts: [
            attempt, try Attempt(title: "ЕГЭ", earned: 70, maximum: 100)
        ])
        let topic = try #require(exam.topicStats.first)
        #expect(exam.topicStats.count == 1)
        #expect(topic.ratio == 0.5)
        #expect(topic.count == 2)
        #expect(attempt.maximum == 4)
        #expect(exam.examAttempts.count == 1)
    }

    @Test func ungradedPracticeRetainsResponsesWithoutAffectingStatistics() throws {
        let ungraded = TaskScore(topic: "Алгебра", earned: nil, maximum: 2, response: "Моё решение")
        let onlyUngraded = try Attempt(title: "Без ключа", scores: [ungraded])
        let mixed = try Attempt(title: "Смешанный набор", scores: [
            ungraded, TaskScore(topic: "Геометрия", earned: 0, maximum: 1)
        ])
        let data = try JSONEncoder().encode([onlyUngraded, mixed])
        let attempts = try JSONDecoder().decode([Attempt].self, from: data)
        #expect(attempts[0].scores.first?.response == "Моё решение")
        #expect(attempts[0].maximum == 0)
        #expect(attempts[1].maximum == 1)
        #expect(attempts[1].scores.count == 2)
        let exam = Exam(name: "Математика", attempts: attempts)
        #expect(exam.topicStats.map(\.name) == ["Геометрия"])
        #expect(exam.examAttempts.isEmpty)
    }

    @Test func testTopicRatioDoesNotOverflowAcrossAttempts() throws {
        let first = try Attempt(title: "Первый", scores: [
            TaskScore(topic: "Математика", earned: 1e308, maximum: 1e308)
        ])
        let second = try Attempt(title: "Второй", scores: [
            TaskScore(topic: "Математика", earned: 0, maximum: 1e308)
        ])
        let stats = Exam(name: "Экзамен", attempts: [first, second]).topicStats
        #expect(stats.first?.ratio == 0.5)
    }

    @Test func testInvalidScoreCannotBeSaved() {
        #expect(throws: ExamError.self) { try Attempt(title: "Пробник", earned: 101, maximum: 100) }
        #expect(throws: ExamError.self) { try Attempt(title: "Пробник", scores: [
            TaskScore(topic: "Геометрия", earned: 2, maximum: 1)
        ]) }
    }

    @Test func testPersistenceRestoresExamAndPractice() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ExamStorage(url: directory.appending(path: "data.json"))
        var task = PracticeTask(topic: "Геометрия", kind: "№1", prompt: "Найдите площадь", answer: "12", solution: "3 × 4", maximum: 1)
        task.diagramDescription = "Прямоугольник: ширина 4, высота 3"
        let attempt = try Attempt(title: "Тренировка", scores: [
            TaskScore(topic: task.topic, earned: 0, maximum: task.maximum, question: task.prompt,
                      response: "10", expectedAnswer: task.answer)
        ])
        let exam = Exam(name: "Математика", attempts: [attempt],
                        practice: [PracticeSet(title: "Стереометрия", tasks: [task])])
        try storage.save([exam])
        let loaded = try #require(storage.load().first)
        #expect(loaded.id == exam.id)
        #expect(loaded.practice.first?.tasks.first?.answer == "12")
        #expect(loaded.practice.first?.tasks.first?.diagramDescription == task.diagramDescription)
        #expect(loaded.attempts.first?.scores.first?.question == "Найдите площадь")
        #expect(loaded.attempts.first?.scores.first?.response == "10")
        #expect(loaded.attempts.first?.scores.first?.expectedAnswer == "12")
    }

    @Test func retainsPrimaryOnlyAndDualScaleResultsIndependently() throws {
        let primary = try ExamScore(earned: 22, maximum: 32)
        let primaryOnly = try Attempt(title: "Первый", primaryScore: primary)
        let both = try Attempt(title: "Второй", earned: 78, maximum: 100, primaryScore: primary)
        let old = try Attempt(title: "Старый", earned: 68, maximum: 100)
        let data = try JSONEncoder().encode([primaryOnly, both, old])
        let decoded = try JSONDecoder().decode([Attempt].self, from: data)
        #expect(decoded.filter(\.hasFinalScore).map(\.earned) == [78, 68])
        #expect(decoded.compactMap { $0.primaryScore?.earned } == [22, 22])
        #expect(decoded[1].primaryScore?.maximum == 32)
    }

    @Test func manualTaskMayHaveNoAnswerWhileGeneratedTasksRequireOne() {
        let task = PracticeTask(topic: "Алгебра", prompt: "Решите уравнение.", solution: "Ход решения")
        #expect(task.isValid)
        #expect(throws: ExamError.self) { try PracticeSet.validateGenerated([task], count: 1) }
    }

    @Test func testGeneratedTasksRejectIncompleteAndDuplicateQuestions() throws {
        let task = PracticeTask(topic: "Алгебра", kind: "№6", prompt: "Решите x = 2", answer: "2", solution: "x уже выражен", maximum: 1)
        #expect(throws: ExamError.self) { try PracticeSet.validateGenerated([task, task], count: 2) }
        #expect(throws: ExamError.self) { try PracticeSet.validateGenerated([task], count: 2) }
        try PracticeSet.validateGenerated([task], count: 1)
    }
}
