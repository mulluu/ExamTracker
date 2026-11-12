import Testing
@testable import ExamCore

struct LocalPracticeSolverTests {
    @Test(arguments: [
        ("Вычислите: 2 + 3 × (4 − 1).", "11"),
        ("Calculate 0.1 + 0.2.", "0,3"),
        ("Вычислите 1,25 × 4.", "5"),
        ("Вычислите 1 / 3 + 1 / 6.", "0,5"),
        ("Evaluate 2 / 7.", "2/7"),
        ("Вычислите −2^2 + 2^3^2 = ?", "508"),
        ("Найдите сумму чисел 12 и 7.", "19"),
        ("3/4 = ?", "0,75"),
        ("3 + 4", "7")
    ])
    func solvesExplicitArithmeticExactly(prompt: String, expected: String) throws {
        let solved = try #require(LocalPracticeSolver.solve(PracticeTask(prompt: prompt)))
        #expect(solved.answer == expected)
        #expect(solved.explanation.contains(expected))
    }

    @Test(arguments: [
        ("Решите уравнение: 3(х − 2) = 9.", "5"),
        ("Solve for x: 3x + 2 = x - 4.", "-3"),
        ("Решите уравнение 3х = 1.", "1/3"),
        ("(x + 1) / 2 = 0", "-1")
    ])
    func solvesOnlyUniqueLinearRoots(prompt: String, expected: String) throws {
        let solved = try #require(LocalPracticeSolver.solve(PracticeTask(prompt: prompt)))
        #expect(solved.answer == expected)
        #expect(solved.explanation.contains("x = \(expected)"))
    }

    @Test(arguments: [
        ("Найдите площадь треугольника с основанием 12 и высотой 7, опущенной на это основание.", "42"),
        ("Найдите площадь прямоугольника со сторонами 6 и 4.", "24"),
        ("Find the area of a rectangle with length 5 cm and width 3 cm.", "15"),
        ("Find the area of a square with side length 2.5.", "6,25"),
        ("Найдите площадь круга радиуса 3.", "9π")
    ])
    func calculatesAreasFromExplicitDimensions(prompt: String, expected: String) throws {
        let solved = try #require(LocalPracticeSolver.solve(PracticeTask(prompt: prompt)))
        #expect(solved.answer == expected)
        #expect(solved.explanation.contains(expected))
    }

    @Test func leavesAnExistingKeyForReviewEvenWhenItDisagreesWithTheCalculation() {
        #expect(LocalPracticeSolver.solve(PracticeTask(prompt: "Вычислите 2 + 2.", answer: "5")) == nil)
    }

    @Test(arguments: [
        "Вычислите 1 / 0.", "Вычислите 0^0.", "Вычислите 1/2/3 без округления.",
        "Calculate 1,234 + 1.", "3/4", "Вычислите 1/2(3+4).", "Решите уравнение x² = 4.",
        "x = x", "x = x + 1", "Решите уравнение 1/x = 2.", "Решите 2x + y = 4.",
        "Решите уравнение 2x = 4 и обоснуйте ответ.", "Используя рисунок, вычислите 2 + 2.",
        "Найдите площадь треугольника со сторонами 12 и 7.", "Find the area of a rectangle with length 5 cm and width 3 m.",
        "Найдите площадь прямоугольника со сторонами 6 и -4.", "Найдите площадь окружности радиуса 3 и округлите.",
        "Вычислите 900000000000000000 × 900000000000000000."
    ])
    func leavesAmbiguousOrUnsupportedTasksUnsolved(prompt: String) {
        #expect(LocalPracticeSolver.solve(PracticeTask(prompt: prompt)) == nil)
    }

    @Test func comparesExactNumericAnswersAcrossDifferentNotations() {
        #expect(LocalPracticeSolver.compareNumericAnswer(" −2 / 4 ", to: "-0,50") == true)
        #expect(LocalPracticeSolver.compareNumericAnswer("2/6", to: "1/3") == true)
        #expect(LocalPracticeSolver.compareNumericAnswer("0.333", to: "1/3") == false)
        #expect(LocalPracticeSolver.compareNumericAnswer("0,5+0", to: "1/2") == nil)
        #expect(LocalPracticeSolver.compareNumericAnswer("1/0", to: "1/2") == nil)
        #expect(LocalPracticeSolver.compareNumericAnswer("9π", to: "9π") == nil)
    }
}
