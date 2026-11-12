import Foundation

public struct OfficialSource: Identifiable, Sendable {
    public let organization: String
    public let title: String
    public let url: URL
    public let isPDF: Bool

    public var id: URL { url }
    public var isArchive: Bool { url.pathExtension.lowercased() == "zip" }

    fileprivate init(_ organization: String, _ title: String, _ url: String, isPDF: Bool = false) {
        self.organization = organization
        self.title = title
        self.url = URL(string: url)!
        self.isPDF = isPDF
    }
}

public enum OfficialSources {
    public static func sources(for exam: Exam) -> [OfficialSource] {
        let words = Set(exam.name.lowercased().split { !$0.isLetter && !$0.isNumber })

        if words.contains("егэ") || words.contains("ege") {
            return fipiDownloads(for: words) + [
                OfficialSource("ФИПИ", "Открытые варианты КИМ ЕГЭ",
                               "https://fipi.ru/ege/otkrytyy-bank-zadaniy-ege/otkrytyye-varianty-kim-ege"),
                OfficialSource("ФИПИ", "Демоверсии ЕГЭ по предметам и годам",
                               "https://fipi.ru/ege/demoversii-specifikacii-kodifikatory"),
                OfficialSource("ФИПИ", "Открытый банк заданий ЕГЭ",
                               "https://fipi.ru/ege/otkrytyy-bank-zadaniy-ege")
            ]
        }

        if words.contains("огэ") || words.contains("oge") {
            return [
                OfficialSource("ФИПИ", "Демоверсии ОГЭ по предметам и годам",
                               "https://fipi.ru/oge/demoversii-specifikacii-kodifikatory"),
                OfficialSource("ФИПИ", "Открытый банк заданий ОГЭ",
                               "https://fipi.ru/oge/otkrytyy-bank-zadaniy-oge")
            ]
        }

        if words.contains("psat") {
            return [OfficialSource("College Board", "Бумажные варианты PSAT",
                                   "https://satsuite.collegeboard.org/practice/practice-tests/paper")]
        }

        if words.contains("sat"), words.isDisjoint(with: ["subject", "subjects", "ii"]) {
            return [
                OfficialSource("College Board", "Полные варианты SAT для печати",
                               "https://satsuite.collegeboard.org/practice/practice-tests/paper"),
                OfficialSource("College Board", "SAT Practice Test 11 для печати",
                               "https://satsuite.collegeboard.org/media/pdf/sat-practice-test-11-digital.pdf", isPDF: true),
                OfficialSource("College Board", "Адаптивные тесты SAT в Bluebook",
                               "https://satsuite.collegeboard.org/practice/practice-tests/bluebook")
            ]
        }

        if words.contains("ielts") {
            return ieltsSources(for: words)
        }

        if words.contains("toefl"), words.isDisjoint(with: ["itp", "essentials", "junior", "primary", "pbt"]) {
            return [
                OfficialSource("ETS", "Подготовка к TOEFL iBT",
                               "https://www.ets.org/toefl/test-takers/ibt/prepare.html"),
                OfficialSource("ETS", "TOEFL iBT Practice Test 1 для печати",
                               "https://www.ets.org/pdfs/toefl/toefl-ibt-teachers-resources-practice-test-1.pdf", isPDF: true)
            ]
        }

        if words.contains("act"), words.isDisjoint(with: ["workkeys", "preact", "aspire"]) {
            return [
                OfficialSource("ACT", "Официальные тренировочные варианты ACT",
                               "https://www.act.org/content/act/en/products-and-services/the-act/test-preparation/free-act-test-prep.html"),
                OfficialSource("ACT", "ACT Practice Test 1 для печати",
                               "https://www.act.org/content/dam/act/unsecured/documents/Preparing-for-the-ACT.pdf", isPDF: true)
            ]
        }

        return cambridgeSource(for: words).map { [$0] } ?? []
    }

    private static func fipiDownloads(for words: Set<Substring>) -> [OfficialSource] {
        let subjects: [(prefixes: [String], open: String, demo: String)] = [
            (["математ", "профмат", "math"], "Mat", "ma"),
            (["русск", "russian"], "Rus", "ru"),
            (["информат", "informatics"], "Inf", "inf"),
            (["физик", "physics"], "Fiz", "fi"),
            (["хими", "chemistry"], "Him", "hi"),
            (["биологи", "biology"], "Bio", "bi"),
            (["истори", "history"], "Ist", "is"),
            (["географ", "geography"], "Geo", "gg"),
            (["обществознан", "social"], "Ob", "ob"),
            (["литератур", "literature"], "Lit", "li"),
            (["английск", "english"], "Angl", "aya"),
            (["немец", "german"], "Nem", "nya"),
            (["француз", "french"], "Fran", "fya"),
            (["испан", "spanish"], "Isp", "iya"),
            (["китай", "chinese"], "Kit", "kya")
        ]
        guard let subject = subjects.first(where: { entry in
            words.contains { word in entry.prefixes.contains { word.hasPrefix($0) } }
        }) else { return [] }
        return [
            OfficialSource("ФИПИ", "Проект демоверсии ЕГЭ 2027",
                           "https://doc.fipi.ru/ege/demoversii-specifikacii-kodifikatory/2027/\(subject.demo)_11_2027.zip"),
            OfficialSource("ФИПИ", "Открытый вариант ЕГЭ 2026",
                           "https://doc.fipi.ru/ege/otkrytyy-bank-zadaniy-ege/otkrytyye-varianty-kim-ege/2026/\(subject.open)_1_ege2026.zip")
        ]
    }

    private static func ieltsSources(for words: Set<Substring>) -> [OfficialSource] {
        let baseURL = "https://ielts.org/take-a-test/preparation-resources/sample-test-questions"
        if words.isSuperset(of: ["life", "skills"]) {
            return [OfficialSource("IELTS", "Примеры заданий IELTS for UKVI Life Skills",
                                   baseURL + "/life-skills-sample-questions")]
        }
        let academic = OfficialSource("IELTS", "IELTS Academic Reading для печати",
                                     "https://ielts.org/cdn/Sample-tests/ielts-academic-reading-sample-tasks-2023.pdf",
                                     isPDF: true)
        let general = OfficialSource("IELTS", "IELTS General Training Reading для печати",
                                    "https://ielts.org/cdn/Sample-tests/ielts-general-reading-sample-tasks-2023.pdf",
                                    isPDF: true)
        if words.contains("academic") {
            return [academic, OfficialSource("IELTS", "Примеры заданий IELTS Academic", baseURL + "/academic-test")]
        }
        if words.contains("general") {
            return [general, OfficialSource("IELTS", "Примеры заданий IELTS General Training", baseURL + "/general-training-test")]
        }
        return [academic, general, OfficialSource("IELTS", "Примеры заданий IELTS по формату экзамена", baseURL)]
    }

    private static func cambridgeSource(for words: Set<Substring>) -> OfficialSource? {
        guard words.isDisjoint(with: ["linguaskill", "celta", "delta", "tkt", "international", "igcse", "gcse"]) else {
            return nil
        }
        let qualifications = [
            (level: "a2", name: "key", acronym: "ket", title: "A2 Key", path: "key/"),
            (level: "b1", name: "preliminary", acronym: "pet", title: "B1 Preliminary", path: "preliminary/"),
            (level: "b2", name: "first", acronym: "fce", title: "B2 First", path: "first/"),
            (level: "c1", name: "advanced", acronym: "cae", title: "C1 Advanced", path: "advanced/"),
            (level: "c2", name: "proficiency", acronym: "cpe", title: "C2 Proficiency", path: "proficiency/")
        ]
        let baseURL = "https://www.cambridgeenglish.org/exams-and-tests/qualifications/"
        if let qualification = qualifications.first(where: {
            words.contains(Substring($0.acronym)) || words.isSuperset(of: [Substring($0.level), Substring($0.name)])
        }) {
            return OfficialSource("Cambridge English", "Пробные варианты \(qualification.title)",
                                  baseURL + qualification.path + "preparation/")
        }
        guard words.contains("cambridge"), words.count == 1 || words.contains("english") else { return nil }
        return OfficialSource("Cambridge English", "Подготовка к экзаменам Cambridge English по уровням",
                              baseURL + "preparation/")
    }
}
