import AppKit
import SwiftUI
import SwiftMath
import CoreText

// MARK: - Inline math parsing

enum InlineMathSegment {
    case text(String)
    case math(String)
}

enum InlineMathParser {
    static func containsMath(_ text: String) -> Bool {
        segments(in: text).contains { segment in
            if case .math = segment { return true }
            return false
        }
    }

    static func segments(in text: String) -> [InlineMathSegment] {
        var result: [InlineMathSegment] = []
        var buffer = ""
        var index = text.startIndex

        func flushText() {
            guard !buffer.isEmpty else { return }
            result.append(.text(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        while index < text.endIndex {
            let character = text[index]

            // Do not interpret dollar signs inside `inline code`.
            if character == "`" {
                let after = text.index(after: index)
                if after < text.endIndex,
                   let close = text.range(of: "`", range: after..<text.endIndex) {
                    buffer.append(contentsOf: text[index..<close.upperBound])
                    index = close.upperBound
                    continue
                }
            }

            if character == "\\" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "(",
                   let close = text.range(of: "\\)", range: next..<text.endIndex) {
                    let content = String(text[text.index(after: next)..<close.lowerBound])
                    if isPlausibleMath(content) {
                        flushText()
                        result.append(.math(content))
                        index = close.upperBound
                        continue
                    }
                }
                if next < text.endIndex, text[next] == "[",
                   let close = text.range(of: "\\]", range: next..<text.endIndex) {
                    let content = String(text[text.index(after: next)..<close.lowerBound])
                    if isPlausibleMath(content) {
                        flushText()
                        result.append(.math(content))
                        index = close.upperBound
                        continue
                    }
                }
                buffer.append(character)
                if next < text.endIndex {
                    buffer.append(text[next])
                    index = text.index(after: next)
                } else {
                    index = next
                }
                continue
            }

            if character == "$" {
                let next = text.index(after: index)

                // Display math appearing in the middle of a paragraph.
                if next < text.endIndex, text[next] == "$",
                   let close = text.range(of: "$$", range: next..<text.endIndex) {
                    let start = text.index(after: next)
                    let content = String(text[start..<close.lowerBound])
                    if isPlausibleMath(content) {
                        flushText()
                        result.append(.math(content))
                        index = close.upperBound
                        continue
                    }
                }

                if next < text.endIndex,
                   let close = nextUnescapedDollar(in: text, from: next) {
                    let content = String(text[next..<close])
                    if isPlausibleMath(content) {
                        flushText()
                        result.append(.math(content))
                        index = text.index(after: close)
                        continue
                    }
                }
            }

            buffer.append(character)
            index = text.index(after: index)
        }

        flushText()
        return result
    }

    private static func nextUnescapedDollar(in text: String, from start: String.Index) -> String.Index? {
        var cursor = start
        while cursor < text.endIndex {
            if text[cursor] == "$" {
                var backslashes = 0
                var previous = cursor
                while previous > text.startIndex {
                    previous = text.index(before: previous)
                    if text[previous] == "\\" { backslashes += 1 } else { break }
                }
                if backslashes.isMultiple(of: 2) { return cursor }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func isPlausibleMath(_ raw: String) -> Bool {
        let content = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, content.count <= 500 else { return false }
        guard !raw.hasPrefix(" "), !raw.hasSuffix(" ") else { return false }
        guard !content.contains("\n") else { return false }
        // Avoid interpreting ordinary currency such as "$5" or "$1,200".
        if content.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) {
            return false
        }
        return content.contains { character in
            character.isLetter || character.isNumber
                || "\\^_{}=+-*/<>()[]|".contains(character)
        }
    }
}

// MARK: - Rendering

final class MathRenderCache {
    static let shared = MathRenderCache()

    struct Rendered {
        let image: NSImage
        let ascent: CGFloat
        let descent: CGFloat
    }

    private var cache: [String: Rendered] = [:]

    func render(
        latex: String,
        fontSize: CGFloat,
        display: Bool,
        textColor: NSColor,
        isDark: Bool
    ) -> Rendered? {
        let color = resolved(textColor, isDark: isDark)
        let colorKey = color.description
        let normalizedLatex = normalize(latex)
        let key = "\(display ? "D" : "I")|\(fontSize)|\(colorKey)|\(normalizedLatex)"
        if let cached = cache[key] { return cached }

        let hasCJK = normalizedLatex.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }

        let rendered: Rendered?
        if hasCJK {
            // Latin Modern Math has no CJK glyphs. Use SwiftMath's fallback
            // font path for formulas such as P(\text{病} \mid +). SwiftMath's
            // fallback glyph does not advance using the CJK font's metrics, so
            // add explicit thin spaces around CJK text blocks to avoid overlap.
            let font = MTFontManager.manager.font(withName: "latinmodern-math", size: fontSize)
            font?.fallbackFont = CTFontCreateWithName("PingFang SC" as CFString, fontSize, nil)
            let imageRenderer = MTMathImage(
                latex: spacedCJKText(in: normalizedLatex),
                fontSize: fontSize,
                textColor: color,
                labelMode: display ? .display : .text,
                textAlignment: display ? .center : .left
            )
            imageRenderer.font = font
            let (error, image) = imageRenderer.asImage()
            if error == nil, let image {
                let descent = image.size.height * 0.32
                rendered = Rendered(image: image, ascent: image.size.height - descent, descent: descent)
            } else {
                rendered = nil
            }
        } else {
            var renderer = MathImage(
                latex: normalizedLatex,
                fontSize: fontSize,
                textColor: color,
                labelMode: display ? .display : .text,
                textAlignment: display ? .center : .left
            )
            renderer.font = .latinModernFont
            let (error, image, layout) = renderer.asImage()
            if error == nil, let image, let layout {
                rendered = Rendered(image: image, ascent: layout.ascent, descent: layout.descent)
            } else {
                rendered = nil
            }
        }
        guard let rendered else { return nil }
        if cache.count > 200 { cache.removeAll(keepingCapacity: true) }
        cache[key] = rendered
        return rendered
    }

    /// SwiftMath does not understand every LaTeX alias. Normalize the common
    /// ones before parsing so a single unsupported command does not drop the
    /// whole formula into the raw-text fallback.
    private func normalize(_ latex: String) -> String {
        var value = latex
        let replacements: [(String, String)] = [
            ("\\dotsb", "\\cdots"),
            ("\\dotsc", "\\ldots"),
            ("\\dotsi", "\\cdots"),
            ("\\dotsm", "\\cdots"),
            ("\\dotso", "\\ldots"),
            ("\\dots", "\\ldots"),
            ("\\underbrace", ""),
            ("\\overbrace", "")
        ]
        for (from, to) in replacements {
            value = value.replacingOccurrences(of: from, with: to)
        }
        return value
    }

    private func spacedCJKText(in latex: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\\text\{([^{}]*)\}"#) else { return latex }
        let ns = latex as NSString
        let matches = regex.matches(in: latex, range: NSRange(location: 0, length: ns.length))
        var result = latex
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let content = ns.substring(with: match.range(at: 1))
            let hasCJK = content.unicodeScalars.contains { scalar in
                switch scalar.value {
                case 0x3400...0x9FFF, 0xF900...0xFAFF: return true
                default: return false
                }
            }
            guard hasCJK else { continue }
            let replacement = "\\quad\\text{\(content)}\\quad"
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }

    private func resolved(_ color: NSColor, isDark: Bool) -> NSColor {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        var resolved = color
        appearance?.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }
}

// MARK: - Inline text view

struct InlineMathText: NSViewRepresentable {
    let content: String
    let font: NSFont
    let textColor: NSColor
    let lineSpacing: CGFloat
    let isDark: Bool
    var showCursor: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MathTextView {
        let view = MathTextView(frame: .zero)
        view.delegate = context.coordinator
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.drawsBackground = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.heightTracksTextView = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: 0
        ]
        return view
    }

    func updateNSView(_ view: MathTextView, context: Context) {
        context.coordinator.parent = self
        let attributed = MathAttributedStringBuilder.make(
            content: content,
            font: font,
            textColor: textColor,
            lineSpacing: lineSpacing,
            isDark: isDark,
            showCursor: showCursor
        )
        if view.textStorage?.isEqual(to: attributed) != true {
            view.textStorage?.setAttributedString(attributed)
            view.invalidateIntrinsicContentSize()
            view.needsDisplay = true
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MathTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 600
        let height = nsView.measure(width: width)
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineMathText?

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }
            if let string = link as? String, let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }
}

final class MathTextView: NSTextView {
    func measure(width: CGFloat) -> CGFloat {
        guard let container = textContainer, let layoutManager else { return 1 }
        container.containerSize = NSSize(width: max(width, 1), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        return max(ceil(layoutManager.usedRect(for: container).height), 1)
    }
}

private enum MathAttributedStringBuilder {
    static func make(
        content: String,
        font: NSFont,
        textColor: NSColor,
        lineSpacing: CGFloat,
        isDark: Bool,
        showCursor: Bool
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let segments = InlineMathParser.segments(in: content)

        for segment in segments {
            switch segment {
            case .text(let value):
                output.append(markdown(value, baseFont: font, color: textColor))
            case .math(let latex):
                if let rendered = MathRenderCache.shared.render(
                    latex: latex,
                    fontSize: font.pointSize,
                    display: false,
                    textColor: textColor,
                    isDark: isDark
                ) {
                    let attachment = NSTextAttachment()
                    attachment.image = rendered.image
                    attachment.bounds = CGRect(
                        x: 0,
                        y: -rendered.descent,
                        width: rendered.image.size.width,
                        height: rendered.image.size.height
                    )
                    output.append(NSAttributedString(attachment: attachment))
                } else {
                    let fallback = NSAttributedString(
                        string: "$\(latex)$",
                        attributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular),
                            .foregroundColor: NSColor.systemOrange
                        ]
                    )
                    output.append(fallback)
                }
            }
        }

        if showCursor {
            output.append(NSAttributedString(
                string: " ▍",
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.controlAccentColor
                ]
            ))
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = 0
        paragraph.lineBreakMode = .byWordWrapping
        if output.length > 0 {
            output.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: output.length))
        }
        return output
    }

    private static func markdown(_ source: String, baseFont: NSFont, color: NSColor) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            return NSAttributedString(string: source, attributes: [
                .font: baseFont,
                .foregroundColor: color
            ])
        }

        let output = NSMutableAttributedString()
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            guard !text.isEmpty else { continue }
            var runFont = baseFont
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]

            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    runFont = NSFont.monospacedSystemFont(ofSize: max(baseFont.pointSize - 1, 9), weight: .regular)
                    attributes[.backgroundColor] = NSColor.textBackgroundColor.withAlphaComponent(0.5)
                } else {
                    if intent.contains(.stronglyEmphasized) {
                        runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask)
                    }
                    if intent.contains(.emphasized) {
                        runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask)
                    }
                    if intent.contains(.strikethrough) {
                        attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    }
                }
            }

            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
            }

            attributes[.font] = runFont
            output.append(NSAttributedString(string: text, attributes: attributes))
        }
        return output
    }
}

// MARK: - Display math

struct MathBlockView: View {
    let latex: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let rendered = MathRenderCache.shared.render(
            latex: latex,
            fontSize: 17,
            display: true,
            textColor: .labelColor,
            isDark: colorScheme == .dark
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                Image(nsImage: rendered.image)
                    .resizable()
                    .frame(width: rendered.image.size.width, height: rendered.image.size.height)
                    .padding(.vertical, 7)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Text("$$\(latex)$$")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.vertical, 4)
        }
    }
}
