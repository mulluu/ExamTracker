import Testing
@testable import ExamCore

struct PracticeGradingTests {
    @Test func unansweredTakesPrecedenceOverTheMissingKey() {
        #expect(PracticeTask().grade(response: " \n\t\u{00A0} ") == .unanswered)
        #expect(PracticeTask(answer: "42").grade(response: " ") == .unanswered)
    }

    @Test(arguments: ["", "_____.", "…", "—", "Нет ответа", "не указано", "См. решение", "TBD"])
    func missingAndPlaceholderKeysRequireManualGrading(key: String) {
        #expect(PracticeTask(answer: key).grade(response: "42") == .manual)
    }

    @Test func exactShortTextAllowsCaseCanonicalUnicodeAndExtraSpaces() {
        let task = PracticeTask(answer: "Синий кит")
        #expect(task.grade(response: "  СИНИИ\u{0306}\u{00A0}  кит  ") == .correct)
        #expect(task.grade(response: "Синий кИT") == .incorrect) // The last letter is Latin.
        #expect(task.grade(response: "синии кит") == .incorrect)
        #expect(PracticeTask(answer: "всё").grade(response: "все") == .incorrect)
    }

    @Test func decimalNotationPreservesSignAndExactDigits() {
        let task = PracticeTask(answer: "−0,375")
        #expect(task.grade(response: "-0.375") == .correct)
        #expect(task.grade(response: "0.375") == .incorrect)
        #expect(task.grade(response: "-0.38") == .incorrect)
        #expect(PracticeTask(answer: "12345678901234567890,1").grade(response: "12345678901234567890.2") == .incorrect)
    }

    @Test func codesRetainLeadingZerosAndSequenceOrder() {
        #expect(PracticeTask(answer: "0012").grade(response: "12") == .incorrect)
        #expect(PracticeTask(answer: "0012").grade(response: " 0012 ") == .correct)
        #expect(PracticeTask(answer: "132").grade(response: "123") == .incorrect)
        #expect(PracticeTask(answer: "1 2").grade(response: "1\t 2") == .correct)
        #expect(PracticeTask(answer: "1 2").grade(response: "12") == .incorrect)
        let sequence = PracticeTask(prompt: "Запишите числа в указанном порядке.", answer: "1,2")
        #expect(sequence.grade(response: "1, 2") == .correct)
        #expect(sequence.grade(response: "1.2") == .incorrect)
        #expect(sequence.grade(response: "2,1") == .incorrect)
    }

    @Test func fractionsAllowSafeTypographicNormalization() {
        let task = PracticeTask(prompt: "Запишите дробь.", answer: "−1/2")
        #expect(task.grade(response: " -1 / 2 ") == .correct)
        #expect(task.grade(response: "1/2") == .incorrect)
        #expect(PracticeTask(answer: "1/0").grade(response: "1/0") == .manual)
        #expect(PracticeTask(answer: "2/03").grade(response: "2/3") == .manual)
    }

    @Test func openPromptsAndRubricsRequireManualGradingEvenWithAnExactKey() {
        let prompt = PracticeTask(prompt: "Найдите результат и обоснуйте ответ.", answer: "42")
        let kind = PracticeTask(kind: "Развернутый ответ", answer: "42")
        let rubric = PracticeTask(answer: "42", solution: "Критерии оценивания: 1 балл за вычисление, 1 балл за обоснование.")
        #expect(prompt.grade(response: "42") == .manual)
        #expect(kind.grade(response: "42") == .manual)
        #expect(rubric.grade(response: "42") == .manual)
        #expect(PracticeTask(answer: "42", solution: "Умножим 6 на 7.", maximum: 2).grade(response: "42") == .correct)
    }

    @Test(arguments: ["A/B", "12 или 21", "1,2,3", "2 + 3", "≈0,3", "1\n2",
                      "Верное решение содержит необходимые вычисления."])
    func ambiguousKeysRequireManualGradingEvenWhenRepeatedVerbatim(key: String) {
        #expect(PracticeTask(answer: key).grade(response: key) == .manual)
    }

    @Test func piAnswersGradeVerbatimAndLeaveOtherFormsForManualReview() throws {
        let task = try #require(Exam.starter.practice.first?.tasks.last)
        #expect(task.grade(response: " 12 π ") == .correct)
        #expect(task.grade(response: "π × 12") == .manual)
        #expect(task.grade(response: "37,7") == .manual)
        #expect(task.grade(response: "13π") == .manual)
        #expect(task.grade(response: "12Π") == .manual)
        #expect(PracticeTask(answer: "−π").grade(response: "-π") == .correct)
    }

    @Test func expressionsAndApproximationsInTheResponseRequireManualGrading() {
        #expect(PracticeTask(answer: "42").grade(response: "6 × 7") == .manual)
        #expect(PracticeTask(answer: "0,33").grade(response: "≈0,33") == .manual)
        #expect(PracticeTask(answer: "42").grade(response: "41") == .incorrect)
    }
}
