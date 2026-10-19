import SwiftUI
import DeepSeekFocusCore

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var modelCatalog: ModelCatalog
    var onBack: () -> Void

    @State private var revealAPIKey = false
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @Environment(\.openURL) private var openURL

    private var selectedModel: DeepSeekModel {
        modelCatalog.selectedModel
    }

    private var reasoningLevels: [String] {
        settings.reasoningLevels(for: selectedModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            DividerLine()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    updateSection
                    connectionSection
                    behaviorSection
                    modelSection
                    privacyNote
                }
                .padding(.horizontal, 26)
                .padding(.top, 20)
                .padding(.bottom, 26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            settings.reconcile(with: modelCatalog.models)
            guard settings.hasAPIKey else { return }
            Task {
                await modelCatalog.refreshIfStale()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 11) {
            FocusIconButton(systemName: "chevron.left", help: "返回") {
                onBack()
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text("设置")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.82))
                Text("更改会自动保存")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)
                Text(L10n.string(modelCatalog.connectionState.titleKey))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.04), in: Capsule())
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }


    // MARK: - Connection

    private var connectionSection: some View {
        SettingsSection(
            title: "连接 DeepSeek",
            subtitle: "API Key 仅保存在这台 Mac 的应用数据目录中（文件权限 600，不使用系统钥匙串），并直接从本机发送给 DeepSeek。",
            icon: "bolt.horizontal.circle"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        if revealAPIKey {
                            TextField("sk-…", text: $settings.apiKey)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                        } else {
                            SecureField("sk-…", text: $settings.apiKey)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
                    }
                    .onSubmit {
                        syncModels()
                    }

                    Button {
                        revealAPIKey.toggle()
                    } label: {
                        Image(systemName: revealAPIKey ? "eye.slash" : "eye")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .help(revealAPIKey ? "隐藏 API Key" : "显示 API Key")

                    Button {
                        syncModels()
                    } label: {
                        HStack(spacing: 5) {
                            if modelCatalog.isLoading {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            Text(LocalizedStringKey(modelCatalog.isLoading ? "正在验证" : "验证并同步"))
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(FocusTheme.accentGradient, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(modelCatalog.isLoading || !settings.hasAPIKey)
                    .opacity(!settings.hasAPIKey ? 0.48 : 1)
                    .help("验证 API Key 并从 DeepSeek 获取最新模型列表")
                }

                connectionFeedback

                HStack(spacing: 5) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                    Link("获取 DeepSeek API Key", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                        .font(.system(size: 10.5))
                }
                .foregroundStyle(.tertiary)

                if let credentialError = settings.credentialError {
                    Label(credentialError, systemImage: "key.slash")
                        .font(.system(size: 10.5))
                        .foregroundStyle(FocusTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        SettingsSection(
            title: "新会话默认配置",
            subtitle: "快捷键唤起或新建会话时使用；在单个会话里修改的配置只记录在该会话中。模型列表来自 DeepSeek 官方 /models 接口。",
            icon: "slider.horizontal.3"
        ) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    Text("模型")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 66, alignment: .leading)

                    FocusSelectMenu(
                        options: modelCatalog.models,
                        selection: selectedModel,
                        title: { $0.displayName },
                        width: 240,
                        onSelect: { settings.selectModel($0) }
                    )

                    Spacer()

                    Button {
                        Task { await modelCatalog.refresh(apiKey: settings.apiKey) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 25, height: 25)
                            .background(Color.primary.opacity(0.04), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(modelCatalog.isLoading || !settings.hasAPIKey)
                    .help("重新获取模型列表")
                }

                HStack(spacing: 8) {
                    Text(selectedModel.id)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(modelFacts)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 76)

                HStack(spacing: 7) {
                    Image(systemName: modelCatalog.error == nil ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.system(size: 9.5))
                    Text(modelCatalog.statusText)
                        .font(.system(size: 10.3))
                        .lineLimit(2)
                }
                .foregroundStyle(modelCatalog.error == nil ? Color.secondary.opacity(0.65) : FocusTheme.warning)
                .padding(.leading, 76)

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("推理等级")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("新会话默认")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.quaternary)
                    }

                    HStack(spacing: 6) {
                        ForEach(reasoningLevels, id: \.self) { level in
                            let isSelected = settings.reasoningEffort == level
                            Button {
                                settings.selectReasoningLevel(level, model: selectedModel)
                            } label: {
                                Text(ReasoningEffortCopy.title(for: level))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(isSelected ? .white : .primary.opacity(0.66))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(isSelected
                                                  ? AnyShapeStyle(FocusTheme.accentGradient)
                                                  : AnyShapeStyle(Color.primary.opacity(0.045)))
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(
                                                isSelected ? Color.clear : Color.primary.opacity(0.055),
                                                lineWidth: 0.7
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(LocalizedStringKey(ReasoningEffortCopy.detail(for: settings.reasoningEffort)))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("联网搜索")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("新会话默认")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.quaternary)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        ForEach(WebSearchMode.allCases) { mode in
                            searchModeCard(mode)
                        }
                    }

                    Label("搜索请求通过 DeepSeek 官方 /v1/tools/search 接口完成，可能会产生少量调用费用。", systemImage: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Search


    private func searchModeCard(_ mode: WebSearchMode) -> some View {
        let isSelected = settings.webSearchMode == mode
        return Button {
            settings.webSearchMode = mode
        } label: {
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? FocusTheme.accent : Color.primary.opacity(0.18),
                            lineWidth: isSelected ? 5 : 1
                        )
                        .frame(width: 14, height: 14)
                }
                .frame(width: 16, height: 16)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: mode == .automatic ? "sparkle.magnifyingglass" : "globe.slash")
                            .font(.system(size: 10))
                        Text(LocalizedStringKey(mode.title))
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    Text(LocalizedStringKey(mode.detail))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? FocusTheme.accent.opacity(0.065) : Color.primary.opacity(0.025))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected ? FocusTheme.accent.opacity(0.35) : Color.primary.opacity(0.06),
                                lineWidth: isSelected ? 1 : 0.7
                            )
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        SettingsSection(
            title: "唤起与应用",
            subtitle: nil,
            icon: "command"
        ) {
            ShortcutSettingRow(
                icon: "keyboard",
                title: "全局唤起",
                subtitle: "在任何应用中唤出 DeepSeek Focus",
                shortcut: settings.shortcut,
                error: settings.shortcutError,
                onApply: { settings.applyShortcut($0) },
                onReset: { _ = settings.applyShortcut(.default) }
            )

            Divider()

            ShortcutSettingRow(
                icon: "rectangle.expand.vertical",
                title: "展开快捷键",
                subtitle: "从初始输入框进入展开后的对话页",
                shortcut: settings.expandShortcut,
                error: settings.expandShortcutError,
                onApply: { settings.applyExpandShortcut($0) },
                onReset: { settings.resetExpandShortcut() }
            )

            Divider()

            ShortcutSettingRow(
                icon: "sidebar.left",
                title: "侧边栏快捷键",
                subtitle: "在展开页中显示或隐藏历史侧边栏",
                shortcut: settings.sidebarShortcut,
                error: settings.sidebarShortcutError,
                onApply: { settings.applySidebarShortcut($0) },
                onReset: { settings.resetSidebarShortcut() }
            )

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("界面语言")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("默认跟随系统语言，修改后立即生效。")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                FocusSelectMenu(
                    options: AppLanguage.allCases,
                    selection: settings.appLanguage,
                    title: { $0.title },
                    width: 150,
                    onSelect: { settings.appLanguage = $0 }
                )
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("开机自启动")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("登录 macOS 后自动在后台运行，随时可用快捷键唤起。")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(FocusTheme.accent)
            }

            if let error = settings.launchAtLoginError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(FocusTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("在菜单栏显示图标")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("关闭后仍可用全局快捷键唤起；按 ⌘, 打开设置。")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $settings.showMenuBarIcon)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(FocusTheme.accent)
            }
        }
    }

    private var updateSection: some View {
        SettingsSection(
            title: "检查与更新",
            subtitle: nil,
            icon: "arrow.triangle.2.circlepath"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.format("当前版本 %@", appVersion))
                            .font(.system(size: 11.5, weight: .medium))
                        Text("从 GitHub Releases 检查并安装最新版本。")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        Task {
                            await updateChecker.check()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if updateChecker.isBusy {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                            }
                            Text(L10n.string(updateActionTitle))
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(FocusTheme.accent, in: Capsule())
                        .opacity(updateChecker.isBusy ? 0.72 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(updateChecker.isBusy)
                }

                updateStatus

                Link(destination: URL(string: "https://github.com/ykn0309/deepseek-focus")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("GitHub 仓库")
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(FocusTheme.accent.opacity(0.9))
                }
            }
        }
    }

    private var updateActionTitle: String {
        switch updateChecker.state {
        case .checking: return "正在检查…"
        case .downloading: return "正在下载…"
        case .installing: return "正在安装…"
        default: return "检查更新"
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateChecker.state {
        case .idle, .checking:
            EmptyView()
        case .upToDate:
            Label(L10n.string("已是最新版本"), systemImage: "checkmark.circle")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.green.opacity(0.85))
        case .available(let version, _):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Label(L10n.format("发现新版本 %@", version), systemImage: "arrow.down.circle")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(FocusTheme.accent)
                    Spacer()
                    Button(L10n.string("下载并安装")) {
                        Task {
                            await updateChecker.downloadAndInstall()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(FocusTheme.accent)
                }
                Text("下载完成后会自动重启应用。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        case .downloading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("正在下载更新…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("正在安装，应用即将重启…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(FocusTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                if let releasePageURL = updateChecker.releasePageURL {
                    Button(L10n.string("打开 Release 页面")) {
                        openURL(releasePageURL)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(FocusTheme.accent)
                }
            }
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text("你的对话只在需要时发送给 DeepSeek，不会经过任何第三方中转。应用不包含账号系统、遥测或分析 SDK。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Helpers

    private func syncModels() {
        Task {
            settings.flushAPIKey()
            await modelCatalog.refresh(apiKey: settings.apiKey)
        }
    }

    private var connectionColor: Color {
        switch modelCatalog.connectionState {
        case .connected: return .green.opacity(0.8)
        case .checking: return FocusTheme.accent
        case .failed: return FocusTheme.warning
        case .notConfigured, .unverified: return Color.secondary.opacity(0.55)
        }
    }

    @ViewBuilder
    private var connectionFeedback: some View {
        if modelCatalog.isLoading {
            Label(L10n.string("正在验证 API Key…"), systemImage: "clock")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        } else if let error = modelCatalog.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.system(size: 10.5))
                .foregroundStyle(FocusTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else if modelCatalog.connectionState == .connected {
            Label(
                modelCatalog.connectionMessage ?? L10n.string("已连接 DeepSeek，可随时开始对话。"),
                systemImage: "checkmark.circle"
            )
            .font(.system(size: 10.5))
            .foregroundStyle(Color.green.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
        } else if !settings.hasAPIKey {
            Label(L10n.string("尚未配置 API Key。"), systemImage: "key.slash")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        } else if modelCatalog.connectionState == .unverified {
            Label(L10n.string("修改 API Key 后请点击“验证并同步”。"), systemImage: "questionmark.circle")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    private var modelFacts: String {
        let context = formattedTokens(selectedModel.contextWindow)
        let output = formattedTokens(selectedModel.maxOutputTokens)
        if context.isEmpty && output.isEmpty {
            return L10n.string("由 DeepSeek 提供")
        }
        return L10n.format("%@ 上下文 · %@ 最大输出", context, output)
    }

    private func formattedTokens(_ value: Int?) -> String {
        guard let value, value > 0 else { return "—" }
        if value >= 1_000_000 {
            return String(format: "%.1fM tokens", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return "\(value / 1_000)K tokens"
        }
        return "\(value) tokens"
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, build != version { return "v\(version) (\(build))" }
        return "v\(version)"
    }
}

// MARK: - Section container

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FocusTheme.accent.opacity(0.85))
                    .frame(width: 18, height: 18)
                    .background(FocusTheme.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 12.5, weight: .semibold))
                    if let subtitle {
                        Text(LocalizedStringKey(subtitle))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            content()
                .padding(.leading, 27)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.56))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.8)
                }
        }
    }
}
