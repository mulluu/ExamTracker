import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ExamCore

struct ImageDiagramTraceTests {
    @Test func tracesAnUnlabelledTriangleAndPreservesTheStrokeInterior() throws {
        let data = try fixture { context in
            context.move(to: CGPoint(x: 14, y: 14))
            context.addLine(to: CGPoint(x: 102, y: 14))
            context.addLine(to: CGPoint(x: 23, y: 63))
            context.closePath()
            context.strokePath()
        }
        let result = try StudyDiagram.traceImage(data: data)
        let saved = try StudyDiagram.parse(result.description)
        #expect(saved.kind == .trace)
        #expect(saved.paths.count == 2)
        #expect(saved.paths.allSatisfy { $0.isClosed })
        #expect(saved.bounds.maxX - saved.bounds.minX > saved.bounds.maxY - saved.bounds.minY)
        let outlines = saved.paths.flatMap(\.points)
        #expect(outlines.contains { $0.y > saved.bounds.maxY - 8 && $0.x < 33 })
        #expect(outlines.contains { $0.x > saved.bounds.maxX - 8 && $0.y < 20 })
    }

    @Test func tracesLightLinesOnDarkBackground() throws {
        let data = try fixture(dark: true) { context in
            context.strokeEllipse(in: CGRect(x: 33, y: 11, width: 56, height: 56))
        }
        let result = try StudyDiagram.traceImage(data: data)
        #expect(result.drawing.paths.count == 2)
        #expect(abs((result.drawing.bounds.maxX - result.drawing.bounds.minX)
                    - (result.drawing.bounds.maxY - result.drawing.bounds.minY)) < 2)
    }

    @Test func rejectsBlankImage() throws {
        let data = try fixture { _ in }
        #expect(throws: StudyDiagramError.self) { try StudyDiagram.traceImage(data: data) }
    }

    private func fixture(dark: Bool = false, draw: (CGContext) -> Void) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8,
                                             bytesPerRow: 120, space: CGColorSpaceCreateDeviceGray(),
                                             bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: dark ? 0 : 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        context.setStrokeColor(gray: dark ? 1 : 0, alpha: 1)
        context.setLineWidth(4)
        draw(context)
        let buffer = NSMutableData()
        let encoder = try #require(CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, try #require(context.makeImage()), nil)
        try #require(CGImageDestinationFinalize(encoder))
        return buffer as Data
    }
}
