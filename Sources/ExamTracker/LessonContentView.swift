import ExamCore
import SwiftUI

struct LessonContentView: View {
    let lesson: ExamLesson

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let code):
                    ScrollView(.horizontal) {
                        Text(verbatim: code)
                            .font(.callout.monospaced())
                            .padding(10)
                    }
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                case .line(let line):
                    prose(line)
                }
            }
            if let data = lesson.illustration, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 520, maxHeight: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Иллюстрация к уроку")
                Label("Иллюстрация создана ИИ", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
    }

    private enum Block {
        case code(String)
        case line(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var code: [String]?
        for line in lesson.displayContent.components(separatedBy: "\n") {
            let trimmed = line.cleaned
            if trimmed.hasPrefix("```") {
                if let lines = code {
                    result.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else if !trimmed.isEmpty {
                result.append(.line(trimmed))
            }
        }
        if let code { result.append(.code(code.joined(separator: "\n"))) }
        return result
    }

    @ViewBuilder private func prose(_ line: String) -> some View {
        if line.hasPrefix("# ") || line.hasPrefix("## ") || line.hasPrefix("### ") {
            inline(String(line.drop(while: { $0 == "#" || $0 == " " })))
                .font(line.hasPrefix("# ") ? .title3.weight(.semibold) : .headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 4)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").accessibilityHidden(true)
                inline(String(line.dropFirst(2)))
            }
        } else {
            inline(line)
        }
    }

    private func inline(_ line: String) -> Text {
        let markdown = try? AttributedString(markdown: line,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        return markdown.map(Text.init) ?? Text(line)
    }
}
