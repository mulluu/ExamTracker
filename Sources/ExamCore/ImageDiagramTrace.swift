import CoreGraphics
import Foundation

public extension StudyDiagram {
    static func isImageTrace(_ description: String) -> Bool {
        description.hasPrefix(ImageDiagramTrace.header + "\n")
    }

    /// Returns an editable, scale-free outline of visible marks in a raster image.
    static func traceImage(at url: URL) throws -> (description: String, drawing: StudyDiagram, original: CGImage) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try traceImage(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func traceImage(data: Data) throws -> (description: String, drawing: StudyDiagram, original: CGImage) {
        guard let image = TaskImportDocument.image(from: data, maxPixelSize: ImageDiagramTrace.resolution) else {
            throw StudyDiagramError.unreadableImage
        }
        let description = try ImageDiagramTrace.trace(image)
        return (description, try parse(description), image)
    }
}

enum ImageDiagramTrace {
    static let header = "Контуры изображения"
    static let resolution = 384
    private static let maximumPaths = 128
    private static let maximumVertices = 6000

    static func trace(_ image: CGImage) throws -> String {
        let width = image.width
        let height = image.height
        guard width > 1, height > 1,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                        bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                        bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw StudyDiagramError.unreadableImage
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(rect)
        context.draw(image, in: rect)
        let pixels = UnsafeBufferPointer(start: bytes, count: width * height)
        let mask = try foregroundMask(pixels, width: width, height: height)
        let contours = try traceBoundaries(mask, width: width, height: height)
        guard !contours.isEmpty else { throw StudyDiagramError.noImageContours }

        let lines = contours.map { contour in
            contour.map { "\($0.x);\($0.y)" }.joined(separator: " ")
        }
        return ([header] + lines).joined(separator: "\n")
    }

    static func parse(_ text: String) throws -> StudyDiagram {
        guard text.utf8.count <= 80_000 else { throw StudyDiagramError.complexImageContours }
        let lines = text.split(whereSeparator: \.isNewline)
        guard let first = lines.first, first == header, lines.count > 1, lines.count <= maximumPaths + 1 else {
            throw StudyDiagramError.invalidGeometry
        }
        var paths: [StudyDiagram.Path] = []
        var vertexCount = 0
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for line in lines.dropFirst() {
            let coordinates = line.split(whereSeparator: \.isWhitespace)
            vertexCount += coordinates.count
            guard coordinates.count >= 3, vertexCount <= maximumVertices else {
                throw StudyDiagramError.invalidGeometry
            }
            let points = try coordinates.map { token in
                let fields = token.split(separator: ";", omittingEmptySubsequences: false)
                guard fields.count == 2, let x = Int(fields[0]), let y = Int(fields[1]),
                      (0...resolution).contains(x), (0...resolution).contains(y) else {
                    throw StudyDiagramError.invalidGeometry
                }
                minX = min(minX, Double(x))
                minY = min(minY, Double(y))
                maxX = max(maxX, Double(x))
                maxY = max(maxY, Double(y))
                return StudyDiagram.Point(x: Double(x), y: Double(y))
            }
            paths.append(StudyDiagram.Path(points: points, isClosed: true))
        }
        guard maxX > minX, maxY > minY else { throw StudyDiagramError.invalidGeometry }
        let bounds = StudyDiagram.Bounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
        return StudyDiagram(kind: .trace, bounds: bounds, paths: paths, points: [], circles: [])
    }

    private static func foregroundMask(_ pixels: UnsafeBufferPointer<UInt8>, width: Int, height: Int) throws -> [Bool] {
        var histogram = Array(repeating: 0, count: 256)
        for value in pixels { histogram[Int(value)] += 1 }
        guard let darkest = histogram.firstIndex(where: { $0 > 0 }),
              let lightest = histogram.lastIndex(where: { $0 > 0 }), lightest - darkest >= 35 else {
            throw StudyDiagramError.noImageContours
        }

        let totalBrightness = histogram.enumerated().reduce(0) { $0 + $1.offset * $1.element }
        var bestScore = -1.0
        var threshold = darkest
        var darkCount = 0
        var darkBrightness = 0
        // Choose the split that best separates foreground and background intensities.
        for level in darkest..<lightest {
            darkCount += histogram[level]
            darkBrightness += level * histogram[level]
            let lightCount = pixels.count - darkCount
            let difference = Double(darkBrightness) / Double(darkCount)
                - Double(totalBrightness - darkBrightness) / Double(lightCount)
            let score = Double(darkCount) * Double(lightCount) * difference * difference
            if score > bestScore {
                bestScore = score
                threshold = level
            }
        }

        var darkBorder = 0
        var borderCount = 0
        for y in 0..<height {
            for x in 0..<width where y == 0 || y == height - 1 || x == 0 || x == width - 1 {
                borderCount += 1
                if Int(pixels[y * width + x]) <= threshold { darkBorder += 1 }
            }
        }
        let backgroundIsDark = 2 * darkBorder > borderCount
        let mask = pixels.map { (Int($0) <= threshold) != backgroundIsDark }
        let foregroundCount = mask.reduce(0) { $0 + ($1 ? 1 : 0) }
        guard foregroundCount >= 6, foregroundCount < pixels.count - 6 else {
            throw StudyDiagramError.noImageContours
        }
        return mask
    }

    private struct Vertex: Equatable {
        let x: Int
        let y: Int
    }

    private static func traceBoundaries(_ mask: [Bool], width: Int, height: Int) throws -> [[Vertex]] {
        let stride = width + 1
        var edges = Array(repeating: UInt8(0), count: stride * (height + 1))
        // Add clockwise edges with foreground on the right.
        for y in 0..<height {
            try Task.checkCancellation()
            for x in 0..<width where mask[y * width + x] {
                let pixel = y * width + x
                let corner = y * stride + x
                if y == 0 || !mask[pixel - width] { edges[corner] |= 1 }
                if x == width - 1 || !mask[pixel + 1] { edges[corner + 1] |= 2 }
                if y == height - 1 || !mask[pixel + width] { edges[corner + stride + 1] |= 4 }
                if x == 0 || !mask[pixel - 1] { edges[corner + stride] |= 8 }
            }
        }

        let steps = [1, stride, -1, -stride]
        var contours: [[Vertex]] = []
        var vertexCount = 0
        for start in edges.indices {
            while edges[start] != 0 {
                try Task.checkCancellation()
                var corner = start
                var direction = edges[start].trailingZeroBitCount
                var loop: [Vertex] = []
                repeat {
                    loop.append(Vertex(x: corner % stride, y: height - corner / stride))
                    edges[corner] &= ~(1 << direction)
                    corner += steps[direction]
                    if corner == start { break }
                    guard let next = [1, 0, 3, 2].map({ (direction + $0) % 4 })
                        .first(where: { edges[corner] & (1 << $0) != 0 }) else {
                        throw StudyDiagramError.noImageContours
                    }
                    direction = next
                } while true

                guard loop.count <= 24_000 else { throw StudyDiagramError.complexImageContours }
                guard abs(twiceArea(loop)) >= 10 else { continue }
                let simplified = simplify(loop)
                vertexCount += simplified.count
                contours.append(simplified)
                guard contours.count <= maximumPaths, vertexCount <= maximumVertices else {
                    throw StudyDiagramError.complexImageContours
                }
            }
        }
        return contours
    }

    private static func twiceArea(_ vertices: [Vertex]) -> Int {
        var area = 0
        for index in vertices.indices {
            let a = vertices[index], b = vertices[(index + 1) % vertices.count]
            area += a.x * b.y - a.y * b.x
        }
        return area
    }

    private static func simplify(_ loop: [Vertex]) -> [Vertex] {
        let corners = loop.indices.compactMap { index -> Vertex? in
            let a = loop[(index + loop.count - 1) % loop.count]
            let b = loop[index]
            let c = loop[(index + 1) % loop.count]
            return (b.x - a.x) * (c.y - b.y) == (b.y - a.y) * (c.x - b.x) ? nil : b
        }
        guard corners.count > 4 else { return corners }
        let end = corners.indices.max(by: {
            squaredDistance(corners[$0], from: corners[0], to: corners[0])
                < squaredDistance(corners[$1], from: corners[0], to: corners[0])
        })!
        let closed = corners + [corners[0]]
        var intervals = [(0, end), (end, closed.count - 1)]
        var keep = Set([0, end])
        while let (first, last) = intervals.popLast() {
            guard last - first > 1 else { continue }
            var maximum = 0.55 * 0.55
            var split: Int?
            for index in (first + 1)..<last {
                let distance = squaredDistance(closed[index], from: closed[first], to: closed[last])
                if distance > maximum { maximum = distance; split = index }
            }
            if let split {
                keep.insert(split)
                intervals.append((first, split))
                intervals.append((split, last))
            }
        }
        return keep.count >= 3 ? keep.sorted().map { closed[$0] } : corners
    }

    private static func squaredDistance(_ point: Vertex, from start: Vertex, to end: Vertex) -> Double {
        let x = Double(end.x - start.x), y = Double(end.y - start.y)
        let px = Double(point.x - start.x), py = Double(point.y - start.y)
        let length = x * x + y * y
        let fraction = length == 0 ? 0 : min(1, max(0, (px * x + py * y) / length))
        let dx = px - fraction * x, dy = py - fraction * y
        return dx * dx + dy * dy
    }
}
