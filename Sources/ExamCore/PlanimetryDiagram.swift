import Foundation

/// Turns explicit triangle constraints into a representative drawing at a fixed scale.
enum PlanimetryDiagram {
    private struct Point {
        let label: Character
        let x: Double
        let y: Double

        var description: String { "\(label)(\(x); \(y))" }
    }

    static func description(from condition: String) -> String? {
        let text = condition
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: #"(?<=\p{Ll})[-‐]\s+(?=\p{Ll})"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let values = matches(unnamedSides, in: text).first,
           let ab = number(values[0]), let ac = number(values[1]), let bc = number(values[2]) {
            return triangleBySides(ab: ab, ac: ac, bc: bc)
        }
        let range = NSRange(text.startIndex..., in: text)
        guard triangle.firstMatch(in: text, range: range) != nil else { return nil }

        let sideLengths = matches(namedSide, in: text)
        if sideLengths.count == 3 {
            let units = Set(sideLengths.map { $0[3].lowercased() }.filter { !$0.isEmpty })
            guard units.count <= 1 else { return nil }
            var sides: [String: Double] = [:]
            for match in sideLengths {
                guard let a = vertex(match[0]), let b = vertex(match[1]), a != b,
                      let length = number(match[2]) else { return nil }
                let side = String([a, b].sorted())
                guard sides.updateValue(length, forKey: side) == nil else { return nil }
            }
            if let ab = sides["AB"], let ac = sides["AC"], let bc = sides["BC"] {
                return triangleBySides(ab: ab, ac: ac, bc: bc)
            }
        }

        var angles: [Character: Double] = [:]
        for (pattern, isExterior) in [(interiorAngle, false), (exteriorAngle, true)] {
            for match in matches(pattern, in: text) {
                guard let label = vertex(match[0]),
                      let degrees = Double(match[1].replacingOccurrences(of: ",", with: ".")),
                      (0..<180).contains(degrees), degrees > 0 else { return nil }
                let angle = isExterior ? 180 - degrees : degrees
                if let previous = angles[label], abs(previous - angle) > 1e-9 { return nil }
                angles[label] = angle
            }
        }
        if let match = matches(rightTriangleAcuteAngle, in: text).first {
            guard let label = vertex(match[0]),
                  let degrees = Double(match[1].replacingOccurrences(of: ",", with: ".")),
                  (0..<90).contains(degrees), degrees > 0 else { return nil }
            if let previous = angles[label], abs(previous - degrees) > 1e-9 { return nil }
            angles[label] = degrees
        }
        if rightAtC.firstMatch(in: text, range: range) != nil {
            if let previous = angles["C"], previous != 90 { return nil }
            angles["C"] = 90
        }

        if angles["C"] == 90 {
            return rightTriangle(angles: angles, text: text)
        }

        guard equalSides.firstMatch(in: text, range: range) != nil
                || isoscelesWithBase.firstMatch(in: text, range: range) != nil else { return nil }
        let baseAngle = angles["A"] ?? angles["B"] ?? angles["C"].map { (180 - $0) / 2 }
        guard let baseAngle, baseAngle > 0, baseAngle < 90,
              angles.allSatisfy({ abs($0.value - ($0.key == "C" ? 180 - 2 * baseAngle : baseAngle)) < 1e-9 })
        else { return nil }

        var points = [Point(label: "A", x: -5, y: 0), Point(label: "B", x: 5, y: 0),
                      Point(label: "C", x: 0, y: 5 * tan(baseAngle * .pi / 180))]
        var segments: [String] = []
        if exteriorRayAtB.firstMatch(in: text, range: range) != nil {
            points.append(Point(label: "D", x: 8, y: 0))
            segments.append("BD")
        }
        return diagram(points, segments: segments)
    }

    private static func triangleBySides(ab: Double, ac: Double, bc: Double) -> String? {
        guard min(ab, ac, bc) > 0, max(ab, ac, bc) <= 100_000,
              ab + ac > bc, ab + bc > ac, ac + bc > ab else { return nil }
        let x = (ab * ab + ac * ac - bc * bc) / (2 * ab)
        let heightSquared = (ac - x) * (ac + x)
        guard heightSquared > 0 else { return nil }
        return diagram([Point(label: "A", x: 0, y: 0), Point(label: "B", x: ab, y: 0),
                        Point(label: "C", x: x, y: sqrt(heightSquared))], segments: [])
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private static func rightTriangle(angles: [Character: Double], text: String) -> String? {
        let angleB = angles["B"] ?? angles["A"].map { 90 - $0 }
        guard let angleB, angleB > 0, angleB < 90,
              angles["A"].map({ abs($0 + angleB - 90) < 1e-9 }) ?? true else { return nil }

        let base = 10.0
        let height = base * tan(angleB * .pi / 180)
        var points = [Point(label: "A", x: 0, y: height), Point(label: "B", x: base, y: 0),
                      Point(label: "C", x: 0, y: 0)]
        var segments: [String] = []

        for (pattern, isMedian) in [(median, true), (bisector, false)] {
            let labels = Set(matches(pattern, in: text).compactMap { ($0[0].isEmpty ? $0[1] : $0[0]).uppercased().last })
            guard labels.count <= 1 else { return nil }
            guard let label = labels.first else { continue }
            let coordinate = base * height / (base + height)
            let point = isMedian ? Point(label: label, x: base / 2, y: height / 2)
                : Point(label: label, x: coordinate, y: coordinate)
            if let previous = points.first(where: { $0.label == label }) {
                guard abs(previous.x - point.x) < 1e-9, abs(previous.y - point.y) < 1e-9 else { return nil }
            } else {
                points.append(point)
                segments.append("C\(label)")
            }
        }

        return diagram(points, segments: segments)
    }

    private static func diagram(_ points: [Point], segments: [String]) -> String {
        (["Треугольник ABC: " + points.map(\.description).joined(separator: ", ")] +
         segments.map { "Отрезок \($0)" }).joined(separator: ". ")
    }

    private static func vertex(_ text: String) -> Character? {
        switch text.uppercased() {
        case "A", "А": "A"
        case "B", "В": "B"
        case "C", "С": "C"
        default: nil
        }
    }

    private static let triangle = regex(#"\bтреугольник(?:е|а)?\s+[AА][BВ][CС]\b"#)
    private static let angle = #"([0-9]+(?:[,.][0-9]+)?)\s*°"#
    private static let interiorAngle = regex(#"\b(?<!внешний )угол\s+(?:при\s+вершине\s+)?([AАBВCС])\s*(?:равен|=)\s*\#(angle)"#)
    private static let exteriorAngle = regex(#"\bвнешний\s+угол\s+при\s+вершине\s+([AАBВ])\s*(?:равен|=)\s*\#(angle)"#)
    private static let rightTriangleAcuteAngle = regex(#"\bострый\s+угол\s+([AАBВ])\s+прямоугольного\s+треугольника\s+[AА][BВ][CС]\s+равен\s*\#(angle)"#)
    private static let rightAtC = regex(#"\bпрямого\s+угла\s+[CС]\b|\bпрямой\s+угол\s+[CС]\b"#)
    private static let equalSides = regex(#"\bстороны\s+(?:[AА][CС]\s+и\s+[BВ][CС]|[BВ][CС]\s+и\s+[AА][CС])\s+равны\b"#)
    private static let isoscelesWithBase = regex(#"\bравнобедренный\s+треугольник\s+[AА][BВ][CС]\s+с\s+основанием\s+[AА][BВ]\b"#)
    private static let length = #"([0-9]+(?:[,.][0-9]+)?)"#
    private static let namedSide = regex(#"\b([AАBВCС])([AАBВCС])\s*=\s*\#(length)(?:\s*(мм|см|км|м|mm|cm|km|m|ft|in)\b)?(?![\p{L}\p{N}]|[,.][0-9])"#)
    private static let unnamedSides = regex(
        #"\A(?:(?:дан|постройте)\s+)?треугольник\s+со\s+сторонами\s+\#(length)\s*,\s+\#(length)\s+и\s+\#(length)(?:[.!?]|\z)"#
    )
    private static let exteriorRayAtB = regex(#"\bугол\s+[CС][BВ]D\s+(?:—\s*)?внешний\b"#)
    private static let median = regex(#"\bмедиан(?:а|ой|у|ы)\s+([CС][D-Z])\b|\b([CС][D-Z])\s*[-–—]\s*медиана\b"#)
    private static let bisector = regex(#"\bбиссектрис(?:а|ой|у|ы)\s+([CС][D-Z])\b|\b([CС][D-Z])\s*[-–—]\s*биссектриса\b"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }

    private static func matches(_ expression: NSRegularExpression, in text: String) -> [[String]] {
        expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}
