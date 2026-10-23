#if DEBUG
import AppKit
import SwiftUI
import DeepSeekFocusCore

/// Isolated regression checks and a preview using synthetic data. No real keys,
/// history, global shortcuts, login items or update checks are involved.
@MainActor
enum ExperienceChecks {
    static func run(application: NSApplication) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("focus-checks-\(UUID())")
        let suite = "com.deepseekfocus.checks.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let settings = AppSettings(defaults: defaults,
                                   credentialStore: APIKeyStore(fileURL: directory.appendingPathComponent("key.json")),
                                   environment: [:])
        settings.appLanguage = CommandLine.arguments.contains("--english") ? .english : .simplifiedChinese
        let catalog = ModelCatalog(settings: settings, defaults: defaults)
        let historyURL = directory.appendingPathComponent("history.json")
        let history = ConversationHistoryStore(fileURL: historyURL)
        let model = SpotlightViewModel(settings: settings, modelCatalog: catalog, historyStore: history)
        model.continueFromSelection(question: "如何让工作更专注？", answer: """
        ## 从一件小事开始
        把下一步写成一个**具体、可执行的动作**，再给它一段不被打断的时间。

        1. 选择今天最重要的一件事。
        2. 关闭暂时不需要的通知。
        3. 完成后留下一句总结。

        > 专注不是一次做更多，而是把眼前的一件事做好。

        ```swift
        let nextStep = "写下第一个想法"
        print(nextStep)
        ```
        """)
        let first = history.sessions[0]
        model.input = "这是第一段尚未发送的草稿"
        model.newConversation()
        model.input = "这是新会话草稿"
        model.loadHistorySession(first)
        precondition(model.input == "这是第一段尚未发送的草稿", "Existing session draft was lost")
        model.loadHistorySession(first)
        precondition(model.input == "这是第一段尚未发送的草稿", "Selecting the same row lost the draft")
        model.newConversation()
        precondition(model.input == "这是新会话草稿", "New conversation draft was lost")
        model.loadHistorySession(first)
        model.input = "  \n "
        precondition(!model.canSend, "Whitespace must not be sendable")
        model.input = ""
        precondition(ConversationHistoryStore(fileURL: historyURL).sessions.count == 1, "History round trip failed")
        var stopped = first
        stopped.turns[0].wasStopped = true
        history.upsert(stopped)
        model.newConversation()
        model.loadHistorySession(stopped)
        precondition(model.turns[0].wasStopped, "Stopped state was lost on restore")
        model.deleteHistorySession(stopped)
        precondition(history.sessions.isEmpty && model.turns.isEmpty, "Delete did not clear current session")
        let impossible = ConversationHistoryStore(fileURL: historyURL.appendingPathComponent("child.json"))
        impossible.upsert(first)
        precondition(impossible.saveError != nil, "Write failures must be visible")
        history.upsert(first)
        model.loadHistorySession(first)
        model.isHistoryPresented = true
        print("ExperienceChecks: draft switching, same-row selection, blank input, history round trip, stopped state, deletion and write-failure feedback passed.")
        guard CommandLine.arguments.contains("--experience-preview") else { return }
        if CommandLine.arguments.contains("--empty") { model.newConversation() }
        if CommandLine.arguments.contains("--settings") { model.openSettingsPage() }
        if CommandLine.arguments.contains("--selection") {
            application.setActivationPolicy(.regular)
            let preview = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 140),
                                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
            preview.title = "Selection Bar Preview"
            preview.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
            preview.contentView = NSHostingView(rootView: SelectionActionBar { _ in }
                .environment(\.locale, settings.appLanguage.locale)
                .frame(width: 400, height: 140))
            preview.center()
            preview.makeKeyAndOrderFront(nil)
            application.activate(ignoringOtherApps: true)
            application.run()
            withExtendedLifetime(preview) { }
            return
        }
        application.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "DeepSeek Focus · Isolated Preview"
        window.minSize = NSSize(width: 900, height: 600)
        window.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: SpotlightRootView(model: model, settings: settings, modelCatalog: catalog))
        window.setContentSize(NSSize(width: 1000, height: 760))
        window.center()
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
        application.run()
        withExtendedLifetime(window) { }
    }
}
#endif
