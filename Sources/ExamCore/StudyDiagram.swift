import Foundation

public struct StudyDiagram: Sendable {
    public enum Kind: Equatable, Sendable { case graph, geometry, trace }

    public struct Point: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let label: String?

        init(x: Double, y: Double, label: String? = nil) {
            self.x = x
            self.y = y
            self.label = label
        }
    }

    public struct Path: Sendable {
        public let points: [Point]
        public let isClosed: Bool
    }

    public struct Circle: Sendable {
        public let center: Point
        public let radius: Double
    }

    public struct Bounds: Sendable {
        public let minX: Double
        public let maxX: Double
        public let minY: Double
        public let maxY: Double
    }

    public let kind: Kind
    public let bounds: Bounds
    public let paths: [Path]
    public let points: [Point]
    public let circles: [Circle]

    public static func parse(_ text: String) throws -> StudyDiagram {
        let text = text.cleaned.replacingOccurrences(of: "−", with: "-")
        if isImageTrace(text) { return try ImageDiagramTrace.parse(text) }
        guard !text.isEmpty, text.utf8.count <= 4096 else { throw StudyDiagramError.unsupportedInput }
        if let match = Self.formula.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            var parser = try FormulaParser(String(text[range]))
            return try graph(parser.parse())
        }
        return try GeometryParser().parse(text)
    }

    private static let formula = try! NSRegularExpression(pattern:
        #"\A(?:(?:(?:постройте|изобразите|нарисуйте)\s+)?график(?:\s+функции)?\s*:?\s*)?[yу]\s*=\s*([^\r\n]+?)\s*[.;?]?\s*\z"#,
        options: .caseInsensitive
    )

    private static func graph(_ expression: Formula) throws -> StudyDiagram {
        let coarse = (-200...200).map { Sample(x: Double($0) / 20, expression: expression) }
        let coarseValues = coarse.compactMap { $0.point?.y }.sorted()
        let tail = coarseValues.count / 50
        let coarseSpan = coarseValues.isEmpty ? 0 : coarseValues[coarseValues.count - tail - 1] - coarseValues[tail]
        let tolerance = max(0.01, coarseSpan * 0.001)
        var samples: [Point?] = [coarse[0].point]
        var budget = 24_000
        for (left, right) in zip(coarse, coarse.dropFirst()) {
            try subdivide(left, right, expression: expression, tolerance: tolerance, depth: 0,
                          budget: &budget, samples: &samples)
        }
        let values = samples.compactMap { $0?.y }.sorted()
        guard let first = values.first, let last = values.last else { throw StudyDiagramError.noVisibleGraph }

        let padding = max(1, (last - first) * 0.07)
        let bounds = Bounds(minX: -10, maxX: 10, minY: first - padding, maxY: last + padding)
        var paths: [Path] = []
        var path: [Point] = []
        for sample in samples {
            guard let point = sample else {
                appendGraphPath(&path, to: &paths)
                continue
            }
            path.append(point)
        }
        appendGraphPath(&path, to: &paths)
        guard !paths.isEmpty else { throw StudyDiagramError.noVisibleGraph }
        return StudyDiagram(kind: .graph, bounds: bounds, paths: paths, points: [], circles: [])
    }

    private struct Sample {
        let x: Double
        let point: Point?

        init(x: Double, expression: Formula) {
            self.x = x
            if let value = expression.evaluate(Interval(x)), abs(value.low) <= 1_000_000 {
                point = Point(x: x, y: value.low)
            } else {
                point = nil
            }
        }
    }

    private static func subdivide(_ left: Sample, _ right: Sample, expression: Formula, tolerance: Double,
                                  depth: Int, budget: inout Int, samples: inout [Point?]) throws {
        budget -= 1
        guard budget > 0 else { throw StudyDiagramError.unresolvedGraph }
        let middle = Sample(x: (left.x + right.x) / 2, expression: expression)
        if let a = left.point?.y, let b = right.point?.y, let m = middle.point?.y,
           let enclosure = expression.evaluate(Interval(left.x, right.x)),
           abs(m - (a + b) / 2) <= tolerance,
           enclosure.low >= min(a, b, m) - tolerance, enclosure.high <= max(a, b, m) + tolerance {
            samples.append(right.point)
            return
        }
        if depth >= 7 || (left.point == nil && middle.point == nil && right.point == nil) {
            // Unresolved intervals remain gaps, including poles between otherwise finite points.
            samples.append(nil)
            samples.append(right.point)
            return
        }
        try subdivide(left, middle, expression: expression, tolerance: tolerance, depth: depth + 1,
                      budget: &budget, samples: &samples)
        try subdivide(middle, right, expression: expression, tolerance: tolerance, depth: depth + 1,
                      budget: &budget, samples: &samples)
    }

    private static func appendGraphPath(_ path: inout [Point], to paths: inout [Path]) {
        if path.count >= 2 { paths.append(Path(points: path, isClosed: false)) }
        path.removeAll(keepingCapacity: true)
    }
}

public enum StudyDiagramError: LocalizedError, Sendable {
    case unsupportedInput, invalidFormula, invalidGeometry, noVisibleGraph, unresolvedGraph
    case unreadableImage, noImageContours, complexImageContours

    public var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "Не удалось открыть изображение."
        case .noImageContours:
            "Контуры не найдены. Попробуйте крупный контрастный чертёж."
        case .complexImageContours:
            "Слишком много деталей. Обрежьте изображение до нужной фигуры."
        case .unsupportedInput:
            "Введите формулу, координаты или условие с размерами, углами или свойствами фигуры."
        case .invalidFormula:
            "Формулу не удалось разобрать. Проверьте переменную x, знаки и скобки."
        case .invalidGeometry:
            "Проверьте координаты вершин, порядок точек и положительные размеры фигуры."
        case .noVisibleGraph:
            "На интервале от −10 до 10 не удалось построить видимую часть графика."
        case .unresolvedGraph:
            "График слишком сложный для точного отображения на интервале от −10 до 10."
        }
    }
}

private enum FormulaToken: Equatable {
    case number(Double), variable, pi, function(FormulaFunction), op(FormulaOperator), left, right

    var startsImplicitFactor: Bool {
        switch self {
        case .variable, .pi, .function, .left: true
        default: false
        }
    }
}

private enum FormulaOperator: Character { case add = "+", subtract = "-", multiply = "*", divide = "/", power = "^" }
private enum FormulaFunction: String { case sin, cos, sqrt, abs, ln, exp }

private struct FormulaParser {
    private let tokens: [FormulaToken]
    private var index = 0
    private var current: FormulaToken? { index < tokens.count ? tokens[index] : nil }

    init(_ text: String) throws {
        guard text.utf8.count <= 512 else { throw StudyDiagramError.invalidFormula }
        let source = Self.normalized(text)
        var tokens: [FormulaToken] = []
        var cursor = source.startIndex
        while cursor < source.endIndex {
            let char = source[cursor]
            if char.isWhitespace {
                source.formIndex(after: &cursor)
                continue
            }
            if char.isASCII && char.isNumber || char == "." || char == "," {
                let start = cursor
                repeat { source.formIndex(after: &cursor) } while cursor < source.endIndex &&
                    (source[cursor].isASCII && source[cursor].isNumber || ".,".contains(source[cursor]))
                let text = source[start..<cursor].replacingOccurrences(of: ",", with: ".")
                guard let value = Double(text), value.isFinite else { throw StudyDiagramError.invalidFormula }
                tokens.append(.number(value))
                continue
            }
            if let operation = FormulaOperator(rawValue: char) {
                tokens.append(.op(operation))
            } else if char == "(" {
                tokens.append(.left)
            } else if char == ")" {
                tokens.append(.right)
            } else if char == "π" {
                tokens.append(.pi)
            } else if char.isLetter {
                let start = cursor
                repeat { source.formIndex(after: &cursor) } while cursor < source.endIndex &&
                    source[cursor].isLetter && source[cursor] != "π"
                let word = String(source[start..<cursor])
                if word == "x" || word == "х" {
                    tokens.append(.variable)
                } else if let function = FormulaFunction(rawValue: word) {
                    tokens.append(.function(function))
                } else {
                    throw StudyDiagramError.invalidFormula
                }
                continue
            } else {
                throw StudyDiagramError.invalidFormula
            }
            source.formIndex(after: &cursor)
        }
        guard !tokens.isEmpty, tokens.count <= 160 else { throw StudyDiagramError.invalidFormula }
        self.tokens = tokens
    }

    mutating func parse() throws -> Formula {
        let value = try sum()
        guard current == nil else { throw StudyDiagramError.invalidFormula }
        return value
    }

    private mutating func sum() throws -> Formula {
        var left = try product()
        while case let .op(op) = current, op == .add || op == .subtract {
            index += 1
            left = .binary(op, left, try product())
        }
        return left
    }

    private mutating func product() throws -> Formula {
        var left = try unary()
        var hasDivision = false
        while let token = current {
            if case let .op(op) = token, op == .multiply || op == .divide {
                hasDivision = hasDivision || op == .divide
                index += 1
                left = .binary(op, left, try unary())
            } else if token.startsImplicitFactor {
                guard !hasDivision else { throw StudyDiagramError.invalidFormula }
                left = .binary(.multiply, left, try unary())
            } else {
                break
            }
        }
        return left
    }

    private mutating func unary() throws -> Formula {
        if current == .op(.add) || current == .op(.subtract) {
            let negate = current == .op(.subtract)
            index += 1
            let value = try unary()
            return negate ? .negative(value) : value
        }
        let base = try atom()
        guard current == .op(.power) else { return base }
        index += 1
        return .binary(.power, base, try unary())
    }

    private mutating func atom() throws -> Formula {
        guard let token = current else { throw StudyDiagramError.invalidFormula }
        index += 1
        switch token {
        case .number(let value): return .constant(value)
        case .variable: return .variable
        case .pi: return .constant(.pi)
        case .left: return try parenthesized()
        case .function(let name):
            guard current == .left else { throw StudyDiagramError.invalidFormula }
            index += 1
            return .function(name, try parenthesized())
        default: throw StudyDiagramError.invalidFormula
        }
    }

    private mutating func parenthesized() throws -> Formula {
        let value = try sum()
        guard current == .right else { throw StudyDiagramError.invalidFormula }
        index += 1
        return value
    }

    private static func normalized(_ text: String) -> String {
        let superscripts: [Character: Character] = [
            "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6",
            "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-", "⁺": "+"
        ]
        let operators: [Character: String] = ["×": "*", "·": "*", "⋅": "*", "÷": "/", "√": "sqrt"]
        var result = ""
        var inSuperscript = false
        for char in text.lowercased() {
            if let value = superscripts[char] {
                if !inSuperscript { result += "^(" }
                result.append(value)
                inSuperscript = true
                continue
            }
            if inSuperscript { result += ")" }
            inSuperscript = false
            result += operators[char] ?? String(char)
        }
        if inSuperscript { result += ")" }
        return result
    }
}

private indirect enum Formula {
    case constant(Double), variable, negative(Formula)
    case binary(FormulaOperator, Formula, Formula), function(FormulaFunction, Formula)

    func evaluate(_ x: Interval) -> Interval? {
        let value: Interval?
        switch self {
        case .constant(let number): value = Interval(number)
        case .variable: value = x
        case .negative(let expression):
            value = expression.evaluate(x).map { Interval(-$0.high, -$0.low) }
        case .binary(let op, let left, let right):
            guard let a = left.evaluate(x), let b = right.evaluate(x) else { return nil }
            value = a.apply(op, b)
        case .function(let name, let expression):
            guard let argument = expression.evaluate(x) else { return nil }
            value = argument.apply(name)
        }
        guard let value, value.low.isFinite, value.high.isFinite else { return nil }
        return value
    }
}

private struct Interval {
    let low: Double
    let high: Double
    var containsZero: Bool { low <= 0 && high >= 0 }

    init(_ value: Double) { self.init(value, value) }

    init(_ low: Double, _ high: Double) {
        self.low = low
        self.high = high
    }

    func apply(_ op: FormulaOperator, _ other: Interval) -> Interval? {
        switch op {
        case .add: return Interval(low + other.low, high + other.high)
        case .subtract: return Interval(low - other.high, high - other.low)
        case .multiply: return enclosing(with: other, operation: *)
        case .divide:
            guard !other.containsZero else { return nil }
            return enclosing(with: other, operation: /)
        case .power:
            if other.low == other.high {
                let exponent = other.low
                guard (low >= 0 || exponent.rounded(.towardZero) == exponent),
                      (!containsZero || exponent > 0) else { return nil }
                let a = pow(low, exponent)
                let b = pow(high, exponent)
                let minValue = containsZero && exponent > 0 ? min(a, b, 0) : min(a, b)
                return Interval(minValue, max(a, b))
            }
            guard low > 0 else { return nil }
            return enclosing(with: other, operation: pow)
        }
    }

    private func enclosing(with other: Interval, operation: (Double, Double) -> Double) -> Interval? {
        let corners = [operation(low, other.low), operation(low, other.high),
                       operation(high, other.low), operation(high, other.high)]
        guard corners.allSatisfy(\.isFinite), let minimum = corners.min(), let maximum = corners.max() else { return nil }
        return Interval(minimum, maximum)
    }

    func apply(_ function: FormulaFunction) -> Interval? {
        switch function {
        case .sqrt: return low >= 0 ? Interval(sqrt(low), sqrt(high)) : nil
        case .ln: return low > 0 ? Interval(log(low), log(high)) : nil
        case .exp: return Interval(exp(low), exp(high))
        case .abs: return Interval(containsZero ? 0 : min(abs(low), abs(high)), max(abs(low), abs(high)))
        case .sin, .cos:
            let period = 2 * Double.pi
            func evaluate(_ value: Double) -> Double {
                function == .sin ? sin(value) : cos(value)
            }
            let start = evaluate(low)
            guard low != high else { return Interval(start) }
            guard high - low < period, max(abs(low), abs(high)) < 1e12 else { return Interval(-1, 1) }
            let end = evaluate(high)
            let peak = function == .sin ? Double.pi / 2 : 0
            func containsPhase(_ phase: Double) -> Bool {
                ceil((low - phase) / period) <= floor((high - phase) / period)
            }
            let minimum = containsPhase(peak + .pi) ? -1 : min(start, end)
            let maximum = containsPhase(peak) ? 1 : max(start, end)
            return Interval(minimum, maximum)
        }
    }
}

private struct GeometryParser {
    typealias Point = StudyDiagram.Point
    typealias Path = StudyDiagram.Path
    typealias Circle = StudyDiagram.Circle
    typealias Bounds = StudyDiagram.Bounds

    func parse(_ text: String) throws -> StudyDiagram {
        var remaining = text
        var points: [Point] = []
        var named: [String: Point] = [:]
        var paths: [Path] = []
        var circles: [Circle] = []

        func register(_ point: Point) throws {
            guard let label = point.label else { return }
            if let previous = named[label] {
                guard previous == point else { throw StudyDiagramError.invalidGeometry }
                return
            }
            guard points.count < 64 else { throw StudyDiagramError.invalidGeometry }
            named[label] = point
            points.append(point)
        }

        let circleSpecs = Self.extract(Self.circle, from: &remaining)
        let rectangleSpecs = Self.extract(Self.rectangle, from: &remaining)
        for definition in Self.extract(Self.point, from: &remaining) {
            try register(Self.coordinate(definition))
        }
        for spec in circleSpecs {
            let radius = try Self.number(spec[1])
            guard radius > 0 else { throw StudyDiagramError.invalidGeometry }
            let center: Point
            if let definition = Self.captures(Self.center, in: spec[0]).first {
                center = try Self.coordinate(definition)
                try register(center)
            } else if let point = named[spec[0]] {
                center = point
            } else {
                throw StudyDiagramError.invalidGeometry
            }
            circles.append(Circle(center: center, radius: radius))
        }
        for shape in Self.extract(Self.shape, from: &remaining) {
            let labels = shape[1].map(String.init)
            let count = labels.count
            let kind = shape[0].lowercased()
            let closed = kind != "отрезок"
            guard Set(labels).count == count,
                  kind == "отрезок" ? count == 2 : (kind == "многоугольник" ? count >= 3 : count == 3) else {
                throw StudyDiagramError.invalidGeometry
            }
            let vertices = try labels.map { label in
                guard let point = named[label] else { throw StudyDiagramError.invalidGeometry }
                return point
            }
            guard Set(vertices.map { XY(x: $0.x, y: $0.y) }).count == count,
                  !closed || (Self.twiceArea(vertices) != 0 && Self.isSimplePolygon(vertices)) else {
                throw StudyDiagramError.invalidGeometry
            }
            paths.append(Path(points: vertices, isClosed: closed))
        }
        guard rectangleSpecs.isEmpty ||
                (rectangleSpecs.count == 1 && points.isEmpty && paths.isEmpty && circles.isEmpty) else {
            throw StudyDiagramError.invalidGeometry
        }
        for spec in rectangleSpecs {
            let width = try Self.number(spec[0])
            let height = try Self.number(spec[1])
            guard width > 0, height > 0 else { throw StudyDiagramError.invalidGeometry }
            paths.append(Path(points: [Point(x: 0, y: 0), Point(x: width, y: 0),
                                       Point(x: width, y: height), Point(x: 0, y: height)], isClosed: true))
        }
        _ = Self.extract(Self.filler, from: &remaining)
        guard remaining.allSatisfy({ $0.isWhitespace || ",.;:".contains($0) }),
              !points.isEmpty || !paths.isEmpty || !circles.isEmpty else {
            throw StudyDiagramError.unsupportedInput
        }
        guard paths.count + circles.count <= 32 else { throw StudyDiagramError.invalidGeometry }

        let vertices = points + paths.flatMap(\.points)
        let x = vertices.map(\.x) + circles.flatMap { [$0.center.x - $0.radius, $0.center.x + $0.radius] }
        let y = vertices.map(\.y) + circles.flatMap { [$0.center.y - $0.radius, $0.center.y + $0.radius] }
        let (minX, maxX) = Self.padded(x)
        let (minY, maxY) = Self.padded(y)
        return StudyDiagram(kind: .geometry, bounds: Bounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY),
                            paths: paths, points: points, circles: circles)
    }

    private struct XY: Hashable { let x: Double; let y: Double }

    private static func isSimplePolygon(_ vertices: [Point]) -> Bool {
        let edges = Array(zip(vertices, vertices.dropFirst() + [vertices[0]]))
        for first in edges.indices {
            for second in edges.indices where second > first + 1 && !(first == 0 && second == edges.count - 1) {
                if intersects(edges[first], edges[second]) { return false }
            }
        }
        return true
    }

    private static func intersects(_ first: (Point, Point), _ second: (Point, Point)) -> Bool {
        let (a, b) = first
        let (c, d) = second
        func orientation(_ p: Point, _ q: Point, _ r: Point) -> Double {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        func onSegment(_ p: Point, _ q: Point, _ r: Point) -> Bool {
            (min(p.x, q.x)...max(p.x, q.x)).contains(r.x) && (min(p.y, q.y)...max(p.y, q.y)).contains(r.y)
        }
        let abc = orientation(a, b, c)
        let abd = orientation(a, b, d)
        let cda = orientation(c, d, a)
        let cdb = orientation(c, d, b)
        return (abc == 0 && onSegment(a, b, c)) || (abd == 0 && onSegment(a, b, d)) ||
            (cda == 0 && onSegment(c, d, a)) || (cdb == 0 && onSegment(c, d, b)) ||
            (((abc > 0 && abd < 0) || (abc < 0 && abd > 0)) && ((cda > 0 && cdb < 0) || (cda < 0 && cdb > 0)))
    }

    private static func twiceArea(_ vertices: [Point]) -> Double {
        let origin = vertices[0]
        return zip(vertices.dropFirst(), vertices.dropFirst(2)).reduce(0) { area, edge in
            let (a, b) = edge
            return area + (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
        }
    }

    private static func padded(_ values: [Double]) -> (Double, Double) {
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let padding = max(0.5, (maximum - minimum) * 0.1)
        return (minimum - padding, maximum + padding)
    }

    private static func coordinate(_ fields: [String]) throws -> Point {
        let x = try number(fields[1].isEmpty ? fields[3] : fields[1])
        let y = try number(fields[2].isEmpty ? fields[4] : fields[2])
        return Point(x: x, y: y, label: fields[0].isEmpty ? nil : fields[0])
    }

    private static func number(_ text: String) throws -> Double {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), abs(value) <= 100_000 else {
            throw StudyDiagramError.invalidGeometry
        }
        return value
    }

    private static let decimal = #"[+-]?[0-9]+(?:[,.][0-9]+)?"#
    private static let dotted = #"[+-]?[0-9]+(?:\.[0-9]+)?"#
    private static let coordinates = #"\(\s*(?:(\#(decimal))\s*;\s*(\#(decimal))|(\#(dotted))\s*,\s*(\#(dotted)))\s*\)"#
    private static let point = regex(#"(?<![\p{L}\p{N}_])([A-ZА-ЯЁ])\s*\#(coordinates)"#)
    private static let center = regex(#"\A([A-ZА-ЯЁ]?)\s*\#(coordinates)\z"#)
    private static let shape = regex(#"\b((?i:отрезок|треугольник|многоугольник))\s+([A-ZА-ЯЁ]{2,12})\b"#)
    private static let circle = regex(
        #"\b(?i:окружность)\s*(?::\s*)?(?i:с\s+центром|центр)\s*:?\s*([A-ZА-ЯЁ]?\s*\([^()\r\n]+\)|[A-ZА-ЯЁ])\s*(?:,\s*|(?i:и)\s+)?(?i:радиусом|радиус)\s*[:=]?\s*(\#(decimal))(?![\p{L}\p{N}]|[,.][0-9])"#
    )
    private static let rectangle = regex(
        #"\b(?i:прямоугольник)\s*:?\s+(?i:ширина)\s*[:=]?\s*(\#(decimal))\s*(?:,\s*|(?i:и)\s+)(?i:высота)\s*[:=]?\s*(\#(decimal))(?![\p{L}\p{N}]|[,.][0-9])"#
    )
    private static let filler = regex(#"\b(?i:дан|даны|дана|точка|точки|вершины|с\s+вершинами|постройте|изобразите|нарисуйте|и)\b"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static func captures(_ expression: NSRegularExpression, in text: String) -> [[String]] {
        expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    private static func extract(_ expression: NSRegularExpression, from text: inout String) -> [[String]] {
        let matches = captures(expression, in: text)
        text = expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        return matches
    }
}
