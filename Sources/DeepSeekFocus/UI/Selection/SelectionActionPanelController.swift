import AppKit
import SwiftUI
import DeepSeekFocusCore

@MainActor
final class SelectionActionPanelController {
    var onSelect: ((String, SelectionAction) -> Void)?

    private var panel: NSPanel?
    private var currentText = ""
    private var clickMonitor: Any?
    private var keyMonitor: Any?

    private let panelSize = NSSize(width: 232, height: 36)

    func show(text: String, near anchor: NSPoint) {
        currentText = text
        let panel = makePanelIfNeeded()
        position(panel, near: anchor)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitors()
    }

    func hide() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(
            rootView: SelectionActionBar { [weak self] action in
                guard let self else { return }
                let text = self.currentText
                self.hide()
                self.onSelect?(text, action)
            }
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

    private func installDismissMonitors() {
        removeDismissMonitors()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.hide()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.hide()
            return nil
        }
    }

    private func removeDismissMonitors() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
