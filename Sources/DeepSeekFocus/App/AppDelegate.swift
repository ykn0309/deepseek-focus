import AppKit
import Combine
import DeepSeekFocusCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var modelCatalog: ModelCatalog!
    private var historyStore: ConversationHistoryStore!
    private var panelController: SpotlightPanelController!
    private var hotKeyManager: HotKeyManager!
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu?
    private var statusShortcutInfoItem: NSMenuItem?
    private var statusCheckUpdateItem: NSMenuItem?
    private let updateChecker = UpdateChecker.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings = AppSettings()
        settings.onLanguageChange = { [weak self] in
            self?.languageDidChange()
        }
        modelCatalog = ModelCatalog(settings: settings)
        historyStore = ConversationHistoryStore()
        panelController = SpotlightPanelController(
            settings: settings,
            modelCatalog: modelCatalog,
            historyStore: historyStore
        )

        installMainMenu()
        installStatusItem()
        updateChecker.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusUpdateItem()
            }
            .store(in: &cancellables)
        settings.$showMenuBarIcon
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                self?.statusItem?.isVisible = visible
            }
            .store(in: &cancellables)

        hotKeyManager = HotKeyManager { [weak self] in
            self?.panelController.toggle()
        }
        settings.hotKeyRegistrationHandler = { [weak self] shortcut in
            guard let self else { return "快捷键服务尚未就绪。" }
            let result = self.hotKeyManager.register(shortcut)
            if result == nil {
                self.updateShortcutPresentation(shortcut.displayString)
            }
            return result
        }
        if let error = hotKeyManager.register(settings.shortcut) {
            settings.reportShortcutError(error)
            // Never leave the app with neither a working shortcut nor a menu
            // bar icon; otherwise there would be no way to reopen it.
            if !settings.showMenuBarIcon {
                settings.showMenuBarIcon = true
            }
        } else {
            settings.shortcutError = nil
        }

        Task { [weak self] in
            guard let self, self.settings.hasAPIKey else { return }
            await self.modelCatalog.refreshIfStale()
        }

        let firstLaunch = !settings.hasLaunchedBefore
        settings.markLaunched()

        if firstLaunch || !settings.hasAPIKey {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showSettings()
            }
        }

        // Development/testing hook: show the panel without using the global
        // hotkey, so an isolated test copy can be driven safely.
        if ProcessInfo.processInfo.environment["DEEPSEEK_FOCUS_SHOW_ON_LAUNCH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.panelController.showFresh()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidResignActive(_ notification: Notification) {
        panelController?.hide()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.viewModel.persistCurrentSessionIfNeeded()
        settings?.flushAPIKey()
        hotKeyManager?.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.showFresh()
        return true
    }

    // MARK: - Actions

    @objc private func showPanelFromMenu() {
        panelController.showFresh()
    }

    @objc private func startNewConversation() {
        guard settings.hasAPIKey else {
            showSettings()
            return
        }
        panelController.viewModel.newConversation()
        panelController.show()
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: L10n.string("DeepSeek 聚焦"),
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
            .credits: NSAttributedString(
                string: L10n.string("像聚焦搜索一样，随时向 DeepSeek 提问。\n\nAPI Key 仅保存在本机应用数据文件中，对话直接发送给 DeepSeek。"),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showSettings() {
        panelController?.showSettings()
    }

    // MARK: - Menu

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: L10n.string("DeepSeek 聚焦"))
        appMenuItem.submenu = appMenu

        let about = NSMenuItem(title: L10n.string("关于 DeepSeek 聚焦"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L10n.string("设置…"), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: L10n.string("服务"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: L10n.string("服务"))
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())

        let hide = NSMenuItem(title: L10n.string("隐藏 DeepSeek 聚焦"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(hide)

        let hideOthers = NSMenuItem(title: L10n.string("隐藏其他"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        hideOthers.target = NSApp
        appMenu.addItem(hideOthers)

        let showAll = NSMenuItem(title: L10n.string("显示全部"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAll.target = NSApp
        appMenu.addItem(showAll)
        appMenu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.string("退出 DeepSeek 聚焦"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L10n.string("编辑"))
        editMenuItem.submenu = editMenu

        let undo = NSMenuItem(title: L10n.string("撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: L10n.string("重做"), action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        let cut = NSMenuItem(title: L10n.string("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copy = NSMenuItem(title: L10n.string("复制"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let paste = NSMenuItem(title: L10n.string("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let selectAll = NSMenuItem(title: L10n.string("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        [undo, redo, cut, copy, paste].forEach { editMenu.addItem($0) }
        editMenu.addItem(.separator())
        editMenu.addItem(selectAll)

        let conversationMenuItem = NSMenuItem()
        mainMenu.addItem(conversationMenuItem)
        let conversationMenu = NSMenu(title: L10n.string("对话"))
        conversationMenuItem.submenu = conversationMenu

        let open = NSMenuItem(title: L10n.string("打开搜索"), action: #selector(showPanelFromMenu), keyEquivalent: "")
        open.target = self
        conversationMenu.addItem(open)

        let newConversation = NSMenuItem(title: L10n.string("新对话"), action: #selector(startNewConversation), keyEquivalent: "n")
        newConversation.target = self
        conversationMenu.addItem(newConversation)

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: L10n.string("窗口"))
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(title: L10n.string("关闭窗口"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: L10n.string("最小化"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func updateShortcutPresentation(_ displayString: String) {
        statusItem?.button?.toolTip = L10n.format("DeepSeek 聚焦 · %@", displayString)
        statusShortcutInfoItem?.title = L10n.format("唤起快捷键：%@", displayString)
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = settings.showMenuBarIcon
        if let button = statusItem.button {
            let whaleURL = Bundle.main.url(forResource: "MenuBarWhale", withExtension: "png")
            let whale = whaleURL.flatMap { NSImage(contentsOf: $0) }
            let fallback = NSImage(
                systemSymbolName: "sparkle.magnifyingglass",
                accessibilityDescription: L10n.string("DeepSeek 聚焦")
            )
            let image = whale ?? fallback
            image?.isTemplate = true
            if let whale {
                whale.size = NSSize(width: 18, height: 18)
            }
            button.image = image
            if image == nil {
                button.title = "⌕"
            }
            button.toolTip = L10n.format("DeepSeek 聚焦 · %@", settings.shortcut.displayString)
            button.setAccessibilityLabel(L10n.string("DeepSeek 聚焦"))
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusMenu = makeStatusMenu()
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let shortcutInfo = NSMenuItem(
            title: L10n.format("唤起快捷键：%@", settings.shortcut.displayString),
            action: nil,
            keyEquivalent: ""
        )
        shortcutInfo.isEnabled = false
        statusShortcutInfoItem = shortcutInfo
        menu.addItem(shortcutInfo)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L10n.string("设置…"), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let checkForUpdates = NSMenuItem(
            title: L10n.string(statusUpdateTitleKey),
            action: #selector(checkForUpdatesFromMenu),
            keyEquivalent: ""
        )
        checkForUpdates.target = self
        checkForUpdates.isEnabled = !updateChecker.isBusy
        menu.addItem(checkForUpdates)
        statusCheckUpdateItem = checkForUpdates

        let about = NSMenuItem(title: L10n.string("关于 DeepSeek 聚焦"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.string("退出"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu, let menu = statusMenu {
            // Let AppKit position the status menu. A manual popUp point above
            // the status item makes macOS treat the menu as partially
            // off-screen and add a scroll indicator, hiding the first item.
            statusItem.popUpMenu(menu)
        } else {
            panelController.showFresh()
        }
    }

    private var statusUpdateTitleKey: String {
        switch updateChecker.state {
        case .checking: return "正在检查更新…"
        case .downloading: return "正在下载更新…"
        case .installing: return "正在安装更新…"
        default: return "检查更新…"
        }
    }

    private func refreshStatusUpdateItem() {
        guard let item = statusCheckUpdateItem else { return }
        item.title = L10n.string(statusUpdateTitleKey)
        item.isEnabled = !updateChecker.isBusy
    }

    @objc private func checkForUpdatesFromMenu() {
        guard !updateChecker.isBusy else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.updateChecker.check()
            self.presentUpdateResult()
        }
    }

    private func presentUpdateResult() {
        switch updateChecker.state {
        case .idle, .checking, .downloading, .installing:
            break
        case .upToDate:
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = L10n.string("已是最新版本")
            alert.informativeText = L10n.format("当前版本：%@", "v\(updateChecker.currentVersion)")
            alert.addButton(withTitle: L10n.string("好"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        case .available(let version, _):
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = L10n.format("发现新版本 v%@", version)
            alert.informativeText = L10n.string("更新会在后台下载，完成后应用会自动重启。")
            alert.addButton(withTitle: L10n.string("下载并安装"))
            alert.addButton(withTitle: L10n.string("稍后"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                Task { [weak self] in
                    guard let self else { return }
                    await self.updateChecker.downloadAndInstall()
                    if case .failed = self.updateChecker.state {
                        self.presentUpdateResult()
                    }
                }
            }
        case .failed(let message):
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.string("检查更新失败")
            alert.informativeText = message
            alert.addButton(withTitle: L10n.string("好"))
            let hasReleasePage = updateChecker.releasePageURL != nil
            if hasReleasePage {
                alert.addButton(withTitle: L10n.string("打开 Release 页面"))
            }
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if hasReleasePage,
               response == .alertSecondButtonReturn,
               let releasePageURL = updateChecker.releasePageURL {
                NSWorkspace.shared.open(releasePageURL)
            }
        }
    }

    private func languageDidChange() {
        installMainMenu()
        statusMenu = makeStatusMenu()
        updateShortcutPresentation(settings.shortcut.displayString)
        statusItem?.button?.toolTip = L10n.format("DeepSeek 聚焦 · %@", settings.shortcut.displayString)
        statusItem?.button?.setAccessibilityLabel(L10n.string("DeepSeek 聚焦"))
    }

}
