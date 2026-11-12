import Foundation

public enum PracticeGrade: Equatable, Sendable {
    case unanswered, correct, incorrect, manual
}

public extension PracticeTask {
    func grade(response: String) -> PracticeGrade {
        let response = response.cleaned
        guard !response.isEmpty else { return .unanswered }

        let instructions = ShortAnswer.normalized(kind + " " + prompt)
        guard !ShortAnswer.openInstructions.matches(instructions),
              !ShortAnswer.rubric.matches(ShortAnswer.normalized(solution)) else { return .manual }

        let answer = answer.cleaned
        if answerOrigin == .localSolution,
           let matches = LocalPracticeSolver.compareNumericAnswer(response, to: answer) {
            return matches ? .correct : .incorrect
        }
        if let expected = ShortAnswer.piLiteral(answer) {
            return ShortAnswer.piLiteral(response) == expected ? .correct : .manual
        }

        let isSequence = ShortAnswer.sequenceInstructions.matches(instructions)
        guard let expected = ShortAnswer.comparable(answer, isSequence: isSequence),
              let submitted = ShortAnswer.comparable(response, isSequence: isSequence) else { return .manual }

        return submitted == expected ? .correct : .incorrect
    }
}

private enum ShortAnswer {
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .lowercased().precomposedStringWithCanonicalMapping
    }

    static func piLiteral(_ text: String) -> String? {
        guard text.count <= 80, !text.contains(where: \.isNewline) else { return nil }
        let notation = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "−", with: "-")
        guard pi.matches(notation) else { return nil }
        return notation.replacingOccurrences(of: " ", with: "")
    }

    static func comparable(_ text: String, isSequence: Bool) -> String? {
        // Preserve line breaks as a signal of an answer that has several parts.
        guard !text.isEmpty, text.count <= 80, !text.contains(where: \.isNewline) else { return nil }
        let text = normalized(text)
        guard !placeholders.contains(text), !ambiguousWording.matches(text), !rubric.matches(text) else { return nil }

        let signed = text.replacingOccurrences(of: "−", with: "-")
        if isSequence {
            let delimited = signed.replacingOccurrences(of: #" *([,;]) *"#, with: "$1", options: .regularExpression)
            if delimitedSequence.matches(delimited) { return delimited }
        }
        if decimal.matches(signed) {
            // In an ordered answer a comma can separate two entries.
            return isSequence ? signed : signed.replacingOccurrences(of: ",", with: ".")
        }
        if fraction.matches(signed) {
            // Compare the written fraction without evaluating or reducing it.
            return signed.replacingOccurrences(of: " ", with: "")
        }
        if digitSequence.matches(signed) { return signed }
        if code.matches(text) || words.matches(text) { return text }
        return nil
    }

    private static let placeholders: Set<String> = [
        "нет ответа", "нет ключа", "не указан", "не указано", "неизвестно", "ответ не указан",
        "ответ отсутствует", "см. решение", "см. решение.", "n/a", "tbd", "todo", "null"
    ]
    private static let ambiguousWording = NSRegularExpression(
        #"\b(?:или|либо|or|either|например|допускается|принимается|потому что|так как|возможный ответ|зависит от)\b"#
    )
    static let openInstructions = NSRegularExpression(
        #"\b(?:обоснуйте|докажите|объясните|поясните|доказательство|сочинение|эссе|разв[её]рнутый ответ|открытый вопрос|ручная проверка|напишите (?:программу|письмо|рассказ|текст)|приведите (?:пример|аргумент)|запишите решение|покажите (?:ход решения|решение)|justify|prove|explain|open[- ]ended|write (?:an? )?(?:essay|program|letter)|show (?:your work|that))\b"#
    )
    static let rubric = NSRegularExpression(
        #"\b(?:критери[йия] оцен(?:ивания|ки)|балл(?:а|ов)? (?:ставится|выставляется|начисляется)|(?:выставляется|начисляется) [0-9]+ балл(?:а|ов)?|grading criteria|rubric|mark scheme)\b"#
    )
    static let sequenceInstructions = NSRegularExpression(
        #"\b(?:последовательность|перечислите|координаты|корни|(?:запишите|укажите) (?:пару чисел|оба значения|два числа)|в (?:указанном|правильном|нужном) порядке|в порядке (?:убывания|возрастания)|через (?:запятую|точку с запятой)|(?:comma|semicolon)[- ]separated|(?:ascending|descending) order)\b"#
    )
    private static let pi = NSRegularExpression(#"\A[+-]?(?:(?:0|[1-9][0-9]*)(?:[,.][0-9]+)? *)?π\z"#)
    private static let decimal = NSRegularExpression(#"\A[+-]?(?:0|[1-9][0-9]*)(?:[,.][0-9]+)?\z"#)
    private static let fraction = NSRegularExpression(#"\A[+-]?(?:0|[1-9][0-9]*) */ *[1-9][0-9]*\z"#)
    private static let digitSequence = NSRegularExpression(#"\A[+-]?[0-9]+(?: [+-]?[0-9]+)*\z"#)
    private static let delimitedSequence = NSRegularExpression(
        #"\A(?:[+-]?[0-9]+|[\p{L}\p{M}0-9]+)(?:[,;](?:[+-]?[0-9]+|[\p{L}\p{M}0-9]+))+\z"#
    )
    private static let code = NSRegularExpression(#"\A\p{L}[\p{L}\p{M}0-9]*[0-9][\p{L}\p{M}0-9]*\z"#)
    private static let words = NSRegularExpression(
        #"\A(?:\p{L}[\p{L}\p{M}]+-)*\p{L}[\p{L}\p{M}]*(?: (?:\p{L}[\p{L}\p{M}]+-)*\p{L}[\p{L}\p{M}]*){0,3}\z"#
    )
}

private extension NSRegularExpression {
    convenience init(_ pattern: String) {
        try! self.init(pattern: pattern)
    }

    func matches(_ text: String) -> Bool {
        firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
