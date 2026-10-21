import AppKit
import SwiftUI
import DeepSeekFocusCore

@MainActor
final class SelectionResultPanelController {
    var onContinue: ((String, String) -> Void)?

    private let model: SelectionResultModel
    private var panel: NSPanel?
    private var keyMonitor: Any?

    private let panelSize = NSSize(width: 420, height: 460)

    init(settings: AppSettings) {
        self.model = SelectionResultModel(settings: settings)
    }

    func show(text: String, action: SelectionAction, anchor: NSPoint) {
        model.start(text: text, action: action)
        let panel = makePanelIfNeeded()
        position(panel, near: anchor)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyboardMonitor()
    }

    func hide() {
        removeKeyboardMonitor()
        model.cancel()
        panel?.orderOut(nil)
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(
            rootView: SelectionResultView(
                model: model,
                onClose: { [weak self] in self?.hide() },
                onContinue: { [weak self] question, answer in
                    guard let self else { return }
                    self.hide()
                    self.onContinue?(question, answer)
                }
            )
        )
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, near anchor: NSPoint) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        var origin = NSPoint(
            x: anchor.x - panelSize.width / 2,
            y: anchor.y + 10
        )
        if origin.y + panelSize.height > visible.maxY {
            origin.y = anchor.y - panelSize.height - 10
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panelSize.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panelSize.height - 8)
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: false)
    }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.hide()
            return nil
        }
    }

    private func removeKeyboardMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
