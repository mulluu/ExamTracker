import Foundation
import Testing
@testable import ExamCore

struct StudyDiagramTests {
    @Test(arguments: ["Выполните построение графика функции y = 2x + 1.",
                      "Построй график функции y = 2x + 1.",
                      "Construct the graph of the function y = 2x + 1."])
    func keepsAlternativeConstructionInstructionsInReview(_ condition: String) throws {
        let diagram = try #require(ProblemDiagram.fromCondition(condition))
        #expect(!diagram.showsDuringPractice)
    }

    @Test func plotsAnExplicitFormulaWithSuperscriptsAndImplicitMultiplication() throws {
        let diagram = try StudyDiagram.parse("Постройте график функции у = х² − 2х + 1.")
        #expect(diagram.kind == .graph)
        let samples = diagram.paths.flatMap(\.points)
        let atZero = try #require(samples.first { $0.x == 0 })
        let atOne = try #require(samples.first { $0.x == 1 })
        #expect(atZero.y == 1)
        #expect(atOne.y == 0)
        #expect(diagram.bounds.minX < diagram.bounds.maxX)
        #expect(diagram.bounds.minY < diagram.bounds.maxY)
    }

    @Test func powersAssociateToTheRightAndBindBeforeUnaryMinus() throws {
        let diagram = try StudyDiagram.parse("y = -x^2 + 2^3^2")
        let atTwo = try #require(diagram.paths.flatMap(\.points).first { $0.x == 2 })
        #expect(atTwo.y == 508)
    }

    @Test func recognizesExplicitFunctionsAndDecimalCommas() throws {
        let diagram = try StudyDiagram.parse("y = sqrt(x) + sin(0) + cos(0) + 0,5")
        let samples = diagram.paths.flatMap(\.points)
        let atFour = try #require(samples.first { $0.x == 4 })
        #expect(atFour.y == 3.5)
        #expect(samples.allSatisfy { $0.x >= 0 })
    }

    @Test func doesNotJoinAcrossASingularityBetweenSamplePoints() throws {
        let diagram = try StudyDiagram.parse("y = 1/(x - 0.023)^2")
        let pole = 0.023
        #expect(diagram.paths.contains { $0.points.allSatisfy { $0.x < pole } })
        #expect(diagram.paths.contains { $0.points.allSatisfy { $0.x > pole } })
        #expect(diagram.paths.allSatisfy { path in
            path.points.allSatisfy { $0.x < pole } || path.points.allSatisfy { $0.x > pole }
        })
    }

    @Test func adaptiveSamplingPreservesOscillationBetweenInitialSamples() throws {
        let diagram = try StudyDiagram.parse("y = sin(40πx)")
        let values = diagram.paths.flatMap(\.points).map(\.y)
        #expect(values.contains { $0 > 0.99 })
        #expect(values.contains { $0 < -0.99 })
    }

    @Test func parsesCoordinateTriangleAndUsesTheDeclaredVertexOrder() throws {
        let diagram = try StudyDiagram.parse("Дан треугольник ABC с вершинами C(0; 3), A(0; 0), B(4; 0).")
        #expect(diagram.kind == .geometry)
        let triangle = try #require(diagram.paths.first)
        #expect(triangle.isClosed)
        #expect(triangle.points.map(\.label) == ["A", "B", "C"])
        #expect(triangle.points.map(\.x) == [0, 4, 0])
        #expect(triangle.points.map(\.y) == [0, 0, 3])
        #expect(diagram.points.count == 3)
    }

    @Test func parsesSegmentsPolygonsAndNamedCircleCenters() throws {
        let diagram = try StudyDiagram.parse("""
        Точки A(−1,5; 0), B(2; 0), C(2; 2), D(-1.5, 2).
        Отрезок AC. Многоугольник ABCD.
        Окружность с центром O(0; 0) и радиусом 1,5.
        """)
        #expect(diagram.paths.count == 2)
        #expect(diagram.paths[0].points.map(\.label) == ["A", "C"])
        #expect(!diagram.paths[0].isClosed)
        #expect(diagram.paths[1].isClosed)
        let circle = try #require(diagram.circles.first)
        #expect(circle.center.label == "O")
        #expect(circle.radius == 1.5)
        #expect(diagram.points.contains { $0.label == "O" })
        #expect(diagram.bounds.minY < -1.5)
    }

    @Test func dimensionedRectanglePreservesItsSideLengthsAndArea() throws {
        let diagram = try StudyDiagram.parse("Прямоугольник: ширина 4, высота 3")
        let path = try #require(diagram.paths.first)
        #expect(path.isClosed)
        #expect(path.points.map(\.x) == [0, 4, 4, 0])
        #expect(path.points.map(\.y) == [0, 0, 3, 3])
        #expect((path.points[1].x - path.points[0].x) * (path.points[2].y - path.points[1].y) == 12)
    }

    @Test(arguments: ["Найдите x, при y = 3.", "Даны y = x и y = -x.",
                      "Дана функция y = x² при x ≥ 0.", "Найдите x. Ответ: y = x.",
                      "Дан треугольник с основанием 4 и высотой 3.",
                      "Найдите площадь прямоугольника со сторонами 4 см и 3 м."])
    func skipsIncompleteOrAmbiguousProblemData(condition: String) {
        #expect(ProblemDiagram.fromCondition(condition) == nil)
    }

    @Test func buildsIsoscelesTriangleUsingTheAngleInTheCondition() throws {
        let condition = """
        В треугольнике АВС угол А равен 53°, сто-
        роны AC и BC равны. Найдите угол C.
        """
        let result = try #require(ProblemDiagram.fromCondition(condition))
        let triangle = try #require(result.drawing.paths.first { $0.isClosed })
        #expect(triangle.points.map(\.label) == ["A", "B", "C"])
        let a = triangle.points[0], b = triangle.points[1], c = triangle.points[2]
        #expect(abs(hypot(c.x - a.x, c.y - a.y) - hypot(c.x - b.x, c.y - b.y)) < 1e-7)
        #expect(abs(atan2(c.y - a.y, c.x - a.x) * 180 / .pi - 53) < 1e-6)
        #expect(result.showsDuringPractice)
    }

    @Test func buildsExternalRayFromAnExplicitlyNamedExteriorAngle() throws {
        let result = try #require(ProblemDiagram.fromCondition(
            "В треугольнике ABC стороны AC и BC равны, угол C равен 154°, угол CBD внешний. Найдите угол CBD."
        ))
        let points = Dictionary(uniqueKeysWithValues: result.drawing.points.compactMap { point in
            point.label.map { ($0, point) }
        })
        let a = try #require(points["A"]), b = try #require(points["B"]), d = try #require(points["D"])
        #expect(a.y == b.y && b.y == d.y)
        #expect(a.x < b.x && b.x < d.x)
        #expect(result.drawing.paths.contains { $0.points.map(\.label) == ["B", "D"] })
    }

    @Test func buildsMedianAndBisectorOfRightTriangleFromItsCondition() throws {
        let result = try #require(ProblemDiagram.fromCondition(
            "Острый угол B прямоугольного треугольника ABC равен 19°. Найдите угол между биссектрисой CD и медианой CM, проведёнными из вершины прямого угла C."
        ))
        let points = Dictionary(uniqueKeysWithValues: result.drawing.points.compactMap { point in
            point.label.map { ($0, point) }
        })
        let a = try #require(points["A"]), b = try #require(points["B"])
        let m = try #require(points["M"]), d = try #require(points["D"])
        #expect(abs(m.x - (a.x + b.x) / 2) < 1e-7)
        #expect(abs(m.y - (a.y + b.y) / 2) < 1e-7)
        #expect(abs(d.x - d.y) < 1e-7)
        #expect(result.drawing.paths.contains { $0.points.map(\.label) == ["C", "D"] })
        #expect(result.drawing.paths.contains { $0.points.map(\.label) == ["C", "M"] })
    }

    @Test func reconstructsTriangleFromNamedSideLengthsInProse() throws {
        let result = try #require(ProblemDiagram.fromCondition(
            "Дан треугольник ABC со сторонами BC = 4, AC = 5 и AB = 3. Найдите площадь."
        ))
        let points = try #require(result.drawing.paths.first?.points)
        #expect(points.map(\.label) == ["A", "B", "C"])
        func distance(_ a: StudyDiagram.Point, _ b: StudyDiagram.Point) -> Double {
            hypot(a.x - b.x, a.y - b.y)
        }
        #expect(abs(distance(points[0], points[1]) - 3) < 1e-7)
        #expect(abs(distance(points[1], points[2]) - 4) < 1e-7)
        #expect(abs(distance(points[0], points[2]) - 5) < 1e-7)
    }

    @Test func keepsManualOverridesAndLetsAutomaticDiagramsFollowConditions() throws {
        var task = PracticeTask(prompt: "Дана функция y = x + 1. Найдите её значение при x = 2.")
        task.updateDiagramFromCondition()
        #expect(task.diagramIsAutomatic == true)
        task.prompt = "Постройте график функции y = 2x + 1."
        task.updateDiagramFromCondition()
        #expect(task.diagramInQuestion == false)
        task.diagramDescription = "y = x²"
        task.diagramIsAutomatic = false
        task.updateDiagramFromCondition()
        #expect(task.diagramDescription == "y = x²")
        task.diagramDescription = nil
        task.updateDiagramFromCondition()
        #expect(task.diagramDescription == nil)
    }

    @Test(arguments: ["y = x^2 и y = x", "y = x + z", "y = x/2x", "y = 1/0", "y = x +",
                      "Треугольник ABC: A(0; 0), B(1; 0)", "A(1,2,3)",
                      "Треугольник ABC: A(0; 0), B(1; 1), C(2; 2)",
                      "Многоугольник ABCD: A(0; 0), B(4; 4), C(0; 4), D(3; 0)",
                      "Точки A(0; 0), A(1; 1)", "Окружность: центр O(0; 0), радиус -2",
                      "Прямоугольник: ширина 4, высота 3. Точка A(1; 1)",
                      "Дан треугольник со сторонами 3 и 4.", "A(0; 0). Проведите касательную."])
    func rejectsUnsupportedAmbiguousOrUnderdeterminedInputs(text: String) {
        #expect(throws: StudyDiagramError.self) {
            try StudyDiagram.parse(text)
        }
    }
}
