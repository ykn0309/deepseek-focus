import AppKit
import SwiftUI

/// AppKit-backed composer. A native text view gives reliable IME composition, multiline
/// editing and a properly working ⇧Return, none of which are easy to guarantee with a
/// SwiftUI TextField on older macOS versions.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var placeholder: String
    var focusToken: Int
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ComposerScrollView {
        let scrollView = ComposerScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none

        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 2, height: 3)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3.5
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        textView.defaultParagraphStyle = paragraph
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.typingAttributes = attributes
        textView.placeholder = placeholder
        textView.string = text
        if !text.isEmpty {
            textView.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: textView.string.utf16.count))
        }
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))

        scrollView.documentView = textView
        scrollView.composerTextView = textView
        scrollView.onHeightChange = { [weak coordinator = context.coordinator] newHeight in
            coordinator?.reportHeight(newHeight)
        }
        context.coordinator.textView = textView
        context.coordinator.lastFocusToken = focusToken

        DispatchQueue.main.async {
            scrollView.updateDocumentLayout()
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: ComposerScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.composerTextView else { return }
        textView.placeholder = placeholder
        scrollView.onHeightChange = { [weak coordinator = context.coordinator] newHeight in
            coordinator?.reportHeight(newHeight)
        }

        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            if !text.isEmpty {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: textView.defaultParagraphStyle ?? NSParagraphStyle.default
                ]
                textView.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: textView.string.utf16.count))
            }
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            DispatchQueue.main.async {
                scrollView.updateDocumentLayout()
            }
        }

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        textView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: NSTextView?
        var lastFocusToken: Int = -1

        init(parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            (textView.enclosingScrollView as? ComposerScrollView)?.updateDocumentLayout()
            textView.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            textView.needsDisplay = true
        }

        func reportHeight(_ height: CGFloat) {
            let clamped = min(max(height, 24), 82)
            guard abs(parent.height - clamped) > 0.5 else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, abs(self.parent.height - clamped) > 0.5 else { return }
                self.parent.height = clamped
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if textView.hasMarkedText() { return false }
                let modifiers = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
                if modifiers.contains(.shift) { return false }
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

final class ComposerScrollView: NSScrollView {
    weak var composerTextView: PlaceholderTextView?
    var onHeightChange: ((CGFloat) -> Void)?

    private var lastReportedHeight: CGFloat = -1

    override func layout() {
        super.layout()
        updateDocumentLayout()
    }

    func updateDocumentLayout() {
        guard let textView = composerTextView else { return }
        let width = max(contentSize.width, 1)
        guard let container = textView.textContainer, let layoutManager = textView.layoutManager else { return }

        container.containerSize = NSSize(
            width: max(width - textView.textContainerInset.width * 2, 1),
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container).height
        let contentHeight = ceil(used + textView.textContainerInset.height * 2 + 2)
        let desiredVisibleHeight = min(max(contentHeight, 24), 82)
        let desiredDocumentHeight = max(contentSize.height, contentHeight)
        let newFrame = NSRect(x: 0, y: 0, width: width, height: desiredDocumentHeight)
        if textView.frame != newFrame {
            textView.frame = newFrame
        }
        textView.needsDisplay = true

        if abs(desiredVisibleHeight - lastReportedHeight) > 0.5 {
            lastReportedHeight = desiredVisibleHeight
            let callback = onHeightChange
            DispatchQueue.main.async {
                callback?(desiredVisibleHeight)
            }
        }
    }
}

final class PlaceholderTextView: NSTextView {
    var placeholder: String = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), !placeholder.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.placeholderTextColor,
            .paragraphStyle: paragraph
        ]
        let origin = NSPoint(x: textContainerInset.width + 1, y: textContainerInset.height)
        let rect = NSRect(
            x: origin.x,
            y: origin.y,
            width: max(bounds.width - origin.x - 2, 1),
            height: max(bounds.height - origin.y, 20)
        )
        (placeholder as NSString).draw(in: rect, withAttributes: attributes)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
    }

    override func unmarkText() {
        super.unmarkText()
        needsDisplay = true
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }
}
