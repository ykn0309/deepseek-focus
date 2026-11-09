import AppKit
import Carbon.HIToolbox
import SwiftUI
import DeepSeekFocusCore

final class SpotlightPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SpotlightPanelController {
    private let panel: SpotlightPanel
    private let model: SpotlightViewModel
    private let settings: AppSettings
    private let modelCatalog: ModelCatalog
    private var keyMonitor: Any?
    private var contentLoaded = false
    private var isOrdinaryWindow = false

    init(settings: AppSettings, modelCatalog: ModelCatalog, historyStore: ConversationHistoryStore) {
        self.settings = settings
        self.modelCatalog = modelCatalog
        let viewModel = SpotlightViewModel(
            settings: settings,
            modelCatalog: modelCatalog,
            historyStore: historyStore
        )
        self.model = viewModel

        let panel = SpotlightPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // The SwiftUI hierarchy is intentionally created on first summon, not
        // at launch. The hidden panel still exists, but its heavy view tree does
        // not consume memory while the app idles in the menu bar.
        panel.contentView = NSView()
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.appearance = nil
        self.panel = panel

        viewModel.onRequestExpand = { [weak self] in
            self?.animate(toConversation: true)
        }
        viewModel.onRequestCollapse = { [weak self] in
            self?.animate(toConversation: false)
        }
        viewModel.onHide = { [weak self] in
            self?.hide()
        }
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    var viewModel: SpotlightViewModel {
        model
    }

    func toggle() {
        guard settings.hasAPIKey else {
            showSettings()
            return
        }
        if panel.isVisible {
            hide()
        } else {
            showFresh()
        }
    }

    /// Starts a one-shot query from text selected in another application.
    /// The selected text becomes a fresh user turn and the panel expands.
    func startSelectionAction(text: String, action: SelectionAction) {
        guard settings.hasAPIKey else {
            showSettings()
            return
        }
        restoreSpotlightMode()
        model.beginFreshInvocation()
        model.input = SelectionPrompt.make(
            text: text,
            action: action,
            targetLanguage: settings.translationTarget
        )
        show()
        model.submit()
    }

    /// Promotes a finished quick answer into a real session without issuing
    /// the same request again.
    func continueFromSelection(question: String, answer: String) {
        model.continueFromSelection(question: question, answer: answer)
        show()
    }

    /// Summoning the palette always starts from a clean search field, but a
    /// missing API key must be resolved before the user can reach the composer.
    func showFresh() {
        guard settings.hasAPIKey else {
            showSettings()
            return
        }
        restoreSpotlightMode()
        model.beginFreshInvocation()
        show()
    }

    func showSettings() {
        model.openSettingsPage()
        if !panel.isVisible {
            show()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            installKeyboardMonitor()
        }
    }

    func show() {
        if isOrdinaryWindow, !panel.isVisible {
            restoreSpotlightMode()
        }
        loadContentIfNeeded()
        let screen = screenForPresentation()
        let frame = targetFrame(conversation: model.isConversation, screen: screen)
        let shouldExpand = model.isConversation
        panel.setFrame(frame, display: false)
        panel.alphaValue = 1

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyboardMonitor()
        model.requestFocus()

        if shouldExpand {
            model.requestFocus()
        }

        // A quiet entrance rather than a hard cut.
        let startFrame = frame.offsetBy(dx: 0, dy: -6)
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.17
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.panel.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKey()
            self.model.requestFocus()
        }
    }

    func promoteToOrdinaryWindow() {
        if isOrdinaryWindow {
            let contentFrame = panel.frame
            restoreSpotlightMode()
            panel.setFrame(contentFrame.insetBy(dx: -SpotlightMetrics.shadowInset, dy: -SpotlightMetrics.shadowInset), display: true)
            installKeyboardMonitor()
            return
        }
        let contentFrame = panel.frame.insetBy(dx: SpotlightMetrics.shadowInset, dy: SpotlightMetrics.shadowInset)
        isOrdinaryWindow = true
        model.promoteToOrdinaryWindowLayout()
        installKeyboardMonitor()
        // Keep the conversation as a regular-level window without adding
        // system chrome. The expanded panel already has its own visual frame;
        // a title bar would make the window chrome wider than that surface.
        panel.styleMask = [.borderless, .resizable]
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.level = .normal
        panel.collectionBehavior = [.managed, .fullScreenAuxiliary]
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.setFrame(contentFrame, display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreSpotlightMode() {
        guard isOrdinaryWindow else { return }
        isOrdinaryWindow = false
        model.restoreSpotlightLayout()
        panel.styleMask = [.borderless, .fullSizeContentView]
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hasShadow = false
    }

    func hide() {
        guard panel.isVisible else { return }
        if isOrdinaryWindow {
            panel.orderOut(nil)
            return
        }
        removeKeyboardMonitor()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    func hideOnDeactivate() {
        guard !isOrdinaryWindow else { return }
        hide()
    }

    private func loadContentIfNeeded() {
        guard !contentLoaded else { return }
        contentLoaded = true

        let rootView = SpotlightRootView(
            model: model,
            onPromoteToWindow: { [weak self] in self?.promoteToOrdinaryWindow() },
            settings: settings,
            modelCatalog: modelCatalog
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.frame = panel.contentLayoutRect
        panel.contentView = hostingView
    }

    /// Re-evaluate the frame, e.g. after the system changes displays.
    func refreshFrame() {
        guard panel.isVisible else { return }
        let frame = targetFrame(conversation: model.isConversation, screen: panel.screen ?? screenForPresentation())
        panel.setFrame(frame, display: true)
    }

    private func animate(toConversation: Bool) {
        guard panel.isVisible else { return }
        let screen = panel.screen ?? screenForPresentation()
        let frame = targetFrame(conversation: toConversation, screen: screen)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func targetFrame(conversation: Bool, screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let preferredWidth = conversation
            ? SpotlightMetrics.expandedVisualWidth
            : SpotlightMetrics.initialVisualWidth
        let width = min(preferredWidth, max(560, visible.width - 100))

        let height: CGFloat
        if conversation {
            let available = visible.height - 84
            height = min(SpotlightMetrics.expandedMaxHeight, max(430, available))
        } else {
            height = SpotlightMetrics.initialVisualHeight
        }

        let topFraction = conversation
            ? SpotlightMetrics.expandedTopFraction
            : SpotlightMetrics.initialTopFraction
        let minimumTopGap: CGFloat = conversation ? 44 : 96
        let topGap = max(minimumTopGap, visible.height * topFraction)
        var visual = NSRect(
            x: visible.midX - width / 2,
            y: visible.maxY - topGap - height,
            width: width,
            height: height
        )
        if visual.minY < visible.minY + 18 {
            visual.origin.y = visible.minY + 18
        }
        if visual.maxY > visible.maxY - 18 {
            visual.origin.y = visible.maxY - 18 - visual.height
        }

        guard !isOrdinaryWindow else { return visual }
        return visual.insetBy(
            dx: -SpotlightMetrics.shadowInset,
            dy: -SpotlightMetrics.shadowInset
        )
    }

    private func screenForPresentation() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
    }

    // MARK: - Keyboard

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func removeKeyboardMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let editor = panel.firstResponder as? NSTextView
        let composing = editor?.hasMarkedText() == true

        if event.keyCode == 53 { // Escape
            if composing { return event }
            if model.isShowingSettings {
                if settings.hasAPIKey {
                    model.closeSettingsPage()
                } else {
                    hide()
                }
                return nil
            }
            hide()
            return nil
        }

        if !composing, !flags.contains(.command), !flags.contains(.option), !flags.contains(.control), !flags.contains(.shift) {
            if event.keyCode == UInt16(kVK_DownArrow) {
                if !model.isConversation {
                    guard model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return event }
                    model.expandToConversation()
                    return nil
                }
                guard !model.isShowingSettings,
                      model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return event }
                model.navigateHistory(by: 1)
                return nil
            }
            if event.keyCode == UInt16(kVK_UpArrow), model.isConversation, !model.isShowingSettings,
               model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.navigateHistory(by: -1)
                return nil
            }
        }

        if flags.contains(.command), !flags.contains(.option), !flags.contains(.control) {
            if !composing,
               model.isConversation,
               !model.isShowingSettings,
               settings.sidebarShortcut.matches(event: event) {
                model.toggleHistory()
                return nil
            }
            if event.charactersIgnoringModifiers?.lowercased() == "n" {
                if settings.hasAPIKey {
                    model.newConversation()
                } else {
                    showSettings()
                }
                return nil
            }
            if event.charactersIgnoringModifiers == "," {
                model.openSettingsPage()
                return nil
            }
            if event.charactersIgnoringModifiers?.lowercased() == "w" {
                hide()
                return nil
            }
        }

        return event
    }
}
