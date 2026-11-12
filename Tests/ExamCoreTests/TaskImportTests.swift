import AppKit
import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import ExamCore

struct TaskImportTests {
    @Test func importSolvesRecognizedTasksAndKeepsTheFileKey() throws {
        let tasks = try TaskImport.tasks(in: """
        1. Вычислите: (2 + 3) × 4
        2. Решите уравнение: 2x + 3 = 7
        3. Вычислите: 2 + 2
        Ответ: 4
        4. Объясните причины французской революции.
        """, selecting: [1, 2, 3, 4], topic: "Пробник")
        #expect(tasks.map(\.answer) == ["20", "2", "4", ""])
        #expect(tasks.map(\.answerOrigin) == [.localSolution, .localSolution, nil, nil])
        #expect(!tasks[0].solution.isEmpty)
        #expect(tasks[0].grade(response: "40/2") == .correct)
        #expect(tasks[0].grade(response: "19,9") == .incorrect)
    }

    @Test func parsesSelectedNumbersAndKeepsTheRequestedOrder() throws {
        let selection = try TaskImport.selectedNumbers("3, 1, 6–8, 7")
        #expect(selection == [3, 1, 6, 7, 8])
    }

    @Test(arguments: ["", "1,,3", "0", "7–6", "1–99999999", "abc"])
    func rejectsInvalidNumberSelections(input: String) {
        #expect(throws: TaskImportError.self) {
            try TaskImport.selectedNumbers(input)
        }
    }

    @Test func importsMultilinePromptsAndLabeledAnswers() throws {
        let document = """
        Тренировочный вариант
        Задание №1
        Найдите площадь треугольника.
        Высота равна 4.
        Ответ: 12,5
        Решение: Используем формулу площади.
        3) Найдите значение x. Ответ: 2
        6. Найдите угол.
        """
        let tasks = try TaskImport.tasks(in: document, selecting: [6, 1, 3], topic: "Геометрия")
        #expect(tasks.map(\.kind) == ["№6", "№1", "№3"])
        #expect(tasks.map(\.topic) == ["Геометрия", "Геометрия", "Геометрия"])
        #expect(tasks.map(\.prompt) == ["Найдите угол.", "Найдите площадь треугольника.\nВысота равна 4.", "Найдите значение x."])
        #expect(tasks.map(\.answer) == ["", "12,5", "2"])
        #expect(tasks.map(\.solution) == ["", "Используем формулу площади.", ""])
    }

    @Test func usesSeparateAnswerKeyAndPreservesDecimalNotation() throws {
        let document = """
        1. Найдите значение.
        2. Вычислите произведение.
        3. Сложите числа.
        Ответы
        1. 3,5
        2    9
        3:
        14
        """
        let tasks = try TaskImport.tasks(in: document, selecting: [1, 2, 3], topic: "")
        #expect(tasks.map(\.answer) == ["3,5", "9", "14"])
        #expect(tasks.first?.prompt == "Найдите значение.")
    }

    @Test func acceptsCatalogueNumbersInParenthesesAndLocalNumbers() throws {
        let text = """
        № 125
        Определите объём памяти.
        54) Вычислите длину пароля.
        (№ 2066) Сколько байт требуется?
        """
        let tasks = try TaskImport.tasks(in: text, selecting: [125, 54, 2066], topic: "Информатика")
        #expect(tasks.map(\.prompt) == ["Определите объём памяти.", "Вычислите длину пароля.", "Сколько байт требуется?"])
    }

    @Test func usesAnswerKeyAfterBlankAnswerLine() throws {
        let text = """
        2. Заполните таблицу истинности.
        Ответ: ___________________________.
        Задание выполняется с использованием прилагаемого файла.
        3. Обработайте таблицу.
        Система оценивания экзаменационной работы по информатике
        Номер задания Правильный ответ
        2 yxzw
        3 1630
        """
        let tasks = try TaskImport.tasks(in: text, selecting: [2, 3], topic: "Информатика")
        #expect(tasks.map(\.answer) == ["yxzw", "1630"])
    }

    @Test func reportsEveryMissingOrRepeatedSelectedTaskNumber() {
        let document = """
        №1 Первое условие
        №1 Другое условие
        №4 Четвёртое условие
        """
        #expect(throws: TaskImportError.unresolved(missing: [3, 2], repeated: [1])) {
            try TaskImport.tasks(in: document, selecting: [3, 1, 2, 4], topic: "Алгебра")
        }
    }

    @Test func preservesDecimalsAndNumberedSubpartsInsideExplicitlyLabeledTasks() throws {
        let document = """
        Задание 2. Выберите все верные утверждения.
        1) Первое утверждение.
        2) Второе утверждение.
        Задание 3. Запишите значение.
        1.25 — начальное приближение.
        """
        let tasks = try TaskImport.tasks(in: document, selecting: [2, 3], topic: "Алгебра")
        #expect(tasks[0].prompt == "Выберите все верные утверждения.\n1) Первое утверждение.\n2) Второе утверждение.")
        #expect(tasks[1].prompt == "Запишите значение.\n1.25 — начальное приближение.")
    }

    @Test func readsATextFileThroughTheImportEntryPoint() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try "1. Найдите сумму.\nОтвет: 3".write(to: file, atomically: true, encoding: .utf8)

        let document = try TaskImport.read(file)
        let tasks = try TaskImport.tasks(in: document, selecting: [1], topic: "Алгебра")
        #expect(tasks.first?.prompt == "Найдите сумму.")
        #expect(tasks.first?.answer == "3")
    }
}

extension TaskImportTests {
    @Test func preservesSignedAnswersInASeparateKey() throws {
        let document = """
        1. Запишите отрицательное число.
        Ответы
        1 -5
        """
        let tasks = try TaskImport.tasks(in: document, selecting: [1], topic: "")
        #expect(tasks.first?.answer == "-5")
    }

    @Test func doesNotSelectAnAnswerFromConflictingKeys() {
        let document = """
        1. Найдите значение.
        Ответы:
        1. 5
        1. 7
        """
        #expect(throws: TaskImportError.unresolved(missing: [], repeated: [1])) {
            try TaskImport.tasks(in: document, selecting: [1], topic: "")
        }
    }
}

extension TaskImportTests {
    @Test func readsTextPDFAndScopesRepeatedTaskNumbersToSelectedPages() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        let bytes = try makePDF(pages: [["7. Найдите сумму.", "Ответ: 20"], ["7. Найдите разность.", "Ответ: 10"]])
        try bytes.write(to: file)

        let document = try TaskImport.readDocument(file)
        #expect(document.pageCount == 2)
        let allPages = try document.text()
        #expect(throws: TaskImportError.unresolved(missing: [], repeated: [7])) {
            try TaskImport.tasks(in: allPages, selecting: [7], topic: "Математика")
        }
        let page = try document.text(on: [2])
        let tasks = try TaskImport.tasks(in: page, selecting: [7], topic: "Математика")
        #expect(tasks.first?.prompt == "Найдите разность.")
        #expect(tasks.first?.answer == "10")
        #expect(throws: TaskImportError.unavailablePages(pageCount: 2)) {
            try document.text(on: [3])
        }
    }

    @Test func readsADOCXFileThroughTheImportEntryPoint() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).docx")
        defer { try? FileManager.default.removeItem(at: file) }
        let sample = NSAttributedString(string: "1. Найдите сумму.\nОтвет: 3")
        let data = try sample.data(from: NSRange(location: 0, length: sample.length),
                                   documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        try data.write(to: file)

        let document = try TaskImport.read(file)
        let tasks = try TaskImport.tasks(in: document, selecting: [1], topic: "")
        #expect(tasks.first?.prompt == "Найдите сумму.")
        #expect(tasks.first?.answer == "3")
    }

    private func makePDF(pages: [[String]]) throws -> Data {
        let bytes = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: bytes as CFMutableData))
        var bounds = CGRect(x: 0, y: 0, width: 650, height: 240)
        let pdf = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 33, nil)

        for lines in pages {
            pdf.beginPDFPage(nil)
            for (index, text) in lines.enumerated() {
                let sample = NSAttributedString(string: text, attributes: [.font: font])
                pdf.textPosition = CGPoint(x: 45, y: 175 - index * 60)
                CTLineDraw(CTLineCreateWithAttributedString(sample), pdf)
            }
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return bytes as Data
    }
}

extension TaskImportTests {
    @Test func recognizesBareNumbersInScopedPDFTextWithoutTreatingFootersAsTasks() throws {
        let document = """
        1 1 Module
        1
        9
        Text 1
        Read both passages.
        10
        Which choice best supports the conclusion?
        A) The first choice.
        B) The second choice.
        Unauthorized copying or reuse of any part of this page is illegal.
        5
        CONTINUE
        """
        let tasks = try TaskImport.tasks(in: document, selecting: [9, 10], topic: "", allowBareNumbers: true)
        #expect(tasks.map(\.prompt) == [
            "Text 1\nRead both passages.",
            "Which choice best supports the conclusion?\nA) The first choice.\nB) The second choice."
        ])
        #expect(throws: TaskImportError.unresolved(missing: [1, 5], repeated: [])) {
            try TaskImport.tasks(in: document, selecting: [1, 5], topic: "", allowBareNumbers: true)
        }
    }
}
