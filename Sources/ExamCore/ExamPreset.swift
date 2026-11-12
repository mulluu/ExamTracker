import Foundation

public struct ExamPreset: Identifiable, Sendable {
    public let name: String
    public let maximum: Double
    public let target: Double
    public let topics: [String]
    public var id: String { name }

    private init(_ name: String, maximum: Double = 100, target: Double = 70, topics: [String] = []) {
        self.name = name
        self.maximum = maximum
        self.target = target
        self.topics = topics
    }

    public static let ege: [Self] = [
        .init("ЕГЭ · Профильная математика", topics: Exam.starter.topics),
        .init("ЕГЭ · Базовая математика", maximum: 5, target: 4),
        .init("ЕГЭ · Русский язык"),
        .init("ЕГЭ · Информатика"),
        .init("ЕГЭ · Физика"),
        .init("ЕГЭ · Химия"),
        .init("ЕГЭ · Биология"),
        .init("ЕГЭ · История"),
        .init("ЕГЭ · География"),
        .init("ЕГЭ · Обществознание"),
        .init("ЕГЭ · Литература"),
        .init("ЕГЭ · Английский язык"),
        .init("ЕГЭ · Немецкий язык"),
        .init("ЕГЭ · Французский язык"),
        .init("ЕГЭ · Испанский язык"),
        .init("ЕГЭ · Китайский язык")
    ]

    public static let international: [Self] = [
        .init("IELTS Academic", maximum: 9, target: 7, topics: languageSkills),
        .init("IELTS General Training", maximum: 9, target: 7, topics: languageSkills),
        .init("TOEFL iBT", maximum: 6, target: 4.5, topics: languageSkills),
        .init("SAT", maximum: 1600, target: 1200, topics: ["Reading and Writing", "Math"])
    ]

    private static let languageSkills = ["Reading", "Listening", "Writing", "Speaking"]
}
