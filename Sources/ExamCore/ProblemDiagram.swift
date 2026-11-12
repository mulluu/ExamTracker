import Foundation

/// Builds a diagram from data written in a problem's condition.
public struct ProblemDiagram: Sendable {
    public let description: String
    public let drawing: StudyDiagram
    public let showsDuringPractice: Bool

    static func requiresConstruction(_ condition: String) -> Bool {
        drawingInstruction.first(in: condition) != nil
    }

    public static func fromCondition(_ condition: String) -> Self? {
        let condition = condition.cleaned.replacingOccurrences(of: "−", with: "-")
        guard !condition.isEmpty, condition.utf8.count <= 4096,
              answerMarker.first(in: condition) == nil else { return nil }

        let instructions = questionBoundary.first(in: condition)?.lowerBound ?? condition.endIndex
        let data = String(condition[..<instructions]).cleaned
        let source = description(in: data, fullCondition: condition)
        if let source, let drawing = try? StudyDiagram.parse(source) {
            return Self(description: source, drawing: drawing,
                        showsDuringPractice: !requiresConstruction(condition))
        }
        guard assignment.first(in: condition) == nil,
              let source = PlanimetryDiagram.description(from: condition),
              let drawing = try? StudyDiagram.parse(source) else { return nil }
        return Self(description: source, drawing: drawing,
                    showsDuringPractice: !requiresConstruction(condition))
    }

    private static func description(in data: String, fullCondition: String) -> String? {
        let definitions = assignment.numberOfMatches(in: fullCondition, range: NSRange(fullCondition.startIndex..., in: fullCondition))
        if definitions != 0 {
            guard definitions == 1, domainRestriction.first(in: fullCondition) == nil,
                  let definition = assignment.first(in: data) else { return nil }
            let prefix = String(data[..<definition.lowerBound])
                .components(separatedBy: .newlines).last ?? ""
            guard prefix.cleaned.isEmpty || definitionLead.first(in: prefix) != nil else { return nil }
            let expression = data[definition.upperBound...].split(whereSeparator: \.isWhitespace).joined(separator: " ")
            // The full expression goes through the math parser, including any unsupported suffix.
            return "y = \(expression)"
        }

        guard geometryHint.first(in: data) != nil else { return nil }
        if let shape = dimensions.firstMatch(in: data, range: NSRange(data.startIndex..., in: data)) {
            return dimensionDescription(shape, in: data)
        }
        return data
    }

    private static func dimensionDescription(_ match: NSTextCheckingResult, in text: String) -> String? {
        func field(_ index: Int) -> String {
            Range(match.range(at: index), in: text).map { String(text[$0]).lowercased() } ?? ""
        }

        let first = field(2)
        let second = field(4)
        let firstUnit = field(3)
        let secondUnit = field(5)
        guard !first.isEmpty else { return nil }
        let shape = field(1)
        switch shape {
        case "квадрат", "квадрата":
            guard second.isEmpty else { return nil }
            return "Прямоугольник: ширина \(first), высота \(first)"
        case "круг", "круга", "окружность", "окружности":
            guard second.isEmpty else { return nil }
            return "Окружность: центр (0; 0), радиус \(first)"
        default:
            // An omitted first unit can use the unit written after the pair.
            guard !second.isEmpty, firstUnit.isEmpty || firstUnit == secondUnit else { return nil }
            if shape.contains("треугольник") {
                guard let a = Double(first.replacingOccurrences(of: ",", with: ".")), a > 0,
                      let b = Double(second.replacingOccurrences(of: ",", with: ".")), b > 0 else { return nil }
                return "Треугольник ABC: A(0; 0), B(\(first); 0), C(0; \(second))"
            }
            return "Прямоугольник: ширина \(first), высота \(second)"
        }
    }

    private static let assignment = regex(#"(?<![\p{L}\p{N}_])(?:[yу]|f\s*\(\s*[xх]\s*\))\s*="#)
    private static let definitionLead = regex(
        #"\b(?:функци(?:я|и|ю|ей)|график(?:а)?|формул(?:а|ой|е)|уравнени(?:е|я|ем|ю)|дано|постройте|нарисуйте|изобразите|function|graph|equation|plot|draw)\s*:?\s*\z"#
    )
    private static let geometryHint = regex(#"\b(?:треугольник\p{L}*|прямоугольник\p{L}*|квадрат\p{L}*|окружност\p{L}*|круг\p{L}*|многоугольник\p{L}*|отрезок|точк\p{L}*)\b|(?<![\p{L}\p{N}_])[A-ZА-ЯЁ]\s*\(\s*[+-]?[0-9]"#)
    private static let answerMarker = regex(#"\b(?:ответ|решение|answer|solution)\s*:"#)
    private static let domainRestriction = regex(#"\b[хx]\s*(?:[∈<>≤≥]|\\in)|\bпри\s+[хx]\s*(?:[∈<>≤≥]|\\in)|\b(?:область определения|кусочно|piecewise|domain)\b"#)
    private static let questionBoundary = regex(
        #"(?:[.!?]\s+|\s*[,;]\s+|\s*\n+\s*)(?=(?:найдите|вычислите|определите|укажите|чему|сколько|постройте|начертите|изобразите|нарисуйте|проведите|докажите|решите|find|calculate|determine|draw|plot|sketch)\b)"#
    )
    private static let drawingInstruction = regex(
        #"\b(?:построй(?:те)?|построить|выполните\s+построение|начерти(?:те)?|изобрази(?:те)?|нарисуй(?:те)?|проведи(?:те)?|решите\s+графически|draw|plot|sketch|graph\s+the|(?:construct|create)\s+(?:a|the)\s+graph)\b"#
    )
    private static let number = #"[0-9]+(?:[,.][0-9]+)?"#
    private static let length = #"(\#(number))(?:\s*(мм|см|м|км))?"#
    private static let dimensions = regex(
        #"\A(?:(?:дан|дана|дано|постройте|изобразите|нарисуйте|найдите\s+площадь|вычислите\s+площадь|найдите\s+периметр)\s+)?(прямоугольника?|квадрата?|круга?|окружность|окружности|прямоугольный\s+треугольник|прямоугольного\s+треугольника)\s+(?:со\s+сторонами|со\s+стороной|с\s+катетами|с\s+радиусом|радиуса|радиусом)\s+\#(length)(?:\s+и\s+\#(length))?\s*[.!?]?\z"#
    )

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }
}

public extension PracticeTask {
    /// Keeps a manually attached or explicitly removed diagram intact.
    mutating func updateDiagramFromCondition() {
        guard diagramIsAutomatic == true || (diagramIsAutomatic == nil && diagramDescription == nil) else { return }
        let generated = ProblemDiagram.fromCondition(prompt)
        if generated?.description != diagramDescription {
            diagramInQuestion = generated?.showsDuringPractice
        }
        diagramDescription = generated?.description
        diagramIsAutomatic = generated.map { _ in true }
    }
}

private extension NSRegularExpression {
    func first(in text: String) -> Range<String.Index>? {
        firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            .flatMap { Range($0.range, in: text) }
    }
}
