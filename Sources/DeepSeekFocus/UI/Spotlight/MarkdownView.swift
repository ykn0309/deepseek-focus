import AppKit
import SwiftUI
import DeepSeekFocusCore

enum MarkdownBlock {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bulletList([String])
    case orderedList([(number: Int, text: String)])
    case code(language: String?, text: String)
    case quote(String)
    case math(String)
    case divider
    case table(headers: [String], rows: [[String]])
}

enum SimpleMarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph.removeAll()
        }

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let math = consumeDisplayMath(lines: lines, index: &index, trimmed: trimmed) {
                flushParagraph()
                blocks.append(.math(math))
                continue
            }

            if let fence = fenceMarker(trimmed) {
                flushParagraph()
                let languageText = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        index += 1
                        break
                    }
                    codeLines.append(candidate)
                    index += 1
                }
                blocks.append(.code(
                    language: languageText.isEmpty ? nil : languageText,
                    text: codeLines.joined(separator: "\n")
                ))
                continue
            }

            if let heading = headingMatch(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let line = lines[index].trimmingCharacters(in: .whitespaces)
                    guard line.hasPrefix(">") else { break }
                    var value = String(line.dropFirst())
                    if value.hasPrefix(" ") { value.removeFirst() }
                    quoteLines.append(value)
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: " ")))
                continue
            }

            if let cells = tableCells(trimmed), index + 1 < lines.count,
               isTableSeparator(lines[index + 1]) {
                flushParagraph()
                let headers = cells
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let line = lines[index].trimmingCharacters(in: .whitespaces)
                    guard !line.isEmpty, let row = tableCells(line), !isTableSeparator(line) else { break }
                    rows.append(row)
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            if bulletMatch(rawLine) != nil {
                flushParagraph()
                var items: [String] = []
                while index < lines.count, let item = bulletMatch(lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            if orderedMatch(rawLine) != nil {
                flushParagraph()
                var items: [(number: Int, text: String)] = []
                while index < lines.count, let item = orderedMatch(lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            paragraph.append(rawLine)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func consumeDisplayMath(
        lines: [String],
        index: inout Int,
        trimmed: String
    ) -> String? {
        let originalIndex = index

        func consume(until terminator: String, dropping prefixCount: Int) -> String? {
            var content: [String] = []
            var first = String(trimmed.dropFirst(prefixCount))
            if let end = first.range(of: terminator) {
                content.append(String(first[..<end.lowerBound]))
                index += 1
                return content.joined(separator: "\n")
            }
            if !first.isEmpty { content.append(first) }
            index += 1
            while index < lines.count {
                let line = lines[index]
                if let end = line.range(of: terminator) {
                    let prefix = String(line[..<end.lowerBound])
                    if !prefix.isEmpty { content.append(prefix) }
                    index += 1
                    return content.joined(separator: "\n")
                }
                content.append(line)
                index += 1
            }
            index = originalIndex
            return nil
        }

        if trimmed.hasPrefix("$$") {
            return consume(until: "$$", dropping: 2)
        }
        if trimmed.hasPrefix("\\[") {
            return consume(until: "\\]", dropping: 2)
        }
        return nil
    }

    private static func fenceMarker(_ line: String) -> String? {
        if line.hasPrefix("```") { return "```" }
        if line.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func headingMatch(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.hasPrefix(" ") else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func bulletMatch(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return nil }
        let first = trimmed.first!
        guard first == "-" || first == "*" || first == "+" else { return nil }
        let rest = trimmed.dropFirst()
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func orderedMatch(_ line: String) -> (number: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var digits = ""
        var cursor = trimmed.startIndex
        while cursor < trimmed.endIndex, trimmed[cursor].isNumber {
            digits.append(trimmed[cursor])
            cursor = trimmed.index(after: cursor)
        }
        guard !digits.isEmpty, let number = Int(digits), cursor < trimmed.endIndex else { return nil }
        guard trimmed[cursor] == "." || trimmed[cursor] == ")" else { return nil }
        let after = trimmed.index(after: cursor)
        guard after < trimmed.endIndex, trimmed[after] == " " else { return nil }
        let text = trimmed[after...].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (number, text)
    }

    private static func tableCells(_ line: String) -> [String]? {
        guard line.contains("|") else { return nil }
        var body = line
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        let cells = body.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return cells.count >= 2 ? cells : nil
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard let cells = tableCells(line.trimmingCharacters(in: .whitespaces)), !cells.isEmpty else {
            return false
        }
        return cells.allSatisfy { cell in
            let stripped = cell.replacingOccurrences(of: ":", with: "")
            return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
        }
    }
}

struct AssistantMarkdownView: View {
    let text: String
    var isStreaming: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var blocks: [MarkdownBlock] {
        SimpleMarkdownParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let parsed = blocks
            ForEach(Array(parsed.enumerated()), id: \.offset) { index, block in
                blockView(block, cursor: isStreaming && index == parsed.count - 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock, cursor: Bool) -> some View {
        switch block {
        case .paragraph(let value):
            inlineContent(
                value,
                size: 14.5,
                weight: .regular,
                color: .labelColor,
                lineSpacing: 5.2,
                cursor: cursor
            )

        case .heading(let level, let value):
            inlineContent(
                value,
                size: headingSize(level),
                weight: level <= 2 ? .bold : .semibold,
                color: .labelColor,
                lineSpacing: 4,
                cursor: cursor
            )
            .padding(.top, 2)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle()
                            .fill(FocusTheme.accent.opacity(0.75))
                            .frame(width: 4.5, height: 4.5)
                            .alignmentGuide(.firstTextBaseline) { dimensions in
                                dimensions[.bottom] - 2.5
                            }
                        inlineContent(
                            item,
                            size: 14.5,
                            weight: .regular,
                            color: .labelColor,
                            lineSpacing: 4.5,
                            cursor: cursor && index == items.count - 1
                        )
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("\(item.number).")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(FocusTheme.accent)
                            .frame(minWidth: 18, alignment: .trailing)
                        inlineContent(
                            item.text,
                            size: 14.5,
                            weight: .regular,
                            color: .labelColor,
                            lineSpacing: 4.5,
                            cursor: cursor && index == items.count - 1
                        )
                    }
                }
            }

        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text((language ?? L10n.string("代码")).uppercased())
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(code, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("复制代码")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                DividerLine()

                ScrollView(.horizontal, showsIndicators: false) {
                    highlightedCode(code, language: language)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
                    }
            }

        case .quote(let value):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(FocusTheme.accent.opacity(0.55))
                    .frame(width: 2.5)
                inlineContent(
                    value,
                    size: 14,
                    weight: .regular,
                    color: .secondaryLabelColor,
                    lineSpacing: 4,
                    cursor: cursor
                )
            }
            .fixedSize(horizontal: false, vertical: true)

        case .math(let latex):
            MathBlockView(latex: latex)
                .padding(.vertical, 1)

        case .divider:
            DividerLine()
                .padding(.vertical, 2)

        case .table(let headers, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 0) {
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                            inlineContent(
                                header,
                                size: 12.5,
                                weight: .semibold,
                                color: .labelColor,
                                lineSpacing: 3,
                                lineLimit: 2
                            )
                        }
                    }
                    .padding(.vertical, 8)

                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        DividerLine()
                        GridRow {
                            ForEach(0..<headers.count, id: \.self) { column in
                                inlineContent(
                                    column < row.count ? row[column] : "",
                                    size: 12.5,
                                    weight: .regular,
                                    color: .labelColor,
                                    lineSpacing: 3,
                                    lineLimit: 3
                                )
                                .frame(minWidth: 52, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .fixedSize(horizontal: true, vertical: false)
            }
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7)
                    }
            }
        }
    }

    private func highlightedCode(_ code: String, language: String?) -> some View {
        Text(syntaxAttributedString(code, language: language))
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .textSelection(.enabled)
            .padding(12)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func syntaxAttributedString(_ code: String, language: String?) -> AttributedString {
        let tokens = SyntaxHighlighter.tokens(in: code, language: language)
        guard !tokens.isEmpty else { return AttributedString(code) }

        var result = AttributedString()
        var cursor = code.startIndex

        func appendPlain(_ range: Range<String.Index>) {
            guard !range.isEmpty else { return }
            var piece = AttributedString(String(code[range]))
            piece.foregroundColor = Color.primary.opacity(0.86)
            result.append(piece)
        }

        for token in tokens where token.range.lowerBound >= cursor {
            if cursor < token.range.lowerBound {
                appendPlain(cursor..<token.range.lowerBound)
            }
            var piece = AttributedString(String(code[token.range]))
            piece.foregroundColor = syntaxColor(for: token.kind)
            result.append(piece)
            cursor = token.range.upperBound
        }

        if cursor < code.endIndex {
            appendPlain(cursor..<code.endIndex)
        }
        return result
    }

    private func syntaxColor(for kind: SyntaxTokenKind) -> Color {
        let dark = colorScheme == .dark
        switch kind {
        case .keyword:
            return dark
                ? Color(red: 0.78, green: 0.47, blue: 0.86)
                : Color(red: 0.55, green: 0.16, blue: 0.68)
        case .string:
            return dark
                ? Color(red: 0.60, green: 0.76, blue: 0.47)
                : Color(red: 0.12, green: 0.47, blue: 0.18)
        case .comment:
            return dark
                ? Color(red: 0.50, green: 0.56, blue: 0.64)
                : Color(red: 0.45, green: 0.50, blue: 0.56)
        case .number:
            return dark
                ? Color(red: 0.82, green: 0.60, blue: 0.40)
                : Color(red: 0.63, green: 0.30, blue: 0.00)
        case .function:
            return dark
                ? Color(red: 0.38, green: 0.69, blue: 0.94)
                : Color(red: 0.08, green: 0.35, blue: 0.72)
        case .type:
            return dark
                ? Color(red: 0.34, green: 0.71, blue: 0.76)
                : Color(red: 0.00, green: 0.40, blue: 0.45)
        case .variable:
            return dark
                ? Color(red: 0.88, green: 0.42, blue: 0.46)
                : Color(red: 0.68, green: 0.12, blue: 0.25)
        case .property:
            return dark
                ? Color(red: 0.90, green: 0.75, blue: 0.48)
                : Color(red: 0.50, green: 0.32, blue: 0.00)
        case .literal:
            return dark
                ? Color(red: 0.82, green: 0.60, blue: 0.40)
                : Color(red: 0.63, green: 0.30, blue: 0.00)
        }
    }

    @ViewBuilder
    private func inlineContent(
        _ value: String,
        size: CGFloat,
        weight: Font.Weight,
        color: NSColor,
        lineSpacing: CGFloat,
        cursor: Bool = false,
        lineLimit: Int? = nil
    ) -> some View {
        Group {
            if InlineMathParser.containsMath(value) {
                let resolvedFont = nsFont(size: size, weight: weight)
                InlineMathText(
                    content: value,
                    font: resolvedFont,
                    textColor: color,
                    lineSpacing: lineSpacing,
                    isDark: colorScheme == .dark,
                    showCursor: cursor
                )
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[.top] + resolvedFont.ascender + resolvedFont.leading
                }
            } else {
                inlineText(value, cursor: cursor)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(Color(nsColor: color))
                    .lineSpacing(lineSpacing)
                    .lineLimit(lineLimit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func nsFont(size: CGFloat, weight: Font.Weight) -> NSFont {
        let nsWeight: NSFont.Weight
        switch weight {
        case .bold: nsWeight = .bold
        case .semibold: nsWeight = .semibold
        case .medium: nsWeight = .medium
        case .heavy: nsWeight = .heavy
        case .light: nsWeight = .light
        case .thin: nsWeight = .thin
        case .black: nsWeight = .black
        default: nsWeight = .regular
        }
        return .systemFont(ofSize: size, weight: nsWeight)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 20
        case 2: return 18
        case 3: return 16.5
        default: return 15.5
        }
    }

    private func inlineText(_ value: String, cursor: Bool) -> some View {
        var attributed: AttributedString
        do {
            attributed = try AttributedString(
                markdown: value,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            attributed = AttributedString(value)
        }
        if cursor {
            var cursorString = AttributedString(" ▍")
            cursorString.foregroundColor = FocusTheme.accent
            attributed.append(cursorString)
        }
        return Text(attributed)
            .tint(FocusTheme.accent)
            .foregroundStyle(.primary.opacity(0.93))
            .textSelection(.enabled)
    }
}
