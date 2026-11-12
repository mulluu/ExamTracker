import Foundation

public struct LocalPracticeSolution: Sendable {
    public let answer: String
    public let explanation: String
}

public enum LocalPracticeSolver {
    public static func solve(_ task: PracticeTask) -> LocalPracticeSolution? {
        guard task.answer.cleaned.isEmpty, task.prompt.utf8.count <= 1_024 else { return nil }
        let text = task.prompt.replacingOccurrences(of: "−", with: "-")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return try? solve(text)
    }

    public static func compareNumericAnswer(_ response: String, to answer: String) -> Bool? {
        guard let submitted = try? numericAnswer(response), let expected = try? numericAnswer(answer) else { return nil }
        return submitted == expected
    }

    private static func numericAnswer(_ text: String) throws -> Rational {
        guard text.utf8.count <= 80 else { throw Unsupported.problem }
        let text = text.cleaned.replacingOccurrences(of: "−", with: "-")
        if let fields = match(numericFraction, text) {
            return try Rational(fields[0]).dividing(by: Rational(fields[1]))
        }
        guard match(numericLiteral, text) != nil else { throw Unsupported.problem }
        return try Rational(text)
    }

    private static func solve(_ text: String) throws -> LocalPracticeSolution {
        let text = text.last.map { ".!?".contains($0) } == true ? String(text.dropLast()).cleaned : text
        if let geometry = try area(text) { return geometry }
        if let fields = match(wordArithmetic, text) {
            let left = try Rational(fields[1])
            let right = try Rational(fields[2])
            let operation: Character
            switch fields[0].lowercased() {
            case "сумму": operation = "+"
            case "разность": operation = "-"
            case "произведение": operation = "*"
            default: operation = "/"
            }
            let result = try left.apply(operation, right).description
            return LocalPracticeSolution(answer: result, explanation: "\(left) \(operation) \(right) = \(result).")
        }

        if let fields = match(russianEquation, text) {
            return try equation(fields[0], allowComma: true)
        }
        if let fields = match(englishEquation, text) {
            return try equation(fields[0], allowComma: false)
        }
        if let fields = match(russianArithmetic, text) {
            return try arithmetic(fields[0], allowComma: true)
        }
        if let fields = match(englishArithmetic, text) {
            return try arithmetic(fields[0], allowComma: false)
        }
        if text.contains("=") {
            if let fields = match(blankAnswer, text) {
                return try arithmetic(fields[0], allowComma: false)
            }
            return try equation(text, allowComma: false)
        }
        // Standalone slash and dash pairs can be dates, ranges, or labels.
        guard text.dropFirst().contains(where: { "+*^×·⋅÷".contains($0) }) else { throw Unsupported.problem }
        return try arithmetic(text, allowComma: false)
    }

    private static func arithmetic(_ source: String, allowComma: Bool) throws -> LocalPracticeSolution {
        let expression = (match(blankAnswer, source)?.first ?? source).cleaned
        var parser = try LinearParser(expression, allowComma: allowComma, allowsVariable: false)
        let value = try parser.parse().constant.description
        return LocalPracticeSolution(answer: value, explanation: "\(expression) = \(value).")
    }

    private static func equation(_ expression: String, allowComma: Bool) throws -> LocalPracticeSolution {
        let sides = expression.split(separator: "=", omittingEmptySubsequences: false)
        guard sides.count == 2 else { throw Unsupported.problem }
        var leftParser = try LinearParser(String(sides[0]), allowComma: allowComma, allowsVariable: true)
        var rightParser = try LinearParser(String(sides[1]), allowComma: allowComma, allowsVariable: true)
        let left = try leftParser.parse()
        let right = try rightParser.parse()
        let coefficient = try left.coefficient.subtracting(right.coefficient)
        let constant = try right.constant.subtracting(left.constant)
        let value = try constant.dividing(by: coefficient).description
        return LocalPracticeSolution(answer: value, explanation:
            "Переносим слагаемые с x влево, числа вправо: (\(coefficient))x = \(constant). Делим обе части на \(coefficient): x = \(value).")
    }

    private static let russianArithmetic = regex(#"\A(?:вычислите(?:\s+значение(?:\s+выражения)?)?|найдите\s+значение\s+выражения|сколько\s+будет)(?:\s*:\s*|\s+)(.+)\z"#)
    private static let englishArithmetic = regex(#"\A(?:(?:calculate|evaluate|compute)(?:\s+the\s+(?:value\s+of\s+the\s+)?expression)?|what\s+is)(?:\s*:\s*|\s+)(.+)\z"#)
    private static let russianEquation = regex(#"\A(?:решите(?:\s+уравнение)?|найдите\s+(?:значение\s+)?[xх](?:,\s*если)?)(?:\s*:\s*|\s+)(.+)\z"#)
    private static let englishEquation = regex(#"\A(?:solve(?:\s+the\s+equation|\s+for\s+x)?|find\s+x(?:\s+if)?)(?:\s*:\s*|\s+)(.+)\z"#)
    private static let wordArithmetic = regex(#"\Aнайдите\s+(сумму|разность|произведение|частное)\s+чисел\s+(\#(ruNumber))\s+и\s+(\#(ruNumber))\z"#)
    private static let numericLiteral = regex(#"\A\#(ruNumber)\z"#)
    private static let numericFraction = regex(#"\A([+-]?[0-9]+)\h*/\h*([+-]?[0-9]+)\z"#)
    private static let blankAnswer = regex(#"\A(.+?)\s*=\s*[_…?]*\s*\z"#)

    private enum Figure { case rectangle, triangle, square, circle }

    private static func area(_ text: String) throws -> LocalPracticeSolution? {
        for (figure, pattern) in areaPatterns {
            guard let fields = match(pattern, text) else { continue }
            let first = try Rational(fields[0])
            let unit = fields[1].lowercased()
            guard first.numerator > 0 else { throw Unsupported.problem }
            let second: Rational
            if fields.count == 4 {
                second = try Rational(fields[2])
                guard second.numerator > 0, fields[3].lowercased() == unit else { throw Unsupported.problem }
            } else {
                second = first
            }
            let product = try first.multiplying(by: second)
            let answer: String
            let calculation: String
            switch figure {
            case .rectangle:
                answer = product.description
                calculation = "S = a × b = \(first) × \(second)"
            case .triangle:
                answer = try product.dividing(by: Rational(2)).description
                calculation = "S = a × h / 2 = \(first) × \(second) / 2"
            case .square:
                answer = product.description
                calculation = "S = a² = \(first)²"
            case .circle:
                answer = product == .one ? "π" : "\(product)π"
                calculation = "S = πr² = π × \(first)²"
            }
            let suffix = unit.isEmpty ? "" : " \(unit)²"
            return LocalPracticeSolution(answer: answer, explanation: "\(calculation) = \(answer)\(suffix).")
        }
        return nil
    }

    private static let ruNumber = #"[+-]?[0-9]+(?:[,.][0-9]+)?"#
    private static let enNumber = #"[+-]?[0-9]+(?:\.[0-9]+)?"#
    private static let ruLength = #"(\#(ruNumber))(?:\s*(мм|см|м|км))?"#
    private static let enLength = #"(\#(enNumber))(?:\s*(mm|cm|m|km))?"#
    private static let ruArea = #"\A(?:найдите|вычислите)\s+площадь\s+"#
    private static let enArea = #"\A(?:find|calculate|compute)\s+(?:the\s+)?area\s+of\s+(?:a\s+|the\s+)?"#
    private static let areaPatterns: [(Figure, NSRegularExpression)] = [
        (.triangle, regex(ruArea + #"треугольника\s+с\s+основанием\s+\#(ruLength)\s+и\s+высотой\s+\#(ruLength)(?:,\s+опущенной\s+на\s+это\s+основание)?\z"#)),
        (.rectangle, regex(ruArea + #"прямоугольника\s+со\s+сторонами\s+\#(ruLength)\s+и\s+\#(ruLength)\z"#)),
        (.rectangle, regex(ruArea + #"прямоугольника\s+(?:с\s+)?длиной\s+\#(ruLength)\s+и\s+шириной\s+\#(ruLength)\z"#)),
        (.square, regex(ruArea + #"квадрата\s+со\s+стороной\s+\#(ruLength)\z"#)),
        (.circle, regex(ruArea + #"круга\s+(?:радиуса|с\s+радиусом)\s+\#(ruLength)\z"#)),
        (.triangle, regex(enArea + #"triangle\s+with\s+(?:a\s+)?base\s+\#(enLength)\s+and\s+(?:a\s+)?height\s+\#(enLength)\z"#)),
        (.rectangle, regex(enArea + #"rectangle\s+with\s+(?:(?:a\s+)?length\s+)?\#(enLength)\s+(?:and\s+(?:a\s+)?width|by)\s+\#(enLength)\z"#)),
        (.square, regex(enArea + #"square\s+with\s+(?:a\s+)?side(?:\s+length)?\s+\#(enLength)\z"#)),
        (.circle, regex(enArea + #"circle\s+with\s+(?:a\s+)?radius\s+\#(enLength)\z"#))
    ]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }

    private static func match(_ pattern: NSRegularExpression, _ text: String) -> [String]? {
        guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

private enum Unsupported: Error { case problem }

private struct Rational: Equatable, CustomStringConvertible {
    let numerator: Int64
    let denominator: Int64

    static let zero = Rational(0)
    static let one = Rational(1)

    init(_ value: Int64) {
        numerator = value
        denominator = 1
    }

    private init(reducedNumerator: Int64, positiveDenominator: Int64) {
        numerator = reducedNumerator
        denominator = positiveDenominator
    }

    init(_ text: String) throws {
        let fields = text.replacingOccurrences(of: ",", with: ".").split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count <= 2 else { throw Unsupported.problem }
        if fields.count == 1 {
            guard let integer = Int64(fields[0]), integer != .min else { throw Unsupported.problem }
            self.init(integer)
            return
        }
        guard (1...15).contains(fields[1].count), let integer = Int64(fields[0] + fields[1]) else {
            throw Unsupported.problem
        }
        let scale = (0..<fields[1].count).reduce(Int64(1)) { value, _ in value * 10 }
        try self.init(numerator: integer, denominator: scale)
    }

    private init(numerator: Int64, denominator: Int64) throws {
        guard numerator != .min, denominator != .min, denominator != 0 else { throw Unsupported.problem }
        let divisor = Self.gcd(abs(numerator), abs(denominator))
        self.numerator = (denominator < 0 ? -numerator : numerator) / divisor
        self.denominator = abs(denominator) / divisor
    }

    func negated() -> Rational {
        // Parsed values and arithmetic results exclude Int64.min.
        Rational(reducedNumerator: -numerator, positiveDenominator: denominator)
    }

    func subtracting(_ other: Rational) throws -> Rational {
        try adding(other.negated())
    }

    func adding(_ other: Rational) throws -> Rational {
        let common = Self.gcd(denominator, other.denominator)
        let lhs = try numerator.checkedTimes(other.denominator / common)
        let rhs = try other.numerator.checkedTimes(denominator / common)
        return try Rational(numerator: lhs.checkedPlus(rhs),
                            denominator: denominator.checkedTimes(other.denominator / common))
    }

    func multiplying(by other: Rational) throws -> Rational {
        let first = Self.gcd(abs(numerator), other.denominator)
        let second = Self.gcd(abs(other.numerator), denominator)
        return try Rational(numerator: (numerator / first).checkedTimes(other.numerator / second),
                            denominator: (denominator / second).checkedTimes(other.denominator / first))
    }

    func dividing(by other: Rational) throws -> Rational {
        try multiplying(by: Rational(numerator: other.denominator, denominator: other.numerator))
    }

    func applyingPower(_ exponent: Rational) throws -> Rational {
        guard exponent.denominator == 1, (-12...12).contains(exponent.numerator),
              numerator != 0 || exponent.numerator > 0 else { throw Unsupported.problem }
        let base = exponent.numerator < 0 ? try Rational.one.dividing(by: self) : self
        return try (0..<abs(exponent.numerator)).reduce(.one) { result, _ in try result.multiplying(by: base) }
    }

    func apply(_ operation: Character, _ other: Rational) throws -> Rational {
        switch operation {
        case "+": try adding(other)
        case "-": try subtracting(other)
        case "*": try multiplying(by: other)
        case "/": try dividing(by: other)
        default: throw Unsupported.problem
        }
    }

    var description: String {
        if denominator == 1 { return String(numerator) }
        let divisor = UInt64(denominator)
        let whole = numerator.magnitude / divisor
        var remainder = numerator.magnitude % divisor
        var digits = ""
        while remainder != 0 && digits.count < 18 {
            let step = divisor.dividingFullWidth(remainder.multipliedFullWidth(by: 10))
            digits += String(step.quotient)
            remainder = step.remainder
        }
        guard remainder == 0 else { return "\(numerator)/\(denominator)" }
        let sign = numerator < 0 ? "-" : ""
        return "\(sign)\(whole),\(digits)"
    }

    private static func gcd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        var a = lhs
        var b = rhs
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}

private extension Int64 {
    func checkedTimes(_ other: Int64) throws -> Int64 {
        let (value, overflow) = multipliedReportingOverflow(by: other)
        guard !overflow else { throw Unsupported.problem }
        return value
    }

    func checkedPlus(_ other: Int64) throws -> Int64 {
        let (value, overflow) = addingReportingOverflow(other)
        guard !overflow else { throw Unsupported.problem }
        return value
    }
}

private struct LinearExpression {
    let coefficient: Rational
    let constant: Rational

    static func number(_ value: Rational) -> LinearExpression {
        LinearExpression(coefficient: .zero, constant: value)
    }

    static let variable = LinearExpression(coefficient: .one, constant: .zero)

    func negated() -> LinearExpression {
        LinearExpression(coefficient: coefficient.negated(), constant: constant.negated())
    }

    func apply(_ operation: Character, _ other: LinearExpression) throws -> LinearExpression {
        switch operation {
        case "+":
            return try LinearExpression(coefficient: coefficient.adding(other.coefficient),
                                        constant: constant.adding(other.constant))
        case "-":
            return try apply("+", other.negated())
        case "*":
            if other.coefficient == .zero {
                return try scaled(by: other.constant)
            }
            guard coefficient == .zero else { throw Unsupported.problem }
            return try other.scaled(by: constant)
        case "/":
            guard other.coefficient == .zero else { throw Unsupported.problem }
            return try scaled(by: Rational.one.dividing(by: other.constant))
        case "^":
            guard other.coefficient == .zero else { throw Unsupported.problem }
            if other.constant == .one { return self }
            guard coefficient == .zero else { throw Unsupported.problem }
            return try .number(constant.applyingPower(other.constant))
        default:
            throw Unsupported.problem
        }
    }

    private func scaled(by value: Rational) throws -> LinearExpression {
        try LinearExpression(coefficient: coefficient.multiplying(by: value), constant: constant.multiplying(by: value))
    }
}

private struct LinearParser {
    private enum Token: Equatable {
        case number(Rational), variable, operation(Character), open, close
    }

    private let tokens: [Token]
    private var index = 0
    private var current: Token? { index < tokens.count ? tokens[index] : nil }

    init(_ text: String, allowComma: Bool, allowsVariable: Bool) throws {
        let characters = Array(Self.normalized(text).lowercased())
        guard characters.count <= 240 else { throw Unsupported.problem }
        var tokens: [Token] = []
        var offset = 0
        while offset < characters.count {
            let character = characters[offset]
            if Self.digit(character) {
                let start = offset
                repeat { offset += 1 } while offset < characters.count && Self.digit(characters[offset])
                if offset < characters.count && (characters[offset] == "." || characters[offset] == ",") {
                    guard characters[offset] == "." || allowComma else { throw Unsupported.problem }
                    offset += 1
                    guard offset < characters.count && Self.digit(characters[offset]) else { throw Unsupported.problem }
                    repeat { offset += 1 } while offset < characters.count && Self.digit(characters[offset])
                }
                tokens.append(.number(try Rational(String(characters[start..<offset]))))
                continue
            }
            if "+-*/^".contains(character) {
                tokens.append(.operation(character))
            } else if character == "(" {
                tokens.append(.open)
            } else if character == ")" {
                tokens.append(.close)
            } else if allowsVariable && (character == "x" || character == "х") {
                tokens.append(.variable)
            } else if !character.isWhitespace {
                throw Unsupported.problem
            }
            offset += 1
        }
        guard !tokens.isEmpty, tokens.count <= 100 else { throw Unsupported.problem }
        self.tokens = tokens
    }

    mutating func parse() throws -> LinearExpression {
        let value = try sum()
        guard current == nil else { throw Unsupported.problem }
        return value
    }

    private mutating func sum() throws -> LinearExpression {
        var value = try product()
        while case let .operation(op) = current, op == "+" || op == "-" {
            index += 1
            value = try value.apply(op, product())
        }
        return value
    }

    private mutating func product() throws -> LinearExpression {
        var value = try unary()
        var hasDivision = false
        while let token = current {
            if case let .operation(op) = token, op == "*" || op == "/" {
                hasDivision = hasDivision || op == "/"
                index += 1
                value = try value.apply(op, unary())
            } else if token == .variable || token == .open {
                guard !hasDivision else { throw Unsupported.problem }
                value = try value.apply("*", unary())
            } else {
                break
            }
        }
        return value
    }

    private mutating func unary() throws -> LinearExpression {
        if current == .operation("+") || current == .operation("-") {
            let negate = current == .operation("-")
            index += 1
            let value = try unary()
            return negate ? value.negated() : value
        }
        let base = try atom()
        guard current == .operation("^") else { return base }
        index += 1
        return try base.apply("^", unary())
    }

    private mutating func atom() throws -> LinearExpression {
        guard let token = current else { throw Unsupported.problem }
        index += 1
        switch token {
        case .number(let value):
            return .number(value)
        case .variable:
            return .variable
        case .open:
            let value = try sum()
            guard current == .close else { throw Unsupported.problem }
            index += 1
            return value
        default:
            throw Unsupported.problem
        }
    }

    private static func digit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    private static func normalized(_ text: String) -> String {
        let superscripts: [Character: Character] = [
            "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6",
            "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-", "⁺": "+"
        ]
        let operators: [Character: Character] = ["×": "*", "·": "*", "⋅": "*", "÷": "/"]
        var result = ""
        var isExponent = false
        for character in text {
            if let digit = superscripts[character] {
                if !isExponent { result += "^(" }
                result.append(digit)
                isExponent = true
            } else {
                if isExponent { result += ")" }
                result.append(operators[character] ?? character)
                isExponent = false
            }
        }
        if isExponent { result += ")" }
        return result
    }
}
