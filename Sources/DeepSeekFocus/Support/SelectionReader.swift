import AppKit
import ApplicationServices

struct SelectionContext {
    let text: String
    let anchor: NSPoint
}

enum SelectionReader {
    static func read(allowClipboardFallback: Bool = true) -> SelectionContext? {
        if let context = readFromAccessibility() {
            return context
        }
        // Some Chromium-based apps do not expose the selected text through the
        // Accessibility API. Fall back to a transient Cmd-C, then restore the
        // previous clipboard contents only if nobody else changed it meanwhile.
        guard allowClipboardFallback, isChromiumFrontmost() else { return nil }
        guard let copied = copySelectedTextViaClipboard() else { return nil }
        let text = copied.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return SelectionContext(text: String(text.prefix(12_000)), anchor: mouseAnchor())
    }

    private static func readFromAccessibility() -> SelectionContext? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
              let focusedRef else {
            return nil
        }
        let element = focusedRef as! AXUIElement

        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &textRef
        ) == .success,
              let rawText = textRef as? String else {
            return nil
        }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let anchor = selectionAnchor(element: element) ?? mouseAnchor()
        return SelectionContext(text: String(text.prefix(12_000)), anchor: anchor)
    }

    private static func selectionAnchor(element: AXUIElement) -> NSPoint? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success,
              let rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range),
              let rangeValue = AXValueCreate(.cfRange, &range) else {
            return nil
        }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef
        ) == .success,
              let boundsRef,
              CFGetTypeID(boundsRef) == AXValueGetTypeID() else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect),
              rect.width > 0, rect.height > 0 else {
            return nil
        }

        // Accessibility uses a top-left screen origin; the panel uses AppKit's
        // bottom-left screen coordinates.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSPoint(x: rect.midX, y: mainHeight - rect.maxY)
    }

    private static func mouseAnchor() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        return NSPoint(x: mouse.x, y: mouse.y + 12)
    }

    // MARK: - Clipboard fallback

    private struct ClipboardSnapshot {
        var items: [[NSPasteboard.PasteboardType: Data]]
    }

    private static let chromiumBundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "org.chromium.Chromium",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera"
    ]

    private static func isChromiumFrontmost() -> Bool {
        guard let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return chromiumBundleIdentifiers.contains(identifier)
    }

    private static func copySelectedTextViaClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        let snapshot = snapshot(of: pasteboard)

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            return nil
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(50_000)
        up.post(tap: .cghidEventTap)

        var observedChange: Int?
        var copiedText: String?
        let deadline = Date().addingTimeInterval(0.55)
        while Date() < deadline {
            let change = pasteboard.changeCount
            if change != before {
                observedChange = change
                if let text = pasteboard.string(forType: .string), !text.isEmpty {
                    copiedText = text
                    break
                }
            }
            usleep(20_000)
        }

        // Only restore when the pasteboard still contains the temporary copy.
        // If another app changed it in the meantime, its newer contents win.
        if let observedChange, pasteboard.changeCount == observedChange {
            restore(snapshot, to: pasteboard)
        }
        return copiedText
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> ClipboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type] = data
                }
            }
            return values
        }
        return ClipboardSnapshot(items: items)
    }

    private static func restore(_ snapshot: ClipboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let items = snapshot.items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
