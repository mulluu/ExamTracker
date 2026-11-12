import Foundation

enum TaskImportZIP {
    enum Error: LocalizedError {
        case unreadableArchive
        case archiveTooLarge
        case noTaskPDF
        case ambiguousPDFs

        var errorDescription: String? {
            switch self {
            case .unreadableArchive:
                "Не удалось прочитать ZIP-архив. Проверьте, что он открывается на Mac."
            case .archiveTooLarge:
                "ZIP-архив или PDF внутри него слишком большой. Импортируйте PDF меньшего размера."
            case .noTaskPDF:
                "В ZIP-архиве не найден подходящий PDF с заданиями."
            case .ambiguousPDFs:
                "В ZIP-архиве несколько подходящих PDF. Выберите нужный вариант после распаковки архива."
            }
        }
    }

    private enum Part {
        case profile, basic, written, oral

        var opposite: Self {
            switch self {
            case .profile: .basic
            case .basic: .profile
            case .written: .oral
            case .oral: .written
            }
        }

        static func find(in words: [Substring]) -> Self? {
            if words.contains(where: { $0.hasPrefix("проф") || $0 == "profile" }) { return .profile }
            if words.contains(where: { $0.hasPrefix("баз") || $0 == "basic" }) { return .basic }
            if words.contains(where: { $0.hasPrefix("письм") || $0 == "пч" || $0 == "written" }) { return .written }
            if words.contains(where: { $0.hasPrefix("устн") || $0 == "уст" || $0 == "уч" || $0 == "oral" }) { return .oral }
            if words.contains(where: { $0 == "ая" || $0.hasPrefix("англ") || $0.hasPrefix("angl") }) {
                if words.contains("п") || words.contains("p") { return .written }
                if words.contains("у") || words.contains("u") { return .oral }
            }
            return nil
        }
    }

    static func pdf(from file: URL, preferredSubject: String) throws -> (name: String, data: Data) {
        let info = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard info.isRegularFile == true, let size = info.fileSize else { throw Error.unreadableArchive }
        guard size <= 128 * 1_024 * 1_024 else { throw Error.archiveTooLarge }

        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let signature = try handle.read(upToCount: 4)
        guard signature == Data([0x50, 0x4B, 0x03, 0x04]) || signature == Data([0x50, 0x4B, 0x05, 0x06]) else {
            throw Error.unreadableArchive
        }

        // macOS's bsdtar preserves Cyrillic filenames in the official ZIPs.
        let entries = try tar(["-tf", file.path], limit: 1_024 * 1_024)
        guard let paths = String(data: entries, encoding: .utf8) else { throw Error.unreadableArchive }
        var candidates = paths.split(separator: "\n").map(String.init).filter(isTaskPDF)
        let subject = words(in: preferredSubject)
        if let requested = Part.find(in: subject) {
            let matching = candidates.filter { Part.find(in: words(in: $0)) == requested }
            candidates = matching.isEmpty
                ? candidates.filter { Part.find(in: words(in: $0)) != requested.opposite }
                : matching
        } else if subject.contains(where: { $0.hasPrefix("английск") || $0 == "english" }) {
            let written = candidates.filter { Part.find(in: words(in: $0)) == .written }
            if !written.isEmpty { candidates = written }
        }

        let variants = candidates.filter {
            words(in: $0).contains { $0.hasPrefix("демо") || $0.hasPrefix("вариант") || $0 == "demo" || $0 == "variant" }
        }
        if !variants.isEmpty { candidates = variants }
        guard let entry = candidates.first else { throw Error.noTaskPDF }
        guard candidates.count == 1 else { throw Error.ambiguousPDFs }

        let data = try tar(["-xOf", file.path, "--", entry], limit: 64 * 1_024 * 1_024)
        guard data.starts(with: "%PDF-".utf8) else { throw Error.unreadableArchive }
        return ((entry as NSString).lastPathComponent, data)
    }

    private static func words(in name: String) -> [Substring] {
        name.lowercased().split { !$0.isLetter && !$0.isNumber }
    }

    private static func isTaskPDF(_ name: String) -> Bool {
        guard name.lowercased().hasSuffix(".pdf"),
              name.rangeOfCharacter(from: CharacterSet(charactersIn: "*?[\\\0")) == nil,
              !name.split(separator: "/").contains(where: { $0 == "__MACOSX" || $0.hasPrefix(".") }) else {
            return false
        }
        let supporting = ["кодиф", "специфик", "критери", "ответ", "инструкц", "скрипт", "codif", "spec", "answers", "readme"]
        return !words(in: name).contains { word in
            word == "спец" || supporting.contains { word.hasPrefix($0) }
        }
    }

    private static func tar(_ arguments: [String], limit: Int) throws -> Data {
        try Task.checkCancellation()
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/bsdtar")
        process.environment = ["LC_ALL": "en_US.UTF-8"]
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardOutput = output
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }

        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            try Task.checkCancellation()
            guard chunk.count <= limit - data.count else { throw Error.archiveTooLarge }
            data.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Error.unreadableArchive }
        return data
    }
}
