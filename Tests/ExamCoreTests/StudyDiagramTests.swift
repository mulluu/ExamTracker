import Testing
@testable import ExamCore

struct StudyDiagramTests {
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
