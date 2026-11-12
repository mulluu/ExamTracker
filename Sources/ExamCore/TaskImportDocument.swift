import AppKit
import CoreML
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

public struct TaskImportDocument: Sendable {
    enum Source: Sendable {
        case pdf(Data, pageCount: Int)
        case image(Data)
        case text(String, attachments: [Int: [Data]])
    }

    let source: Source
    public var containedFileName: String? = nil

    public var pageCount: Int {
        if case .pdf(_, let count) = source { return count }
        return 1
    }

    public var hasPageImages: Bool {
        if case .text = source { return false }
        return true
    }

    public func text(on selectedPages: [Int] = []) throws -> String {
        let lines = try analyze(on: selectedPages).lines
        let text = lines.map(\.text).joined(separator: "\n").cleaned
        guard !text.isEmpty else { throw TaskImportError.noText }
        return text
    }

    public func tasks(selecting numbers: [Int] = [], on selectedPages: [Int] = [], topic: String) throws -> [PracticeTask] {
        let analysis = try analyze(on: selectedPages)
        let bareHeadingLines = Set(analysis.lines.indices.filter { index in
            let line = analysis.lines[index]
            guard line.columns > 1, let box = line.box else { return true }
            return box.minX * CGFloat(line.columns) - CGFloat(line.column) < 0.15
        })
        let matches = try TaskImport.matches(in: analysis.lines.map(\.text), selecting: numbers,
                                             topic: topic, allowBareNumbers: hasPageImages,
                                             bareHeadingLines: bareHeadingLines)
        var images = analysis.images
        return try matches.map { match in
            try Task.checkCancellation()
            var task = match.task
            let context = Self.readingContext(for: match, in: analysis.lines)
            if let context {
                task.prompt = analysis.lines[context].map(\.text).joined(separator: "\n") + "\n\n" + task.prompt
            }
            let questionLines = analysis.lines[match.range].prefix { !TaskImport.isAnswerOrSolution($0.text) }
            let hasInlineKey = questionLines.contains { TaskImport.hasInlineAnswerOrSolution($0.text) }
            if let pdf = analysis.pdf {
                task.sourceFragments = try Self.fragments(for: match, context: context, in: analysis.lines, pdf: pdf, images: &images).nonEmpty
            } else if !images.isEmpty {
                task.sourceFragments = try Self.fragments(for: match, context: context, in: analysis.lines, pdf: nil, images: &images).nonEmpty
            } else {
                let split = hasInlineKey ? questionLines.startIndex : questionLines.endIndex
                task.sourceFragments = analysis.lines[match.range.lowerBound..<split].flatMap(\.attachments).nonEmpty
                task.reviewFragments = analysis.lines[split..<match.range.upperBound].flatMap(\.attachments).nonEmpty
            }
            if task.sourceFragments != nil {
                let hasContextKey = context.map { range in
                    analysis.lines[range].contains {
                        TaskImport.isAnswerOrSolution($0.text) || TaskImport.hasInlineAnswerOrSolution($0.text)
                    }
                } ?? false
                task.sourceInQuestion = !hasInlineKey && !hasContextKey
            }
            return task
        }
    }

    public func pageTasks(on selectedPages: [Int] = [], topic: String) throws -> [PracticeTask] {
        let pages = try indices(for: selectedPages)
        switch source {
        case .text(let text, let attachments):
            var task = PracticeTask(topic: TaskImport.topicName(topic), kind: "Документ", prompt: text.cleaned)
            task.updateDiagramFromCondition()
            task.sourceFragments = attachments.sorted { $0.key < $1.key }.flatMap(\.value).nonEmpty
            task.sourceInQuestion = !TaskImport.containsAnswerMaterial(text)
            guard task.isValid else { throw TaskImportError.noText }
            return [task]
        case .pdf(let data, _):
            guard let pdf = PDFDocument(data: data) else { throw TaskImportError.unreadableFile }
            return try pages.map { index in
                try Task.checkCancellation()
                guard let page = pdf.page(at: index), let image = PageRendering(page)?.image() else {
                    throw TaskImportError.unreadableFile
                }
                return try Self.pageTask(image: image, index: index, topic: topic,
                                         containsAnswers: TaskImport.containsAnswerMaterial(page.string ?? ""))
            }
        case .image(let data):
            guard let image = Self.image(from: data) else { throw TaskImportError.unreadableFile }
            return [try Self.pageTask(image: image, index: 0, topic: topic, containsAnswers: false)]
        }
    }

    private static func pageTask(image: CGImage, index: Int, topic: String, containsAnswers: Bool) throws -> PracticeTask {
        guard let data = jpeg(image) else { throw TaskImportError.unreadableFile }
        var task = PracticeTask(topic: TaskImport.topicName(topic), kind: "Страница \(index + 1)",
                                prompt: "Решите задания на приложенной странице.")
        task.sourceFragments = [data]
        task.sourceInQuestion = !containsAnswers
        return task
    }

    private func indices(for pages: [Int]) throws -> [Int] {
        guard pages.allSatisfy({ $0 > 0 && $0 <= pageCount }) else {
            throw TaskImportError.unavailablePages(pageCount: pageCount)
        }
        return pages.isEmpty ? Array(0..<pageCount) : Set(pages).sorted().map { $0 - 1 }
    }

    private struct Line {
        let text: String
        let page: Int
        let box: CGRect?
        var column = 0
        var columns = 1
        var attachments: [Data] = []
    }

    private struct Analysis {
        var lines: [Line] = []
        var images: [Int: CGImage] = [:]
        var pdf: PDFDocument?
    }

    private func analyze(on pages: [Int]) throws -> Analysis {
        let indices = try indices(for: pages)
        switch source {
        case .text(let text, let attachments):
            let lines = text.components(separatedBy: .newlines).enumerated().map { index, line in
                Line(text: line, page: 0, box: nil, attachments: attachments[index] ?? [])
            }
            return Analysis(lines: lines)
        case .image(let data):
            guard let image = Self.image(from: data) else { throw TaskImportError.unreadableFile }
            return Analysis(lines: try Self.recognize(image, page: 0), images: [0: image])
        case .pdf(let data, _):
            guard let pdf = PDFDocument(data: data) else { throw TaskImportError.unreadableFile }
            var result = Analysis(pdf: pdf)
            var recognitionFailed = false
            for index in indices {
                try Task.checkCancellation()
                guard let page = pdf.page(at: index), let render = PageRendering(page) else { continue }
                var lines = Self.nativeLines(page, transform: render.transform, canvas: render.canvas, index: index)
                if !lines.contains(where: { $0.text.contains(where: { $0.isLetter || $0.isNumber }) }),
                   let image = render.image() {
                    do {
                        lines = try Self.recognize(image, page: index)
                    } catch TaskImportError.recognitionFailed {
                        recognitionFailed = true
                    }
                }
                result.lines.append(contentsOf: Self.readingOrder(lines, landscape: render.canvas.width > render.canvas.height * 1.2))
            }
            if result.lines.isEmpty && recognitionFailed { throw TaskImportError.recognitionFailed }
            return result
        }
    }

    private static func nativeLines(_ page: PDFPage, transform: CGAffineTransform,
                                    canvas: CGRect, index: Int) -> [Line] {
        let text = (page.string ?? "") as NSString
        var lines: [Line] = []
        var offset = 0

        func line(_ input: NSRange) -> Line? {
            var start = input.location
            var end = NSMaxRange(input)
            let whitespace = CharacterSet.whitespacesAndNewlines
            while start < end, let char = UnicodeScalar(text.character(at: start)), whitespace.contains(char) {
                start += 1
            }
            while end > start, let char = UnicodeScalar(text.character(at: end - 1)), whitespace.contains(char) {
                end -= 1
            }
            guard end > start else { return nil }
            let range = NSRange(location: start, length: end - start)
            let content = text.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "").cleaned
            guard !content.isEmpty else { return nil }
            let box = page.selection(for: range)?.bounds(for: page).applying(transform)
            let normalized = box.map {
                CGRect(x: $0.minX / canvas.width, y: $0.minY / canvas.height,
                       width: $0.width / canvas.width, height: $0.height / canvas.height)
            }
            return Line(text: content, page: index, box: normalized)
        }

        while offset < text.length {
            let range = text.lineRange(for: NSRange(location: offset, length: 0))
            offset = NSMaxRange(range)
            guard let full = line(range) else { continue }
            let crossing = canvas.width > canvas.height * 1.2 && full.box.map {
                $0.minX < 0.46 && $0.maxX > 0.53
            } == true
            let firstWord = full.text.split(whereSeparator: \.isWhitespace).first.map(String.init)
            let startsWithNumber = firstWord.map { $0.count <= 3 && $0.allSatisfy(\.isNumber) } == true
            if crossing || startsWithNumber {
                let tokens = word.matches(in: text as String, range: range)
                var pieces: [Line] = []
                var start = range.location
                var previous: Line?
                for token in tokens {
                    guard let current = line(token.range), let box = current.box else { continue }
                    if let previous, let prior = previous.box {
                        let acrossColumns = crossing && prior.midX < 0.5 && box.midX >= 0.5
                            && box.minX - prior.maxX > 0.045
                        let isolatedNumber = startsWithNumber && tokens.count > 2 && previous.text == firstWord
                            && box.minX - prior.maxX > 0.018 && current.text.contains(where: \.isLetter)
                        if acrossColumns || isolatedNumber {
                            if let part = line(NSRange(location: start, length: token.range.location - start)) {
                                pieces.append(part)
                            }
                            start = token.range.location
                        }
                    }
                    previous = current
                }
                if !pieces.isEmpty, let last = line(NSRange(location: start, length: NSMaxRange(range) - start)) {
                    lines.append(contentsOf: pieces)
                    lines.append(last)
                    continue
                }
            }
            lines.append(full)
        }
        return lines
    }

    private static let word = try! NSRegularExpression(pattern: #"\S+"#)

    private static func readingOrder(_ lines: [Line], landscape: Bool) -> [Line] {
        let body = lines.filter { line in
            guard let box = line.box else { return true }
            return !(box.midY > 0.9 || box.midY < 0.10) || !isFurniture(line.text)
        }
        guard landscape else { return body }
        let left = body.filter { $0.box.map { $0.midX < 0.5 } ?? false }
        let right = body.filter { $0.box.map { $0.midX >= 0.5 } ?? false }
        let crossing = body.filter { $0.box.map { $0.minX < 0.46 && $0.maxX > 0.54 } ?? false }
        guard left.count >= 2, right.count >= 2, crossing.count * 6 < body.count else { return body }
        return [left, right].enumerated().flatMap { column, lines in
            lines.sorted { a, b in
                guard let first = a.box, let second = b.box else { return false }
                let firstRow = Int((first.midY * 140).rounded())
                let secondRow = Int((second.midY * 140).rounded())
                return firstRow == secondRow ? first.minX < second.minX : firstRow > secondRow
            }.map { line in
                var line = line
                line.column = column
                line.columns = 2
                return line
            }
        }
    }

    private static func isFurniture(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("©") || lower.hasPrefix("демонстрационный вариант егэ")
            || lower.contains("задачник егэпроф") || lower.hasPrefix("unauthorized copying")
            || lower == "continue" || lower == "stop"
    }

    private static func recognize(_ image: CGImage, page: Int) throws -> [Line] {
        try Task.checkCancellation()
        func request() -> VNRecognizeTextRequest {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            let languages = ["ru-RU", "en-US"].filter { supported.contains($0) }
            if !languages.isEmpty { request.recognitionLanguages = languages }
            return request
        }

        let first = request()
        let completed: VNRecognizeTextRequest
        do {
            try VNImageRequestHandler(cgImage: image).perform([first])
            completed = first
        } catch {
            try Task.checkCancellation()
            let retry = request()
            do {
                let stages = try retry.supportedComputeStageDevices
                for (stage, devices) in stages {
                    if let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) {
                        retry.setComputeDevice(cpu, for: stage)
                    }
                }
                try VNImageRequestHandler(cgImage: image).perform([retry])
                completed = retry
            } catch {
                throw TaskImportError.recognitionFailed
            }
        }
        return (completed.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return Line(text: text, page: page, box: observation.boundingBox)
        }
    }

    private static func readingContext(for match: TaskImport.Match, in lines: [Line]) -> Range<Int>? {
        let start = match.range.lowerBound
        let anchor = lines[start]
        guard let instruction = lines[..<start].lastIndex(where: { line in
            line.page == anchor.page && line.column == anchor.column
                && contextInstruction.firstMatch(in: line.text, range: NSRange(line.text.startIndex..., in: line.text)) != nil
        }) else { return nil }
        let firstQuestion = ((instruction + 1)...start).first { index in
            TaskImport.startsQuestion(lines[index].text)
        } ?? start
        guard firstQuestion > instruction + 1 else { return nil }
        return instruction..<firstQuestion
    }

    private static let contextInstruction = try! NSRegularExpression(
        pattern: #"^(?:read\s+(?:a|an|the|this|both)\s+|listen\s+to\s+|прочитайте\s+(?:текст|отрывок)|прослушайте\s+)"#,
        options: .caseInsensitive
    )

    private static func fragments(for match: TaskImport.Match, context: Range<Int>?, in lines: [Line], pdf: PDFDocument?,
                                  images: inout [Int: CGImage]) throws -> [Data] {
        let questionLines = lines[match.range].prefix { !TaskImport.isAnswerOrSolution($0.text) }
        let located = questionLines.filter { line in line.box?.isEmpty == false }
        let groups = Dictionary(grouping: located) { $0.page * 2 + $0.column }
        var fragments: [Data] = []
        for key in groups.keys.sorted() {
            try Task.checkCancellation()
            guard let group = groups[key], let first = group.first, let firstBox = first.box else { continue }
            if images[first.page] == nil, let page = pdf?.page(at: first.page) {
                images.removeAll(keepingCapacity: true)
                images[first.page] = PageRendering(page)?.image()
            }
            guard let image = images[first.page] else { continue }
            let width = 1 / CGFloat(first.columns)
            let nextLine = match.range.upperBound < lines.count ? lines[match.range.upperBound] : nil
            let firstAfterQuestion = lines[match.range].dropFirst(questionLines.count).first
            let boundary = firstAfterQuestion ?? nextLine
            let bottom: CGFloat
            if let boundary, boundary.page == first.page, boundary.column == first.column,
               let box = boundary.box, box.maxY < firstBox.maxY {
                bottom = max(0, box.maxY + 0.003)
            } else {
                bottom = 0.025
            }
            let top = min(1, firstBox.maxY + 0.025)
            let lowest = group.compactMap(\.box).map(\.minY).min() ?? firstBox.minY
            let safeBottom = min(bottom, max(0, lowest - 0.005))
            let normalized = CGRect(x: CGFloat(first.column) * width, y: safeBottom,
                                    width: width, height: top - safeBottom)
            if let context, let topBox = lines[context.lowerBound].box, let questionBox = lines[context.upperBound].box,
               lines[context.lowerBound].page == first.page && lines[context.lowerBound].column == first.column {
                let top = min(1, topBox.maxY + 0.012)
                let bottom = questionBox.maxY + 0.002
                let region = CGRect(x: normalized.minX, y: bottom, width: width, height: max(0, top - bottom))
                if let data = crop(image, region: region) { fragments.append(data) }
            }
            if let data = crop(image, region: normalized) { fragments.append(data) }
        }
        return fragments
    }

    private static func crop(_ image: CGImage, region: CGRect) -> Data? {
        let frame = CGRect(x: region.minX * CGFloat(image.width),
                           y: (1 - region.maxY) * CGFloat(image.height),
                           width: region.width * CGFloat(image.width),
                           height: region.height * CGFloat(image.height)).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !frame.isEmpty, let cropped = image.cropping(to: frame) else { return nil }
        return jpeg(trimHorizontalMargins(cropped))
    }

    private static func trimHorizontalMargins(_ image: CGImage) -> CGImage {
        let columns = 240
        let rows = 150
        guard let sample = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8,
                                     bytesPerRow: columns, space: CGColorSpaceCreateDeviceGray(),
                                     bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let pixels = sample.data?.assumingMemoryBound(to: UInt8.self) else { return image }
        sample.interpolationQuality = .high
        sample.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        var left = columns
        var right = -1
        for y in 0..<rows {
            for x in 0..<columns where pixels[y * columns + x] < 232 {
                left = min(left, x)
                right = max(right, x)
            }
        }
        guard left < right else { return image }
        let margin = max(5, columns / 40)
        let start = max(0, left - margin) * image.width / columns
        let end = min(columns, right + margin + 1) * image.width / columns
        return image.cropping(to: CGRect(x: start, y: 0, width: end - start, height: image.height)) ?? image
    }

    private struct PageRendering {
        let page: CGPDFPage
        let canvas: CGRect
        let transform: CGAffineTransform

        init?(_ input: PDFPage) {
            guard let page = input.pageRef else { return nil }
            let box = page.getBoxRect(.cropBox)
            let rotated = page.rotationAngle % 180 != 0
            let width = rotated ? box.height : box.width
            let height = rotated ? box.width : box.height
            guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
            let scale = 1800 / max(width, height)
            let canvas = CGRect(x: 0, y: 0, width: max(1, (width * scale).rounded()),
                                height: max(1, (height * scale).rounded()))
            self.page = page
            self.canvas = canvas
            let oriented = CGRect(x: 0, y: 0, width: width, height: height)
            let rotation = page.getDrawingTransform(.cropBox, rect: oriented, rotate: 0, preserveAspectRatio: true)
            transform = rotation.concatenating(CGAffineTransform(scaleX: canvas.width / width, y: canvas.height / height))
        }

        func image() -> CGImage? {
            guard let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height),
                                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(canvas)
            context.concatenate(transform)
            context.drawPDFPage(page)
            return context.makeImage()
        }
    }

    static func image(from data: Data, maxPixelSize: Int = 2400) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary)
    }

    static func jpeg(_ image: CGImage) -> Data? {
        guard let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

private extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}
