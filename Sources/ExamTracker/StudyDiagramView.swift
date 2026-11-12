import ExamCore
import SwiftUI

struct StudyDiagramView: View {
    let description: String
    @TrackerState private var diagram: StudyDiagram?

    var body: some View {
        Group {
            if let diagram {
                StudyDiagramCanvas(diagram: diagram, description: description)
                    .frame(height: 250)
            }
        }
        .task(id: description) { diagram = try? StudyDiagram.parse(description) }
    }
}

private struct StudyDiagramCanvas: View {
    let diagram: StudyDiagram
    let description: String

    var body: some View {
        Canvas { context, size in
            draw(diagram, in: context, size: size)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.secondary.opacity(0.16))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(diagram.kind == .graph ? "График функции" : "Геометрическая фигура")
        .accessibilityValue(diagram.kind == .trace ? "Контуры с изображения: \(diagram.paths.count)" : description)
    }

    private func draw(_ diagram: StudyDiagram, in context: GraphicsContext, size: CGSize) {
        let projection = Projection(bounds: diagram.bounds, size: size, equalScale: diagram.kind != .graph)
        if diagram.kind == .trace {
            var outlines = SwiftUI.Path()
            for line in diagram.paths {
                guard let first = line.points.first else { continue }
                outlines.move(to: projection.point(first.x, first.y))
                for point in line.points.dropFirst() {
                    outlines.addLine(to: projection.point(point.x, point.y))
                }
                outlines.closeSubpath()
            }
            context.fill(outlines, with: .color(.primary), style: FillStyle(eoFill: true))
            return
        }
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
    @Binding var isAutomatic: Bool?
    let condition: String
    let fragments: [Data]
    let illustration: Data?
    @TrackerState private var draft: String
    @TrackerState private var choosingImage = false
    @TrackerState private var readText = false
    @TrackerState private var reading: Task<Void, Never>?
    @TrackerState private var error: String?

    init(description: Binding<String?>, inQuestion: Binding<Bool?>,
         isAutomatic: Binding<Bool?>, condition: String, fragments: [Data], illustration: Data?) {
        _description = description
        _inQuestion = inQuestion
        _isAutomatic = isAutomatic
        self.condition = condition
        self.fragments = fragments
        self.illustration = illustration
        _draft = TrackerState(initialValue: description.wrappedValue ?? "")
    }

    var body: some View {
        DisclosureGroup(description == nil ? "График или фигура" : "График или фигура добавлены") {
            VStack(alignment: .leading, spacing: 10) {
                if StudyDiagram.isImageTrace(draft) {
                    Label("Контур с изображения", systemImage: "photo")
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Формула или условие", text: $draft, prompt: Text("y = x² − 2x + 1"), axis: .vertical)
                        .lineLimit(1...5)
                        .disabled(reading != nil)
                }
                StudyDiagramExamples { draft = $0 }
                    .disabled(reading != nil)
                HStack(spacing: 10) {
                    Button("Построить", systemImage: "chart.xyaxis.line", action: build)
                        .disabled(draft.cleaned.isEmpty || StudyDiagram.isImageTrace(draft) || reading != nil)
                    Button("Из условия", action: buildFromCondition)
                        .disabled(condition.cleaned.isEmpty || reading != nil)
                    Menu("С изображения", systemImage: "photo") {
                        Button("Обвести контур из файла…") {
                            readText = false
                            choosingImage = true
                        }
                        Button("Считать текст из файла…") {
                            readText = true
                            choosingImage = true
                        }
                        if let illustration {
                            Button("Обвести иллюстрацию задания") { loadImage(.traceData(illustration)) }
                        }
                        if !fragments.isEmpty {
                            Menu("Обвести фрагмент оригинала") {
                                ForEach(fragments.indices, id: \.self) { index in
                                    Button("Фрагмент \(index + 1)") { loadImage(.traceData(fragments[index])) }
                                }
                            }
                        }
                    }
                    .fixedSize()
                    .disabled(reading != nil)
                    if description != nil {
                        Button("Убрать", role: .destructive) {
                            description = nil
                            inQuestion = nil
                            isAutomatic = false
                            draft = ""
                        }
                        .disabled(reading != nil)
                    }
                }
                if reading != nil { ProgressView("Обрабатываем изображение…").controlSize(.small) }
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
            do {
                let url = try result.get()
                loadImage(readText ? .text(url) : .traceFile(url))
            } catch { self.error = error.localizedDescription }
        }
        .onChange(of: draft) { error = nil }
        .onChange(of: description) { oldValue, newValue in
            if draft.cleaned == (oldValue ?? "") { draft = newValue ?? "" }
        }
        .onDisappear { reading?.cancel() }
    }

    private func build() {
        error = nil
        do {
            let drawing = try DiagramDraft.parse(draft.cleaned)
            if description != drawing.description {
                inQuestion = nil
            }
            description = drawing.description
            draft = drawing.description
            isAutomatic = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func buildFromCondition() {
        guard let diagram = ProblemDiagram.fromCondition(condition) else {
            error = "В условии не найдено достаточно данных для построения."
            return
        }
        error = nil
        description = diagram.description
        inQuestion = diagram.showsDuringPractice
        isAutomatic = true
        draft = diagram.description
    }

    private enum ImageAction: Sendable {
        case traceFile(URL), traceData(Data), text(URL)

        func run() throws -> String {
            switch self {
            case .traceFile(let url): try StudyDiagram.traceImage(at: url).description
            case .traceData(let data): try StudyDiagram.traceImage(data: data).description
            case .text(let url): try TaskImport.read(url)
            }
        }
    }

    private func loadImage(_ action: ImageAction) {
        error = nil
        reading?.cancel()
        reading = Task {
            let worker = Task.detached(priority: .userInitiated) { try action.run() }
            defer { if !Task.isCancelled { reading = nil } }
            do {
                let value = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                draft = value
                if case .text = action { return }
                description = value
                inQuestion = nil
                isAutomatic = false
            } catch where !Task.isCancelled {
                self.error = error.localizedDescription
            } catch {}
        }
    }
}

struct StudyDiagramWorkspace: View {
    let onCreateTask: (PracticeTask) -> Void

    @Environment(\.dismiss) private var dismiss
    @TrackerState private var source = Source.condition
    @TrackerState private var input = ""
    @TrackerState private var preview: DiagramDraft?
    @TrackerState private var renderedInput = ""
    @TrackerState private var error: String?

    @TrackerState private var imagePreview: DiagramDraft?
    @TrackerState private var imageError: String?
    @TrackerState private var imageJob: Task<Void, Never>?
    @TrackerState private var selectingImage = false
    @TrackerState private var imageCondition = ""

    private enum Source: String, CaseIterable {
        case condition = "Из условия"
        case image = "С изображения"
    }

    private var currentPreview: DiagramDraft? {
        source == .image ? imagePreview : renderedInput == input ? preview : nil
    }

    private var currentError: String? {
        source == .image ? imageError : renderedInput == input ? error : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Графики и фигуры").font(.title2.weight(.semibold))
                Spacer()
                Picker("Источник", selection: $source) {
                    ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(20)
            Divider()
            HSplitView {
                Group {
                    if source == .condition { conditionEditor }
                    else { imageEditor }
                }
                .padding(20)
                .frame(minWidth: 260, idealWidth: 310, maxHeight: .infinity)

                Group {
                    if let drawing = currentPreview {
                        StudyDiagramCanvas(diagram: drawing.drawing, description: drawing.description)
                    } else if let currentError {
                        ContentUnavailableView("Не удалось построить", systemImage: "exclamationmark.circle",
                                               description: Text(currentError))
                    } else if source == .image, imageJob != nil {
                        ProgressView("Обводим контуры…")
                    } else {
                        ContentUnavailableView("Предпросмотр", systemImage: "chart.xyaxis.line",
                            description: Text(source == .image ? "Выберите изображение чертежа." : "Введите условие или выберите пример."))
                    }
                }
                .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            }
            Divider()
            HStack {
                Button("Закрыть", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Создать задание") {
                    guard let drawing = currentPreview else { return }
                    let topic = drawing.drawing.kind == .graph ? "Графики" : "Геометрия"
                    let prompt = source == .condition ? input.cleaned : imageCondition.cleaned
                    var task = PracticeTask(topic: topic, prompt: prompt)
                    task.illustration = drawing.attachment
                    task.diagramDescription = drawing.description
                    task.diagramInQuestion = drawing.showsDuringPractice
                    task.diagramIsAutomatic = false
                    onCreateTask(task)
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentPreview == nil)
            }
            .padding(16)
        }
        .frame(width: 800, height: 460)
        .fileImporter(isPresented: $selectingImage, allowedContentTypes: [.image]) { result in
            do { traceImage(try result.get()) }
            catch { imageError = error.localizedDescription }
        }
        .onDisappear { imageJob?.cancel() }
        .task(id: input) {
            let current = input
            guard !current.cleaned.isEmpty else {
                preview = nil
                error = nil
                renderedInput = current
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(180))
                let worker = Task.detached(priority: .userInitiated) { try DiagramDraft.parse(current.cleaned) }
                let drawing = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                preview = drawing
                error = nil
                renderedInput = current
            } catch where !Task.isCancelled {
                preview = nil
                self.error = error.localizedDescription
                renderedInput = current
            } catch {}
        }
    }

    private var conditionEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Условие или формула").font(.headline)
                Spacer()
                StudyDiagramExamples { input = $0 }
            }
            TextEditor(text: $input)
                .font(.body)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.2)) }
                .accessibilityLabel("Условие или формула")
            Text("Например, дан треугольник со сторонами 3, 4 и 5.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var imageEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Выбрать чертёж…", systemImage: "photo") { selectingImage = true }
                .disabled(imageJob != nil)
            if let original = imagePreview?.original {
                Image(decorative: original, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Исходный чертёж")
            } else {
                Text("Подойдёт контрастный рисунок или скриншот. При необходимости обрежьте его до фигуры.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            TextField("Условие задания", text: $imageCondition, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private func traceImage(_ url: URL) {
        imageJob?.cancel()
        imageError = nil
        imagePreview = nil
        imageJob = Task {
            defer { if !Task.isCancelled { imageJob = nil } }
            let worker = Task.detached(priority: .userInitiated) {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let attachment = try TaskIllustrationEditor.thumbnail(from: url)
                let result = try StudyDiagram.traceImage(data: attachment)
                return DiagramDraft(description: result.description, drawing: result.drawing,
                                    showsDuringPractice: false, original: result.original, attachment: attachment)
            }
            do {
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                imagePreview = result
            } catch where !Task.isCancelled {
                imageError = error.localizedDescription
            } catch {}
        }
    }

}

private struct DiagramDraft: Sendable {
    let description: String
    let drawing: StudyDiagram
    let showsDuringPractice: Bool
    var original: CGImage? = nil
    var attachment: Data? = nil

    static func parse(_ input: String) throws -> Self {
        if let diagram = ProblemDiagram.fromCondition(input) {
            return Self(description: diagram.description, drawing: diagram.drawing,
                        showsDuringPractice: diagram.showsDuringPractice)
        }
        return Self(description: input, drawing: try StudyDiagram.parse(input), showsDuringPractice: false)
    }
}

private struct StudyDiagramExamples: View {
    let select: (String) -> Void

    var body: some View {
        Menu("Примеры") {
            Button("Парабола") { select("y = x² − 2x + 1") }
            Button("Треугольник по условию") {
                select("Дан треугольник ABC со сторонами AB = 3, BC = 4 и AC = 5. Найдите площадь.")
            }
            Button("Треугольник по координатам") { select("Треугольник ABC: A(0; 0), B(4; 0), C(0; 3)") }
            Button("Окружность по центру и радиусу") { select("Окружность: центр O(0; 0), радиус 3") }
            Button("Прямоугольник по размерам") { select("Прямоугольник: ширина 4, высота 3") }
        }
        .fixedSize()
    }
}
