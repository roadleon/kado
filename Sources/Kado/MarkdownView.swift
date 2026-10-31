import SwiftUI

/// 回答の Markdown を、チャット向けの最小限で整えて表示する。
/// 見出し・箇条書き・番号つきリスト・引用・区切り線・コードブロックと、行内の太字・斜体・コード・リンクを扱う。
struct MarkdownView: View {
    let text: String
    var onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let body):
                    TextBlockView(text: body)
                case .code(let language, let body):
                    CodeBlockView(language: language, code: body, onCopy: onCopy)
                }
            }
        }
    }
}

enum MarkdownBlock {
    case text(String)
    case code(language: String, body: String)

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var textLines: [String] = []
        var codeLines: [String] = []
        var language = ""
        var inCode = false

        func flushText() {
            let joined = textLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty { blocks.append(.text(joined)) }
            textLines = []
        }

        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(language: language, body: codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCode = false
                } else {
                    flushText()
                    language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(line)
            } else {
                textLines.append(line)
            }
        }
        // 書きかけ（閉じていない）のコードブロックもコードとして見せる
        if inCode {
            blocks.append(.code(language: language, body: codeLines.joined(separator: "\n")))
        } else {
            flushText()
        }
        return blocks
    }
}

private struct TextBlockView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(collapsedLines.enumerated()), id: \.offset) { _, line in
                LineView(line: line)
            }
        }
    }

    /// 連続する空行は1つにまとめる
    private var collapsedLines: [String] {
        var result: [String] = []
        for line in text.components(separatedBy: "\n") {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank, result.last.map({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? true { continue }
            result.append(line)
        }
        return result
    }
}

private struct LineView: View {
    let line: String
    @Environment(\.typography) private var typography

    var body: some View {
        let indentCount = line.prefix { $0 == " " || $0 == "\t" }.count
        let content = String(line.dropFirst(indentCount))
        let indent = CGFloat(min(indentCount / 2, 4)) * 14

        if content.isEmpty {
            Color.clear.frame(height: 2)
        } else if let heading = Self.heading(content) {
            Text(inline(heading))
                .font(typography.heading)
                .padding(.top, 4)
        } else if content == "---" || content == "***" || content == "___" {
            Divider().padding(.vertical, 4)
        } else if let item = Self.bullet(content) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                linkAwareText(item)
            }
            .padding(.leading, indent)
        } else if let numbered = Self.numbered(content) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(numbered.number).").foregroundStyle(.secondary).monospacedDigit()
                linkAwareText(numbered.item)
            }
            .padding(.leading, indent)
        } else if content.hasPrefix(">") {
            HStack(spacing: 8) {
                Rectangle().fill(Theme.accent.opacity(0.5)).frame(width: 2)
                Text(inline(String(content.dropFirst()).trimmingCharacters(in: .whitespaces)))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            linkAwareText(content)
                .padding(.leading, indent)
        }
    }

    /// 出典のように、行のほとんどがリンクなら、その上でポインターを指の形にする。
    /// SwiftUI の Text ではリンクの範囲だけを判定できないので、行の大半がリンクのときに限る。
    private func linkAwareText(_ s: String) -> some View {
        let text = inline(s)
        var linked = 0
        var total = 0
        for run in text.runs {
            let count = text[run.range].characters.count
            total += count
            if run.link != nil { linked += count }
        }
        return Text(text).modifier(LinkCursor(enabled: total > 0 && Double(linked) / Double(total) >= 0.6))
    }

    private func inline(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
    }

    private static func heading(_ s: String) -> String? {
        let hashes = s.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = s.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return String(rest.dropFirst())
    }

    private static func bullet(_ s: String) -> String? {
        for marker in ["- ", "* ", "+ ", "・"] where s.hasPrefix(marker) {
            return String(s.dropFirst(marker.count))
        }
        return nil
    }

    private static func numbered(_ s: String) -> (number: String, item: String)? {
        let digits = s.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = s.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (String(digits), String(rest.dropFirst(2)))
    }
}

private struct LinkCursor: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        // 文字選択の I 字カーソルが指の形を上書きするので、リンクの行では文字選択を外す
        if !enabled {
            content
        } else if #available(macOS 15, *) {
            content.textSelection(.disabled).pointerStyle(.link)
        } else {
            content.textSelection(.disabled).onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}

private struct CodeBlockView: View {
    let language: String
    let code: String
    var onCopy: (String) -> Void
    @State private var copied = false
    @Environment(\.typography) private var typography

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(typography.bodySmall)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onCopy(code)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Label(copied ? L10n.t("コピーしました", "Copied") : L10n.t("コピー", "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(typography.bodySmall)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            Divider().opacity(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(typography.code)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(10)
            }
        }
        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
