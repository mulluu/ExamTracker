import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public enum TaskImportError: LocalizedError, Equatable {
    case invalidSelection
    case selectionTooLarge
    case unsupportedFormat
    case unreadableFile
    case lockedPDF
    case noText
    case noNumberedTasks
    case recognitionFailed
    case unavailablePages(pageCount: Int)
    case unresolved(missing: [Int], repeated: [Int])

    public var errorDescription: String? {
        switch self {
        case .invalidSelection:
            "Введите номера и диапазоны через запятую, например 1, 3, 6–8."
        case .selectionTooLarge:
            "Выберите не более 1000 заданий за один импорт."
        case .unsupportedFormat:
            "Выберите PDF, ZIP, TXT, DOCX или изображение."
        case .unreadableFile:
            "Не удалось прочитать файл. Проверьте, что он открывается на Mac."
        case .lockedPDF:
            "PDF защищён паролем. Для импорта нужна незаблокированная копия."
        case .noText:
            "Текст не найден. Проверьте, что текст на странице или снимке читается."
        case .noNumberedTasks:
            "Номера заданий не найдены. Можно добавить выбранные страницы целиком."
        case .recognitionFailed:
            "macOS не удалось распознать текст на изображении. Попробуйте PDF с текстовым слоем или TXT."
        case .unavailablePages(let pageCount):
            "Выберите страницы от 1 до \(pageCount)."
        case .unresolved(let missing, let repeated):
            [
                missing.isEmpty ? nil : "Не найдены задания № \(missing.map(String.init).joined(separator: ", ")).",
                repeated.isEmpty ? nil : "Номера встречаются несколько раз в заданиях или ключе ответов: \(repeated.map(String.init).joined(separator: ", "))."
            ].compactMap { $0 }.joined(separator: " ")
        }
    }
}

public enum TaskImport {
    public static let fileTypes = [UTType.pdf, .zip, .plainText, .image] + [UTType(filenameExtension: "docx")].compactMap { $0 }

    private static let selectionLimit = 1000

    public static func selectedNumbers(_ input: String) throws -> [Int] {
        var numbers: [Int] = []
        var seen: Set<Int> = []
        let selection = input.replacingOccurrences(of: "№", with: "")
            .replacingOccurrences(of: #"(?<=[0-9])\h+(?=[0-9])"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #"\s*[\r\n]+\s*"#, with: ",", options: .regularExpression)
        for term in selection.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == ";" }) {
            let bounds = term.split(omittingEmptySubsequences: false, whereSeparator: { "-–—−".contains($0) })
            guard let first = bounds.first.flatMap({ positiveNumber(String($0).cleaned) }), bounds.count <= 2,
                  let last = positiveNumber(String(bounds[bounds.count - 1]).cleaned), first <= last else {
                throw TaskImportError.invalidSelection
            }
            guard last - first < selectionLimit else { throw TaskImportError.selectionTooLarge }
            for number in first...last where seen.insert(number).inserted {
                guard numbers.count < selectionLimit else { throw TaskImportError.selectionTooLarge }
                numbers.append(number)
            }
        }
        guard !numbers.isEmpty else { throw TaskImportError.invalidSelection }
        return numbers
    }

    public static func tasks(in document: String, selecting numbers: [Int], topic: String,
                             allowBareNumbers: Bool = false) throws -> [PracticeTask] {
        guard !numbers.isEmpty else { throw TaskImportError.invalidSelection }
        return try matches(in: document.components(separatedBy: .newlines), selecting: numbers,
                           topic: topic, allowBareNumbers: allowBareNumbers).map(\.task)
    }

    struct Match {
        let task: PracticeTask
        let range: Range<Int>
    }

    private struct Body {
        let text: [String]
        let range: Range<Int>
    }

    static func matches(in rawLines: [String], selecting numbers: [Int], topic: String,
                        allowBareNumbers: Bool, bareHeadingLines: Set<Int>? = nil) throws -> [Match] {
        let lines = rawLines.map { $0.replacingOccurrences(of: "\u{FFFC}", with: "").cleaned }
        let keyIndex = lines.firstIndex { match(answerHeading, $0) != nil || match(evaluationHeading, $0) != nil }
        let questions = lines.prefix(keyIndex ?? lines.count)
        let key: [Int: Set<String>] = keyIndex.map { index in
            let trailing = lines.suffix(from: index)
            if match(evaluationHeading, lines[index]) != nil {
                var answers: [Int: Set<String>] = [:]
                for row in trailing {
                    if let (number, answer) = header(evaluationRow, row) {
                        answers[number, default: []].insert(answer)
                    }
                }
                return answers
            }
            return answerKey(Array(trailing))
        } ?? [:]
        var occurrences = taskBodies(questions)
        if allowBareNumbers {
            let bare = bareTaskBodies(questions, eligible: bareHeadingLines)
            if bare.count > occurrences.count {
                occurrences = bare
            } else {
                for (number, bodies) in bare where occurrences[number] == nil {
                    occurrences[number] = bodies
                }
            }
        }
        let selection = numbers.isEmpty ? occurrences.keys.sorted() : numbers
        guard !selection.isEmpty else { throw TaskImportError.noNumberedTasks }
        var missing: [Int] = []
        var repeated: [Int] = []
        var results: [Match] = []
        var seen: Set<Int> = []

        for number in selection where seen.insert(number).inserted {
            let bodies = occurrences[number] ?? []
            if bodies.count > 1 && !numbers.isEmpty {
                repeated.append(number)
                continue
            }
            if bodies.isEmpty { missing.append(number) }
            for (index, body) in bodies.enumerated() {
                let fields = taskFields(body.text)
                guard !fields.prompt.isEmpty else {
                    missing.append(number)
                    continue
                }
                let answers = key[number] ?? []
                if fields.answer.isEmpty && answers.count > 1 && !numbers.isEmpty {
                    repeated.append(number)
                    continue
                }
                let keyAnswer = bodies.count == 1 && answers.count == 1 ? answers.first : nil
                let suffix = bodies.count > 1 ? " · вариант \(index + 1)" : ""
                var task = PracticeTask(topic: topicName(topic), kind: "№\(number)\(suffix)", prompt: fields.prompt,
                                        answer: fields.answer.isEmpty ? keyAnswer ?? "" : fields.answer,
                                        solution: fields.solution)
                if answers.isEmpty { task.fillMissingAnswerLocally() }
                results.append(Match(task: task, range: body.range))
            }
        }
        guard missing.isEmpty && repeated.isEmpty else {
            throw TaskImportError.unresolved(missing: missing, repeated: repeated)
        }
        return results
    }

    static func topicName(_ topic: String) -> String {
        topic.cleaned.isEmpty ? "Без темы" : topic.cleaned
    }

    static func isAnswerOrSolution(_ line: String) -> Bool {
        fieldLabel.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))?.range.location == 0
    }

    static func hasInlineAnswerOrSolution(_ line: String) -> Bool {
        let text = line.cleaned
        return fieldLabel.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            .map { $0.range.location > 0 } ?? false
    }

    static func startsQuestion(_ line: String) -> Bool {
        header(explicitHeader, line) != nil || header(looseHeader, line) != nil
            || positiveNumber(line).map { $0 <= 100 } == true
    }

    public static func read(_ file: URL) throws -> String {
        try readDocument(file).text()
    }

    public static func readDocument(_ file: URL, preferredSubject: String = "") throws -> TaskImportDocument {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        if file.pathExtension.lowercased() == "zip" {
            let entry = try TaskImportZIP.pdf(from: file, preferredSubject: preferredSubject)
            var document = try readPDF(entry.data)
            document.containedFileName = entry.name
            return document
        }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        switch file.pathExtension.lowercased() {
        case "txt", "text":
            let decoded: String?
            if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
                decoded = String(data: data, encoding: .utf16)
            } else {
                decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251)
            }
            guard let decoded, !decoded.contains("\0") else { throw TaskImportError.unreadableFile }
            return TaskImportDocument(source: .text(decoded.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")), attachments: [:]))
        case "docx":
            let document = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                                                  documentAttributes: nil)
            var attachments: [Int: [Data]] = [:]
            let text = document.string as NSString
            document.enumerateAttribute(.attachment, in: NSRange(location: 0, length: document.length)) { value, range, _ in
                guard let attachment = value as? NSTextAttachment,
                      let bytes = attachment.fileWrapper?.regularFileContents ?? attachment.image?.tiffRepresentation,
                      let image = TaskImportDocument.image(from: bytes),
                      let jpeg = TaskImportDocument.jpeg(image) else { return }
                let prefix = text.substring(to: range.location)
                let line = prefix.components(separatedBy: .newlines).count - 1
                attachments[line, default: []].append(jpeg)
            }
            return TaskImportDocument(source: .text(document.string, attachments: attachments))
        case "pdf":
            return try readPDF(data)
        default:
            if let image = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(image) > 0 {
                return TaskImportDocument(source: .image(data))
            }
            if UTType(filenameExtension: file.pathExtension)?.conforms(to: .image) == true {
                throw TaskImportError.unreadableFile
            }
            throw TaskImportError.unsupportedFormat
        }
    }

    private static func readPDF(_ data: Data) throws -> TaskImportDocument {
        guard let document = PDFDocument(data: data) else { throw TaskImportError.unreadableFile }
        guard !document.isLocked else { throw TaskImportError.lockedPDF }
        guard document.pageCount > 0 else { throw TaskImportError.unreadableFile }
        return TaskImportDocument(source: .pdf(data, pageCount: document.pageCount))
    }

    private struct Header {
        let line: Int
        let number: Int
        let content: String
        let isExplicit: Bool
    }

    private static let explicitHeader = regex(#"^(?:\(\h*)?(?:(?:задание|задача|вопрос|question|task|problem)\h*(?:№|#|no\.?)?\h*|[№#]\h*)([0-9]+)(?:\h*[.):\-–—](?![0-9])\h*|\h+|$)(.*)$"#)
    private static let zeroPaddedHeading = regex(#"^0+[1-9][0-9]*[.)]"#)
    private static let looseHeader = regex(#"^([0-9]+)(?:[.)](?![0-9])\h*|:\h*|\h+[-–—]\h+)(.*)$"#)
    private static let keyRow = regex(#"^(?:[№#]\h*)?([0-9]+)(?:\h*(?:[):]|\.(?![0-9]))\h*|\h*[-–—]\h+|\h+)(.*)$"#)
    private static let answerHeading = regex(#"^(?:краткие\h+ответы|ответы(?:\h+(?:к\h+заданиям|на\h+задания))?|answer\h+key|answers)(?:\h*:\h*(.*)|\h*\.?)$"#)
    private static let evaluationHeading = regex(#"^система\h+оценивания\h+экзаменационной\h+работы\b"#)
    private static let evaluationRow = regex(#"^([1-9][0-9]{0,2})\h+([\p{L}0-9−-]+(?:[\h;,.]+[0-9−-]+)*)$"#)
    private static let pageMarker = regex(#"^(?:continue|stop|(?:[0-9]+\h+)*module(?:\h+[0-9]+)*)$"#)
    private static let keySeparator = regex(#";\h*(?=(?:[№#]\h*)?[0-9]+[.):\-])"#)
    private static let fieldLabel = regex(#"(?:^|(?<=[.!?;])\h+)(ответ|решение|answer|solution)\h*[:.\-–—]\h*"#)

    private static func taskBodies(_ lines: ArraySlice<String>) -> [Int: [Body]] {
        let candidates = lines.indices.compactMap { index -> Header? in
            if let (number, content) = header(explicitHeader, lines[index]) {
                return Header(line: index, number: number, content: content, isExplicit: true)
            }
            guard let (number, content) = header(looseHeader, lines[index]) else { return nil }
            return Header(line: index, number: number, content: content, isExplicit: false)
        }
        let normalNumbers = Set(candidates.compactMap { heading in
            match(zeroPaddedHeading, lines[heading.line]) == nil ? heading.number : nil
        })
        let distinct = candidates.filter { heading in
            match(zeroPaddedHeading, lines[heading.line]) == nil || !normalNumbers.contains(heading.number)
        }
        // Explicit headings anchor the numbering. Bare numbered subparts often start at 1 again.
        var remainingAnchors = distinct.lazy.filter(\.isExplicit).makeIterator()
        var nextAnchor = remainingAnchors.next()
        var previousAnchor: Header?
        let headings = distinct.filter { candidate in
            if candidate.isExplicit {
                previousAnchor = candidate
                nextAnchor = remainingAnchors.next()
                return true
            }
            if let previousAnchor, candidate.number <= previousAnchor.number,
               !(candidate.number >= 10 && previousAnchor.number >= 100) { return false }
            if let nextAnchor, candidate.number >= nextAnchor.number { return false }
            return true
        }

        return taskBodies(lines, headedBy: headings)
    }

    private static func bareTaskBodies(_ lines: ArraySlice<String>, eligible: Set<Int>?) -> [Int: [Body]] {
        let nonempty = lines.indices.filter { !lines[$0].isEmpty }
        var excluded: Set<Int> = []
        var candidates: [Int: Int] = [:]
        for (offset, index) in nonempty.enumerated() {
            let line = lines[index]
            if match(pageMarker, line) != nil ||
                line.lowercased().hasPrefix("unauthorized copying or reuse of any part of this page") {
                excluded.insert(index)
                continue
            }
            guard eligible?.contains(index) != false, let number = positiveNumber(line),
                  offset + 1 < nonempty.count else { continue }
            let next = lines[nonempty[offset + 1]]
            if match(pageMarker, next) != nil {
                excluded.insert(index)
            } else if offset > 0, match(pageMarker, lines[nonempty[offset - 1]]) != nil,
                      positiveNumber(next) != nil {
                excluded.insert(index)
            } else if next.contains(where: \.isLetter) {
                candidates[index] = number
            }
        }
        guard !candidates.isEmpty else { return [:] }

        let headings = lines.indices.compactMap { index -> Header? in
            guard let number = candidates[index] else { return nil }
            return Header(line: index, number: number, content: "", isExplicit: false)
        }
        return taskBodies(lines, headedBy: headings, excluding: excluded)
    }

    private static func taskBodies(_ lines: ArraySlice<String>, headedBy headings: [Header],
                                   excluding excluded: Set<Int> = []) -> [Int: [Body]] {
        var result: [Int: [Body]] = [:]
        for (offset, heading) in headings.enumerated() {
            let end = offset + 1 < headings.count ? headings[offset + 1].line : lines.endIndex
            let content = [heading.content] + ((heading.line + 1)..<end).compactMap { index in
                excluded.contains(index) ? nil : lines[index]
            }
            result[heading.number, default: []].append(Body(text: content, range: heading.line..<end))
        }
        return result
    }

    private static func answerKey(_ lines: [String]) -> [Int: Set<String>] {
        guard let first = lines.first, let heading = match(answerHeading, first) else { return [:] }
        let entries = [heading[0]] + lines.dropFirst()
        var answers: [Int: Set<String>] = [:]
        var number: Int?
        var content: [String] = []

        func finishEntry() {
            let answer = content.joined(separator: "\n").cleaned
            if let number, !answer.isEmpty { answers[number, default: []].insert(answer) }
        }

        for entry in entries {
            let separated = keySeparator.stringByReplacingMatches(in: entry, range: NSRange(entry.startIndex..., in: entry),
                                                                    withTemplate: "\n")
            for line in separated.components(separatedBy: "\n") {
                if let (next, answer) = header(keyRow, line) {
                    finishEntry()
                    number = next
                    content = [answer]
                } else if !line.isEmpty {
                    content.append(line)
                }
            }
        }
        finishEntry()
        return answers
    }

    private enum Field: String {
        case prompt, answer, solution, discard
    }

    private static func taskFields(_ lines: [String]) -> (prompt: String, answer: String, solution: String) {
        var fields: [Field: [String]] = [:]
        var active = Field.prompt
        for line in lines {
            let labels = fieldLabel.matches(in: line, range: NSRange(line.startIndex..., in: line))
            var start = line.startIndex
            for label in labels {
                guard let range = Range(label.range, in: line),
                      let name = Range(label.range(at: 1), in: line) else { continue }
                if start < range.lowerBound {
                    fields[active, default: []].append(String(line[start..<range.lowerBound]))
                }
                let isAnswer = ["ответ", "answer"].contains(line[name].lowercased())
                let suffix = String(line[range.upperBound...]).cleaned
                active = isAnswer ? (isAnswerPlaceholder(suffix) ? .discard : .answer) : .solution
                start = range.upperBound
            }
            if start < line.endIndex || labels.isEmpty {
                let remaining = String(line[start...])
                if active == .answer && isAnswerPlaceholder(remaining.cleaned) {
                    active = .discard
                }
                if active != .discard { fields[active, default: []].append(remaining) }
            }
        }
        let answer = fields[.answer]?.joined(separator: "\n").cleaned ?? ""
        let isBlank = isAnswerPlaceholder(answer)
        return (fields[.prompt]?.joined(separator: "\n").cleaned ?? "",
                isBlank ? "" : answer, fields[.solution]?.joined(separator: "\n").cleaned ?? "")
    }

    private static func isAnswerPlaceholder(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isWhitespace || "_.…".contains($0) }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }

    private static func match(_ regex: NSRegularExpression, _ line: String) -> [String]? {
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: line).map { String(line[$0]) } ?? ""
        }
    }

    private static func header(_ regex: NSRegularExpression, _ line: String) -> (Int, String)? {
        guard let fields = match(regex, line), let number = positiveNumber(fields[0]) else { return nil }
        return (number, fields[1])
    }

    private static func positiveNumber(_ text: String) -> Int? {
        guard text.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(text), number > 0 else { return nil }
        return number
    }
}
