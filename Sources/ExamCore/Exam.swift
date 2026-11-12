import Foundation

public struct Exam: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var maximum: Double
    public var target: Double
    public var primaryMaximum: Double?
    public var topics: [String]
    public var attempts: [Attempt]
    public var practice: [PracticeSet]
    public var lessons: [ExamLesson]?

    public init(name: String, maximum: Double = 100, target: Double = 70, topics: [String] = [],
                attempts: [Attempt] = [], practice: [PracticeSet] = [], primaryMaximum: Double? = nil) {
        self.name = name
        self.maximum = maximum
        self.target = target
        self.primaryMaximum = primaryMaximum
        self.topics = topics
        self.attempts = attempts
        self.practice = practice
    }

    public var examAttempts: [Attempt] {
        attempts.filter { !$0.isPractice }.sorted { $0.date < $1.date }
    }

    public var topicStats: [TopicStat] {
        let recorded = attempts.flatMap(\.scores).filter { $0.earned != nil && $0.maximum > 0 && !$0.topic.cleaned.isEmpty }
        let groups = Dictionary(grouping: recorded) { $0.topic.cleaned.lowercased() }
        return groups.map { key, scores in
            let earned = scores.compactMap(\.earned).reduce(0, +)
            let maximum = scores.map(\.maximum).reduce(0, +)
            let ratio: Double
            if maximum.isFinite {
                ratio = earned / maximum
            } else {
                let scale = scores.map(\.maximum).max() ?? 1
                let scaledEarned = scores.compactMap(\.earned).reduce(0) { $0 + $1 / scale }
                let scaledMaximum = scores.reduce(0) { $0 + $1.maximum / scale }
                ratio = scaledEarned / scaledMaximum
            }
            return TopicStat(id: key,
                      name: topics.first { $0.cleaned.lowercased() == key } ?? scores[0].topic.cleaned,
                      earned: earned, maximum: maximum, count: scores.count, ratio: ratio)
        }.sorted {
            if $0.ratio == $1.ratio { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.ratio < $1.ratio
        }
    }

    public static var starter: Exam {
        Exam(name: "ЕГЭ · Профильная математика",
             topics: ["Планиметрия", "Стереометрия", "Теория вероятностей", "Уравнения",
                      "Функции и производные", "Неравенства", "Экономические задачи"],
             practice: [PracticeSet(title: "Разминка по геометрии", tasks: [
                PracticeTask(topic: "Планиметрия", kind: "Площадь", prompt: "Найдите площадь треугольника с основанием 12 и высотой 7, опущенной на это основание.", answer: "42", solution: "Площадь равна половине произведения основания на высоту: 12 × 7 ÷ 2 = 42.", maximum: 1),
                PracticeTask(topic: "Стереометрия", kind: "Объём", prompt: "Найдите объём конуса с радиусом основания 3 и высотой 4.", answer: "12π", solution: "V = πr²h ÷ 3 = π × 9 × 4 ÷ 3 = 12π.", maximum: 1)
             ])])
    }
}

public struct TopicStat: Identifiable, Encodable, Sendable {
    public let id: String
    public let name: String
    public let earned: Double
    public let maximum: Double
    public let count: Int
    public let ratio: Double

    enum CodingKeys: String, CodingKey {
        case name, count, ratio
    }
}

public struct TaskScore: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var topic: String
    public var earned: Double?
    public var maximum: Double
    public var note: String
    public var question: String?
    public var response: String?
    public var expectedAnswer: String?

    public init(topic: String, earned: Double?, maximum: Double, note: String = "",
                question: String? = nil, response: String? = nil, expectedAnswer: String? = nil) {
        self.topic = topic
        self.earned = earned
        self.maximum = maximum
        self.note = note
        self.question = question
        self.response = response
        self.expectedAnswer = expectedAnswer
    }
}

public struct ExamScore: Codable, Sendable {
    public let earned: Double
    public let maximum: Double
    public var ratio: Double { earned / maximum }

    public init(earned: Double, maximum: Double) throws {
        guard maximum.isFinite, maximum > 0, earned.isFinite, (0...maximum).contains(earned) else {
            throw ExamError.invalidScore
        }
        self.earned = earned
        self.maximum = maximum
    }
}

public struct Attempt: Identifiable, Codable, Sendable {
    public var id = UUID()
    public let title: String
    public let date: Date
    public let earned: Double
    public let maximum: Double
    public let scores: [TaskScore]
    public let isPractice: Bool
    public private(set) var primaryScore: ExamScore?
    private var primaryOnly: Bool?
    public var hasFinalScore: Bool { !isPractice && primaryOnly != true }

    public init(title: String, date: Date = .now, earned: Double, maximum: Double,
                scores: [TaskScore] = [], primaryScore: ExamScore? = nil) throws {
        guard !title.cleaned.isEmpty, earned.isFinite, maximum.isFinite, maximum > 0,
              (0...maximum).contains(earned) else { throw ExamError.invalidScore }
        try Self.validate(scores)
        self.title = title.cleaned
        self.date = date
        self.earned = earned
        self.maximum = maximum
        self.scores = scores
        self.isPractice = false
        self.primaryScore = primaryScore
    }

    public init(title: String, date: Date = .now, primaryScore: ExamScore, scores: [TaskScore] = []) throws {
        try self.init(title: title, date: date, earned: primaryScore.earned, maximum: primaryScore.maximum,
                      scores: scores, primaryScore: primaryScore)
        primaryOnly = true
    }

    public init(title: String, date: Date = .now, scores: [TaskScore]) throws {
        try Self.validate(scores)
        let marked = scores.filter { $0.earned != nil }
        guard !title.cleaned.isEmpty,
              scores.contains(where: { $0.earned != nil || !($0.response ?? "").cleaned.isEmpty || !$0.note.cleaned.isEmpty })
        else { throw ExamError.invalidScore }
        self.title = title.cleaned
        self.date = date
        let total = marked.map(\.maximum).reduce(0, +)
        guard total.isFinite else { throw ExamError.invalidScore }
        self.earned = marked.compactMap(\.earned).reduce(0, +)
        self.maximum = total
        self.scores = scores
        self.isPractice = true
    }

    private static func validate(_ scores: [TaskScore]) throws {
        for score in scores {
            guard score.maximum.isFinite, score.maximum > 0, !score.topic.cleaned.isEmpty else {
                throw ExamError.invalidScore
            }
            if let earned = score.earned, !earned.isFinite || !(0...score.maximum).contains(earned) {
                throw ExamError.invalidScore
            }
        }
    }
}

public enum PracticeAnswerOrigin: String, Codable, Sendable {
    case localSolution, acceptedSuggestion
}

public struct PracticeTask: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var topic: String
    public var kind: String
    public var prompt: String
    public var answer: String
    public var solution: String
    public var maximum: Double
    public var illustration: Data?
    public var sourceFragments: [Data]?
    public var reviewFragments: [Data]?
    public var generatedIllustration: Bool?
    public var answerOrigin: PracticeAnswerOrigin?
    public var diagramDescription: String?
    public var diagramInQuestion: Bool?
    public var diagramIsAutomatic: Bool?
    public var sourceInQuestion: Bool?
    public var illustrationInQuestion: Bool?

    public var showsIllustrationInQuestion: Bool { illustration?.isEmpty == false }

    public var showsSourceInQuestion: Bool {
        guard sourceFragments?.isEmpty == false else { return false }
        return sourceInQuestion ?? (!kind.hasPrefix("Страница ") && solution.cleaned.isEmpty)
    }

    public var showsDiagramInQuestion: Bool {
        if diagramIsAutomatic == true, ProblemDiagram.requiresConstruction(prompt) { return false }
        return diagramInQuestion == true
    }

    public init(topic: String = "", kind: String = "", prompt: String = "", answer: String = "",
                solution: String = "", maximum: Double = 1) {
        self.topic = topic
        self.kind = kind
        self.prompt = prompt
        self.answer = answer
        self.solution = solution
        self.maximum = maximum
    }

    @discardableResult
    public mutating func fillMissingAnswerLocally() -> Bool {
        guard answer.cleaned.isEmpty, solution.cleaned.isEmpty,
              let solved = LocalPracticeSolver.solve(self) else { return false }
        answer = solved.answer
        solution = solved.explanation
        answerOrigin = .localSolution
        return true
    }

    public var isValid: Bool {
        !topic.cleaned.isEmpty && !prompt.cleaned.isEmpty && maximum.isFinite && maximum > 0
    }
}

public struct PracticeSet: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var title: String
    public var tasks: [PracticeTask]
    public var sourceURL: URL?

    public init(title: String, tasks: [PracticeTask]) {
        self.title = title
        self.tasks = tasks
    }

    public static func validateGenerated(_ tasks: [PracticeTask], count: Int) throws {
        let prompts = Set(tasks.map { $0.prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased() })
        guard count > 0, tasks.count == count, prompts.count == count,
              tasks.allSatisfy({ $0.isValid && !$0.answer.cleaned.isEmpty && !$0.solution.cleaned.isEmpty }) else {
            throw ExamError.invalidGeneration
        }
    }
}

public struct ExamStorage {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> [Exam] {
        do {
            return try JSONDecoder().decode([Exam].self, from: Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            return [Exam.starter]
        }
    }

    public func save(_ exams: [Exam]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(exams).write(to: url, options: .atomic)
    }
}

public enum ExamError: LocalizedError {
    case invalidScore, invalidGeneration, emptyResponse, noModel, server(String)

    public var errorDescription: String? {
        switch self {
        case .invalidScore: "Проверьте название, темы и баллы. Балл должен быть от нуля до указанного максимума."
        case .invalidGeneration: "Модель вернула неполный набор или повторила задания. Попробуйте уменьшить число заданий и повторить."
        case .emptyResponse: "Модель вернула пустой ответ. Попробуйте другую модель или повторите запрос."
        case .noModel: "Откройте настройки Ollama и выберите установленную модель."
        case .server(let message): message
        }
    }
}

public extension String {
    var cleaned: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var scoreValue: Double? {
        guard let number = Double(cleaned.replacingOccurrences(of: ",", with: ".")), number.isFinite else { return nil }
        return number
    }
}
