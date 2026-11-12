import ExamCore
import SwiftUI

struct StudyDiagramView: View {
    let description: String
    @TrackerState private var diagram: StudyDiagram?

    var body: some View {
        Group {
            if let diagram {
                Canvas { context, size in
                    draw(diagram, in: context, size: size)
                }
                .frame(height: 250)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.secondary.opacity(0.16))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(diagram.kind == .graph ? "График функции" : "Геометрическая фигура")
                .accessibilityValue(description)
            }
        }
        .task(id: description) { diagram = try? StudyDiagram.parse(description) }
    }

    private func draw(_ diagram: StudyDiagram, in context: GraphicsContext, size: CGSize) {
        let projection = Projection(bounds: diagram.bounds, size: size, equalScale: diagram.kind == .geometry)
        if diagram.kind == .graph {
            drawAxes(diagram.bounds, in: context, projection: projection)
        }

        var strokes = context
        if diagram.kind == .graph {
            let topLeft = projection.point(diagram.bounds.minX, diagram.bounds.maxY)
            let bottomRight = projection.point(diagram.bounds.maxX, diagram.bounds.minY)
            strokes.clip(to: SwiftUI.Path(CGRect(x: topLeft.x, y: topLeft.y,
                width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)))
        }
        for line in diagram.paths {
            guard let start = line.points.first else { continue }
            var path = SwiftUI.Path()
            path.move(to: projection.point(start.x, start.y))
            for point in line.points.dropFirst() {
                path.addLine(to: projection.point(point.x, point.y))
            }
            if line.isClosed { path.closeSubpath() }
            strokes.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }

        for circle in diagram.circles {
            let center = projection.point(circle.center.x, circle.center.y)
            let rx = circle.radius * projection.xScale
            let ry = circle.radius * projection.yScale
            let ellipse = CGRect(x: center.x - rx, y: center.y - ry, width: 2 * rx, height: 2 * ry)
            context.stroke(SwiftUI.Path(ellipseIn: ellipse), with: .color(.accentColor), lineWidth: 2)
        }

        for point in diagram.points {
            let position = projection.point(point.x, point.y)
            let marker = CGRect(x: position.x - 2.5, y: position.y - 2.5, width: 5, height: 5)
            context.fill(SwiftUI.Path(ellipseIn: marker), with: .color(.accentColor))
            if let label = point.label {
                let text = Text(label).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                context.draw(text, at: CGPoint(x: position.x + 6, y: position.y - 6), anchor: .bottomLeading)
            }
        }
    }

    private func drawAxes(_ bounds: StudyDiagram.Bounds, in context: GraphicsContext, projection: Projection) {
        let originX = min(max(0, bounds.minX), bounds.maxX)
        let originY = min(max(0, bounds.minY), bounds.maxY)
        let labelStyle = Font.caption2.monospacedDigit()

        for x in ticks(from: bounds.minX, to: bounds.maxX) {
            let bottom = projection.point(x, bounds.minY)
            let top = projection.point(x, bounds.maxY)
            line(bottom, top, in: context, strong: abs(x) < 1e-12)
            context.draw(Text(points(x)).font(labelStyle).foregroundStyle(.secondary),
                         at: CGPoint(x: bottom.x, y: bottom.y + 4), anchor: .top)
        }
        for y in ticks(from: bounds.minY, to: bounds.maxY) {
            let left = projection.point(bounds.minX, y)
            let right = projection.point(bounds.maxX, y)
            line(left, right, in: context, strong: abs(y) < 1e-12)
            context.draw(Text(points(y)).font(labelStyle).foregroundStyle(.secondary),
                         at: CGPoint(x: left.x - 5, y: left.y), anchor: .trailing)
        }
        let xEnd = projection.point(bounds.maxX, originY)
        let yEnd = projection.point(originX, bounds.maxY)
        context.draw(Text("x").font(labelStyle), at: CGPoint(x: xEnd.x + 5, y: xEnd.y), anchor: .leading)
        context.draw(Text("y").font(labelStyle), at: CGPoint(x: yEnd.x, y: yEnd.y - 4), anchor: .bottom)
    }

    private func line(_ start: CGPoint, _ end: CGPoint, in context: GraphicsContext, strong: Bool) {
        var path = SwiftUI.Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(.secondary.opacity(strong ? 0.55 : 0.18)), lineWidth: strong ? 1 : 0.5)
    }

    private func ticks(from start: Double, to end: Double) -> [Double] {
        let rough = (end - start) / 6
        guard rough.isFinite, rough > 0 else { return [] }
        let magnitude = pow(10, floor(log10(rough)))
        let scaled = rough / magnitude
        let step = magnitude * (scaled <= 1 ? 1 : scaled <= 2 ? 2 : scaled <= 5 ? 5 : 10)
        guard step.isFinite, step > 0 else { return [] }
        let first = ceil(start / step) * step
        return (0..<10).map { first + Double($0) * step }.filter { $0 <= end }
    }

    private struct Projection {
        let xScale: Double
        let yScale: Double
        let left: Double
        let bottom: Double

        init(bounds: StudyDiagram.Bounds, size: CGSize, equalScale: Bool) {
            let width = bounds.maxX - bounds.minX
            let height = bounds.maxY - bounds.minY
            let horizontal = max(1, size.width - 94) / width
            let vertical = max(1, size.height - 56) / height
            xScale = equalScale ? min(horizontal, vertical) : horizontal
            yScale = equalScale ? xScale : vertical
            left = (size.width - width * xScale) / 2 - bounds.minX * xScale
            bottom = (size.height + height * yScale) / 2 + bounds.minY * yScale
        }

        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: left + x * xScale, y: bottom - y * yScale)
        }
    }
}

struct StudyDiagramEditor: View {
    @Binding var description: String?
    @Binding var inQuestion: Bool?
    @TrackerState private var draft: String
    @TrackerState private var choosingImage = false
    @TrackerState private var reading: Task<Void, Never>?
    @TrackerState private var error: String?

    init(description: Binding<String?>, inQuestion: Binding<Bool?>) {
        _description = description
        _inQuestion = inQuestion
        _draft = TrackerState(initialValue: description.wrappedValue ?? "")
    }

    var body: some View {
        DisclosureGroup("Точный график или фигура") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Формула или параметры", text: $draft, prompt: Text("y = x² − 2x + 1"), axis: .vertical)
                    .lineLimit(1...5)
                    .disabled(reading != nil)
                    .onChange(of: draft) { error = nil }
                Menu("Примеры форматов") {
                    Button("График параболы") { draft = "y = x² − 2x + 1" }
                    Button("Треугольник по координатам") { draft = "Треугольник ABC: A(0; 0), B(4; 0), C(0; 3)" }
                    Button("Окружность по центру и радиусу") { draft = "Окружность: центр O(0; 0), радиус 3" }
                    Button("Прямоугольник по размерам") { draft = "Прямоугольник: ширина 4, высота 3" }
                }
                .disabled(reading != nil)
                HStack(spacing: 10) {
                    Button("Построить", systemImage: "chart.xyaxis.line", action: build)
                        .disabled(draft.cleaned.isEmpty || reading != nil)
                    Button("Считать текст с изображения", systemImage: "text.viewfinder") { choosingImage = true }
                        .disabled(reading != nil)
                    if description != nil {
                        Button("Убрать", role: .destructive) {
                            description = nil
                            inQuestion = nil
                            draft = ""
                        }
                        .disabled(reading != nil)
                    }
                }
                if reading != nil { ProgressView("Распознаём текст…").controlSize(.small) }
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
                if draft.cleaned != (description ?? ""), !draft.cleaned.isEmpty {
                    Text("Нажмите «Построить», чтобы применить изменения.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let description, description == draft.cleaned {
                    StudyDiagramView(description: description)
                    Toggle("Показывать схему в условии", isOn: Binding(
                        get: { inQuestion == true },
                        set: { inQuestion = $0 }
                    ))
                    .help("Оставьте выключенным, если схема показывает ответ или решение.")
                }
            }
            .padding(.vertical, 6)
        }
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.image]) { result in
            do { read(try result.get()) }
            catch { self.error = error.localizedDescription }
        }
        .onDisappear { reading?.cancel() }
    }

    private func build() {
        error = nil
        do {
            let value = draft.cleaned
            _ = try StudyDiagram.parse(value)
            description = value
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func read(_ url: URL) {
        error = nil
        reading = Task {
            let worker = Task.detached(priority: .userInitiated) { try TaskImport.read(url) }
            defer { reading = nil }
            do {
                let text = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                draft = text
            } catch where !Task.isCancelled {
                self.error = error.localizedDescription
            } catch {}
        }
    }
}
