import Foundation
import Testing
@testable import ExamCore

struct TaskImportZIPTests {
    @Test func choosesProfileMathAndExcludesSupportingPDFs() throws {
        try withZIP([
            "МА-11 ЕГЭ 2027 ДЕМО_базовый.pdf": "base",
            "МА-11 ЕГЭ 2027 ДЕМО_профильный.pdf": "profile",
            "МА-11 ЕГЭ 2027 СПЕЦ_профильный.pdf": "spec",
            "МА-11 ЕГЭ 2027 КОДИФ.pdf": "codifier"
        ]) { file in
            let profile = try TaskImportZIP.pdf(from: file, preferredSubject: "ЕГЭ · Профильная математика")
            #expect(profile.name == "МА-11 ЕГЭ 2027 ДЕМО_профильный.pdf")
            #expect(profile.data == Data("%PDF-1.4\nprofile".utf8))
            let base = try TaskImportZIP.pdf(from: file, preferredSubject: "ЕГЭ · Базовая математика")
            #expect(base.data == Data("%PDF-1.4\nbase".utf8))
            #expect(throws: TaskImportZIP.Error.ambiguousPDFs) {
                try TaskImportZIP.pdf(from: file, preferredSubject: "ЕГЭ · Математика")
            }
        }
    }

    @Test func defaultsToWrittenEnglishAndHonorsAnExplicitOralTitle() throws {
        try withZIP([
            "АЯ-11 ЕГЭ 2027 ДЕМО_ПЧ.pdf": "written",
            "АЯ-11 ЕГЭ 2027 ДЕМО_УЧ.pdf": "oral",
            "ИНЯЗ-11 ЕГЭ 2027 СПЕЦ.pdf": "spec"
        ]) { file in
            let written = try TaskImportZIP.pdf(from: file, preferredSubject: "ЕГЭ · Английский язык")
            #expect(written.data == Data("%PDF-1.4\nwritten".utf8))
            let oral = try TaskImportZIP.pdf(from: file, preferredSubject: "ЕГЭ · Английский язык · Устная часть")
            #expect(oral.data == Data("%PDF-1.4\noral".utf8))
        }
    }

    @Test func choosesWrittenPartFromOpenVariant() throws {
        try withZIP([
            "английский п 2026.pdf": "written",
            "английский у 2026.pdf": "oral",
            "Скрипт Открытый вариант ЕГЭ 2026.pdf": "transcript"
        ]) { file in
            let result = try TaskImportZIP.pdf(from: file, preferredSubject: "ЕГЭ · Английский язык")
            #expect(result.data == Data("%PDF-1.4\nwritten".utf8))
        }
    }

    @Test func includesDirectZIPsForSupportedFIPISubjects() {
        #expect(ExamPreset.ege.count == 16)
        for preset in ExamPreset.ege {
            let sources = OfficialSources.sources(for: Exam(name: preset.name))
            let archives = sources.filter(\.isArchive)
            #expect(archives.count == 2)
            #expect(archives.allSatisfy { $0.url.host == "doc.fipi.ru" && $0.url.pathExtension == "zip" })
        }
    }

    @Test func includesPrintableOfficialMaterialsForInternationalPresets() {
        #expect(ExamPreset.international.map(\.maximum) == [9, 9, 6, 1600])
        for preset in ExamPreset.international {
            let sources = OfficialSources.sources(for: Exam(name: preset.name))
            #expect(sources.contains { $0.isPDF && $0.url.pathExtension == "pdf" })
        }
    }

    @Test func selectsTheWrittenPartOfAChineseOpenVariant() throws {
        try withZIP([
            "Китайский п 2026.pdf": "written",
            "Китайский у 2026.pdf": "oral",
            "Скрипт Китайский 2026.pdf": "transcript"
        ]) { file in
            let written = try TaskImportZIP.pdf(from: file, preferredSubject: "ЕГЭ · Китайский язык")
            #expect(written.data == Data("%PDF-1.4\nwritten".utf8))
            let oral = try TaskImportZIP.pdf(from: file, preferredSubject: "ЕГЭ · Китайский язык · Устная часть")
            #expect(oral.data == Data("%PDF-1.4\noral".utf8))
        }
    }

    @Test func selectsBasicMathFromTheCompactOpenVariantFilename() throws {
        try withZIP(["МАпроф.pdf": "profile", "МАбаз.pdf": "basic"]) { file in
            let result = try TaskImportZIP.pdf(from: file, preferredSubject: "ЕГЭ · Базовая математика")
            #expect(result.data == Data("%PDF-1.4\nbasic".utf8))
        }
    }

    private func withZIP(_ files: [String: String], perform check: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        for (name, content) in files {
            try Data("%PDF-1.4\n\(content)".utf8).write(to: folder.appending(path: name))
        }
        let archive = folder.appending(path: "variant.zip")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/zip")
        process.currentDirectoryURL = folder
        process.arguments = ["-q", archive.path] + files.keys.sorted()
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        try check(archive)
    }
}
