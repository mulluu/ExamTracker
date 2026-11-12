import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ExamCore

struct TaskSourceImportTests {
    @Test func importsGeometryWithFigureToLeftOfText() throws {
        let url = try makePDF(width: 600, text: [
            ("01. Планиметрия", 230, 760), ("1. Найдите угол C.", 245, 680),
            ("2. Найдите площадь.", 245, 470)
        ], graphic: CGRect(x: 60, y: 545, width: 140, height: 120))
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = try TaskImport.readDocument(url)
        let task = try #require(try doc.tasks(selecting: [1], topic: "").first)
        #expect(task.prompt == "Найдите угол C.")
        #expect(task.sourceInQuestion == true)
        let fragments = try #require(task.sourceFragments)
        #expect(fragments.count == 1)
        #expect(containsBlue(fragments[0]))
    }

    @Test func buildsGraphOnPDFImportAndKeepsTheOriginalFragment() throws {
        let url = try makePDF(width: 600, text: [
            ("1. Дана функция y = 2x + 1.", 50, 700),
            ("Найдите её значение при x = 2.", 50, 665),
            ("2. Найдите угол.", 50, 470)
        ], graphic: CGRect(x: 65, y: 510, width: 130, height: 100))
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try TaskImport.readDocument(url)
        let task = try #require(try document.tasks(selecting: [1], topic: "Функции").first)
        let diagram = try StudyDiagram.parse(#require(task.diagramDescription))
        #expect(task.diagramInQuestion == true)
        #expect(task.sourceFragments?.isEmpty == false)
        #expect(diagram.paths.flatMap(\.points).contains { $0.x == 2 && $0.y == 5 })
    }

    @Test func importsTwoColumnInformaticsWithoutMergingQuestions() throws {
        let url = try makePDF(width: 1000, text: [
            ("1", 40, 700), ("2", 540, 700),
            ("На рисунке изображена схема.", 70, 700), ("Заполните таблицу истинности.", 570, 700),
            ("Найдите длину пути.", 70, 420), ("Запишите переменные.", 570, 405)
        ], graphic: CGRect(x: 80, y: 480, width: 220, height: 170))
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = try TaskImport.readDocument(url)
        let tasks = try doc.tasks(selecting: [1, 2], topic: "")
        #expect(tasks[0].prompt.contains("длину пути"))
        #expect(!tasks[0].prompt.contains("таблицу истинности"))
        #expect(tasks[1].prompt.contains("переменные"))
        #expect(containsBlue(try #require(tasks[0].sourceFragments?.first)))
        #expect(!containsBlue(try #require(tasks[1].sourceFragments?.first)))
    }

    @Test func attachesSharedReadingPassageToEveryQuestion() throws {
        let url = try makePDF(width: 600, text: [
            ("Read a notice.", 50, 700), ("The library closes at noon.", 50, 650),
            ("11. Who wrote the notice?", 50, 490), ("12. When does the library close?", 50, 370)
        ], graphic: CGRect(x: 80, y: 540, width: 100, height: 60))
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = try TaskImport.readDocument(url)
        let tasks = try doc.tasks(selecting: [11, 12], topic: "Reading")
        #expect(tasks.allSatisfy { $0.prompt.contains("The library closes at noon.") })
        #expect(tasks.allSatisfy { $0.sourceFragments?.count == 2 })
        for task in tasks {
            #expect(containsBlue(try #require(task.sourceFragments?.first)))
        }
    }

    @Test func importsUnnumberedReadingPageAsSource() throws {
        let url = try makePDF(width: 600, text: [("Read the passage and match the headings.", 50, 700)],
                              graphic: CGRect(x: 90, y: 420, width: 130, height: 90))
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = try TaskImport.readDocument(url)
        let pages = try doc.pageTasks(topic: "Reading")
        #expect(pages.first?.kind == "Страница 1")
        #expect(pages.first?.sourceInQuestion == true)
        #expect(containsBlue(try #require(pages.first?.sourceFragments?.first)))
    }

    @Test func showsTextDocumentAttachmentsThatBelongToTheQuestion() throws {
        let document = TaskImportDocument(source: .text("1. What does the diagram show?\n\u{FFFC}", attachments: [1: [Data([1])]]))
        let task = try #require(try document.tasks(topic: "Reading").first)
        #expect(task.sourceFragments == [Data([1])])
        #expect(task.sourceInQuestion == true)
    }

    @Test func retainsTheQuestionImageWhenTheSameDocumentHasASolutionImage() throws {
        let document = TaskImportDocument(
            source: .text("1. Use the diagram.\n\u{FFFC}\nSolution: use a line.\n\u{FFFC}",
                          attachments: [1: [Data([1])], 3: [Data([2])]]))
        let task = try #require(try document.tasks(topic: "Math").first)
        #expect(task.showsSourceInQuestion)
        #expect(task.sourceFragments == [Data([1])])
        #expect(task.reviewFragments == [Data([2])])
    }

    @Test(arguments: ["Answer Key", "Reading Sample (Answers)", "Система оценивания экзаменационной работы"])
    func reservesAnswerPagesForReview(heading: String) throws {
        let url = try makePDF(width: 600, text: [(heading, 50, 700), ("1. B", 50, 620)],
                              graphic: CGRect(x: 90, y: 420, width: 130, height: 90))
        defer { try? FileManager.default.removeItem(at: url) }
        let task = try #require(try TaskImport.readDocument(url).pageTasks(topic: "Reading").first)
        #expect(!task.showsSourceInQuestion)
        #expect(task.sourceFragments?.count == 1)
    }

    @Test func showsAttachedIllustrationsFromOlderVersionsDuringPractice() {
        var task = PracticeTask(prompt: "Study the figure.")
        task.illustration = Data([1])
        task.generatedIllustration = true
        task.illustrationInQuestion = false
        #expect(task.showsIllustrationInQuestion)
    }

    @Test func keepsImagesWithInlineAnswerForReview() throws {
        let url = try makePDF(width: 600, text: [("1. Найдите угол C. Ответ: 42", 50, 700)],
                              graphic: CGRect(x: 90, y: 420, width: 130, height: 90))
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = try TaskImport.readDocument(url)
        let task = try #require(try doc.tasks(selecting: [1], topic: "Геометрия").first)
        #expect(task.prompt == "Найдите угол C.")
        #expect(task.answer == "42")
        #expect(task.sourceFragments?.isEmpty == false)
        #expect(task.sourceInQuestion == false)
        #expect(try doc.pageTasks(topic: "Геометрия").first?.sourceInQuestion != true)
    }

    @Test func recognizesPNGAsImageByItsContents() throws {
        let url = try makeFormulaPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try TaskImport.readDocument(url)
        #expect(document.hasPageImages)
        #expect(try document.pageTasks(topic: "Математика").first?.sourceFragments?.count == 1)
        #expect(try document.pageTasks(topic: "Математика").first?.sourceInQuestion == true)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["EXAMTRACKER_TEST_VISION"] == "1",
                   "Requires an interactive macOS environment with Vision OCR available"))
    func buildsGraphFromFormulaRecognizedInImage() throws {
        let url = try makeFormulaPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        let recognized = try TaskImport.read(url)
        let graph = try StudyDiagram.parse(recognized)
        #expect(graph.kind == .graph)
        #expect(graph.paths.flatMap(\.points).contains { $0.x == 0 && $0.y == 2 })
    }

    private func makeFormulaPNG() throws -> URL {
        let context = try #require(CGContext(data: nil, width: 1000, height: 250, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 250))
        context.setFillColor(gray: 0, alpha: 1)
        context.textPosition = CGPoint(x: 95, y: 85)
        let font = CTFontCreateWithName("Helvetica" as CFString, 76, nil)
        let text = NSAttributedString(string: "y = x + 2", attributes: [.font: font])
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).png")
        let output = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(output, image, nil)
        try #require(CGImageDestinationFinalize(output))

        return url
    }

    private func makePDF(width: Double, text: [(String, Double, Double)], graphic: CGRect) throws -> URL {
        let bytes = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: bytes as CFMutableData))
        var bounds = CGRect(x: 0, y: 0, width: width, height: 800)
        let pdf = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        pdf.beginPDFPage(nil)
        pdf.setFillColor(red: 0.1, green: 0.35, blue: 0.9, alpha: 1)
        pdf.fill(graphic)
        pdf.setFillColor(gray: 0, alpha: 1)
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        for (string, x, y) in text {
            pdf.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font])), pdf)
        }
        pdf.endPDFPage()
        pdf.closePDF()
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).pdf")
        try (bytes as Data).write(to: url)
        return url
    }

    private func containsBlue(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let bitmap = CGContext(data: nil, width: 96, height: 96, bitsPerComponent: 8,
                                     bytesPerRow: 384, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let pixels = bitmap.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: 96, height: 96))
        return stride(from: 0, to: 96 * 384, by: 4).contains { pixels[$0] < 120 && pixels[$0 + 2] > 170 }
    }
}
