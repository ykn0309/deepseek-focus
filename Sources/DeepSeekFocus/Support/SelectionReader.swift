import AppKit
import ApplicationServices

struct SelectionContext {
    let text: String
    let anchor: NSPoint
}

enum SelectionReader {
    static func read() -> SelectionContext? {
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
}
