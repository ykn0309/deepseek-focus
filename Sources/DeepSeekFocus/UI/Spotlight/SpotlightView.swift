import SwiftUI
import DeepSeekFocusCore

struct SpotlightRootView: View {
    @ObservedObject var model: SpotlightViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var modelCatalog: ModelCatalog

    var body: some View {
        ZStack {
            if model.isShowingSettings {
                SettingsView(
                    settings: settings,
                    modelCatalog: modelCatalog,
                    onBack: { model.closeSettingsPage() }
                )
                .clipShape(RoundedRectangle(cornerRadius: FocusTheme.radiusLarge, style: .continuous))
                .background(FocusPanelBackground(cornerRadius: FocusTheme.radiusLarge, prominentShadow: true))
                .transition(.opacity)
            } else if model.isConversation {
                ConversationSurface(
                    model: model,
                    modelCatalog: modelCatalog
                )
                .id(settings.resolvedLanguageCode)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                        removal: .opacity
                    )
                )
            } else {
                SearchSurface(model: model, modelCatalog: modelCatalog)
                    .id(settings.resolvedLanguageCode)
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
            }
        }
        .padding(SpotlightMetrics.shadowInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.locale, settings.appLanguage.locale)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.isConversation)
        .animation(.easeInOut(duration: 0.18), value: model.isShowingSettings)
        .onExitCommand {
            model.requestHide()
        }
    }
}

// MARK: - Search palette

private struct SearchSurface: View {
    @ObservedObject var model: SpotlightViewModel
    @ObservedObject var modelCatalog: ModelCatalog
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 11) {
            FocusAvatar(size: 30)

            TextField(
                "",
                text: $model.input,
                prompt: Text("给DeepSeek发送消息")
                    .foregroundColor(.primary.opacity(0.34))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 21, weight: .regular, design: .rounded))
            .foregroundStyle(.primary.opacity(0.92))
            .focused($fieldFocused)
            .onSubmit { model.submit() }
            .layoutPriority(1)

            QuickModelControls(
                modelCatalog: modelCatalog,
                configuration: model.sessionConfiguration,
                onModelChange: { model.selectSessionModel($0) },
                onReasoningChange: { level, selected in
                    model.selectSessionReasoningLevel(level, model: selected)
                },
                onWebSearchChange: { model.selectSessionWebSearchMode($0) }
            )

            Button {
                model.openHistory()
            } label: {
                HStack(spacing: 3) {
                    Text("历史")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("›")
                        .font(.system(size: 11.5))
                        .opacity(0.50)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("打开历史会话")
            .accessibilityLabel("历史会话")

            Button {
                model.submit()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(model.input.isEmpty ? Color.primary.opacity(0.34) : .white)
                    .frame(width: 30, height: 30)
                    .background {
                        Circle()
                            .fill(model.input.isEmpty
                                  ? AnyShapeStyle(Color.primary.opacity(0.055))
                                  : AnyShapeStyle(FocusTheme.accentGradient))
                    }
            }
            .buttonStyle(.plain)
            .disabled(model.input.isEmpty)
            .help("发送（Return）")
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: FocusTheme.radiusSearch, style: .continuous))
        .background(FocusPanelBackground(cornerRadius: FocusTheme.radiusSearch))
        .contentShape(RoundedRectangle(cornerRadius: FocusTheme.radiusSearch, style: .continuous))
        .onAppear { scheduleFocus() }
        .onChange(of: model.focusToken) { _ in scheduleFocus() }
        .onChange(of: model.sessionConfiguration) { _ in scheduleFocus() }
        .animation(.easeOut(duration: 0.14), value: model.input.isEmpty)
    }

    private func scheduleFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.055) {
            fieldFocused = true
        }
    }
}

// MARK: - Conversation

private struct ConversationSurface: View {
    @ObservedObject var model: SpotlightViewModel
    @ObservedObject var modelCatalog: ModelCatalog
    @Environment(\.colorScheme) private var colorScheme
    @State private var composerHeight: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            if model.isHistoryPresented {
                sidebarColumn
                    .transition(.move(edge: .leading).combined(with: .opacity))

                sidebarDivider
                    .transition(.opacity)
            }

            conversationColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: FocusTheme.radiusLarge, style: .continuous))
        .background(FocusPanelBackground(cornerRadius: FocusTheme.radiusLarge, prominentShadow: true))
        .animation(.easeInOut(duration: 0.2), value: model.isHistoryPresented)
        .onChange(of: model.sessionConfiguration) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { model.requestFocus() }
        }
    }

    private var sidebarFill: Color {
        colorScheme == .dark ? Color.black.opacity(0.10) : Color.black.opacity(0.035)
    }

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            sidebarHeader

            HistoryBrowser(
                history: model.historyStore,
                currentSessionID: model.currentSessionID,
                onNewConversation: {
                    model.newConversation()
                },
                onSelect: { session in
                    DispatchQueue.main.async {
                        model.loadHistorySession(session)
                    }
                },
                onDelete: { session in
                    model.deleteHistorySession(session)
                },
                onRename: { session, title in
                    model.renameHistorySession(session, title: title)
                }
            )
            .frame(maxHeight: .infinity)
        }
        .frame(width: 254)
        .frame(maxHeight: .infinity)
        .background(sidebarFill)
    }

    private var sidebarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.14))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.16 : 0.055),
                radius: 3,
                x: 1,
                y: 0
            )
    }

    private var conversationColumn: some View {
        VStack(spacing: 0) {
            conversationHeader
            DividerLine()
            conversation
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            sidebarToggle
            panelTitle
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    private var conversationHeader: some View {
        HStack(spacing: 10) {
            if !model.isHistoryPresented {
                sidebarToggle
                panelTitle
            }

            Spacer(minLength: 12)
            HStack(spacing: 4) {
                newChatButton
                settingsButton
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    private var sidebarToggle: some View {
        Button {
            model.toggleHistory()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(model.isHistoryPresented ? FocusTheme.accent : .primary.opacity(0.68))
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(model.isHistoryPresented ? 0.07 : 0))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(model.isHistoryPresented ? "关闭历史会话" : "历史会话")
        .accessibilityLabel("历史会话")
    }

    private var panelTitle: some View {
        Text("DeepSeek 聚焦")
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.82))
    }

    private var newChatButton: some View {
        FocusIconButton(
            systemName: "square.and.pencil",
            help: "开始新对话（⌘N）",
            iconSize: 13.6,
            iconOffset: CGSize(width: 0, height: -0.5)
        ) {
            model.newConversation()
        }
    }

    private var settingsButton: some View {
        FocusIconButton(systemName: "gearshape", help: "设置（⌘,）") {
            model.openSettingsPage()
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(model.turns) { turn in
                        TurnView(turn: turn, model: model)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("conversation-bottom")
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 14)
            }
            .onChange(of: model.scrollTick) { _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                }
            }
            .onChange(of: model.isHistoryPresented) { _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var composer: some View {
        VStack(spacing: 7) {
            HStack(alignment: .bottom, spacing: 9) {
                ComposerTextView(
                    text: $model.input,
                    height: $composerHeight,
                    placeholder: L10n.string("给DeepSeek发送消息"),
                    focusToken: model.focusToken,
                    onSubmit: { model.submit() }
                )
                .frame(height: composerHeight)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    if model.isStreaming {
                        model.stopGenerating()
                    } else {
                        model.submit()
                    }
                } label: {
                    Image(systemName: model.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: model.isStreaming ? 9.5 : 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background {
                            Circle()
                                .fill(model.isStreaming || model.canSend
                                      ? AnyShapeStyle(FocusTheme.accentGradient)
                                      : AnyShapeStyle(Color.primary.opacity(0.16)))
                        }
                }
                .buttonStyle(.plain)
                .disabled(!model.isStreaming && !model.canSend)
                .help(model.isStreaming ? "停止生成" : "发送（Return）")
            }
            .padding(.leading, 12)
            .padding(.trailing, 7)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.09 : 0.48))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.105), lineWidth: 0.8)
                    }
            }

            HStack(spacing: 7) {
                QuickModelControls(
                    modelCatalog: modelCatalog,
                    configuration: model.sessionConfiguration,
                    onModelChange: { model.selectSessionModel($0) },
                    onReasoningChange: { level, selected in
                        model.selectSessionReasoningLevel(level, model: selected)
                    },
                    onWebSearchChange: { model.selectSessionWebSearchMode($0) }
                )

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 9)
        .padding(.bottom, 12)
    }


}

// MARK: - Turn

private struct TurnView: View {
    let turn: ConversationTurn
    @ObservedObject var model: SpotlightViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            userMessage
            assistantMessage
        }
    }

    private var userMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            Spacer(minLength: 90)
            Text(turn.question)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.97))
                .lineSpacing(3)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(
                    FocusTheme.accentGradient,
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .shadow(color: FocusTheme.accentDeep.opacity(0.18), radius: 8, y: 3)
        }
    }

    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: 11) {
            FocusAvatar(size: 25)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 11) {
                if turn.hasReasoning {
                    ReasoningView(turn: turn)
                }

                if !turn.activities.isEmpty {
                    SearchActivitiesView(turn: turn)
                }

                if !turn.answer.isEmpty {
                    AssistantMarkdownView(text: turn.answer, isStreaming: turn.isStreaming)
                } else if turn.isStreaming {
                    HStack(spacing: 8) {
                        ThinkingDots()
                        Text(activeStatusText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }

                if turn.isStreaming, !turn.answer.isEmpty {
                    Text(turn.activities.contains(where: { $0.state == .searching })
                         ? L10n.string("正在整理搜索结果…")
                         : "")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }

                if let error = turn.errorMessage {
                    ErrorCard(message: error, needsSetup: turn.needsSetup, model: model)
                }

                if !turn.sources.isEmpty {
                    SourcesView(sources: turn.sources)
                }

                if turn.wasStopped {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.circle")
                            .font(.system(size: 9))
                        Text("已停止生成")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var activeStatusText: String {
        if turn.activities.contains(where: { $0.state == .searching }) {
            return L10n.string("正在检索网页…")
        }
        return turn.hasReasoning ? L10n.string("思考中…") : L10n.string("正在思考…")
    }
}

// MARK: - Reasoning

private struct ReasoningView: View {
    let turn: ConversationTurn
    @State private var expanded = false

    private var isThinking: Bool {
        turn.isStreaming && turn.answer.isEmpty
    }

    private var title: String {
        if isThinking { return L10n.string("正在思考") }
        if let duration = turn.reasoningDuration, duration > 0.3 {
            return L10n.format("思考了 %.1f 秒", duration)
        }
        return L10n.string("思考过程")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 9.5, weight: .medium))
                    Text(title)
                        .font(.system(size: 10.5, weight: .medium))
                    if isThinking {
                        ThinkingDots()
                            .scaleEffect(0.8)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                        .opacity(0.6)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.035), in: Capsule())
            }
            .buttonStyle(.plain)

            if expanded {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(turn.reasoning)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary.opacity(0.9))
                        .lineSpacing(4.5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                }
                .frame(maxHeight: 170)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.028))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.7)
                        }
                }
                .padding(.top, 7)
                // Expand downward from below the header. A .move(edge: .top)
                // transition starts the content above the header and makes it
                // visibly overlap the reasoning pill.
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Search activity and sources

private struct SearchActivitiesView: View {
    let turn: ConversationTurn

    private var visibleActivities: [SearchActivity] {
        turn.activities.filter { activity in
            switch activity.state {
            case .searching, .failed:
                return true
            case .completed(let count):
                return count == 0
            }
        }
    }

    var body: some View {
        if !visibleActivities.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleActivities) { activity in
                    HStack(spacing: 7) {
                        activityIcon(activity.state)
                            .frame(width: 12)
                        Text(activityText(activity))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.03), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func activityIcon(_ state: SearchActivity.State) -> some View {
        switch state {
        case .searching:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.65)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 9.5))
                .foregroundStyle(FocusTheme.warning)
        case .completed:
            Image(systemName: "globe")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
    }

    private func activityText(_ activity: SearchActivity) -> String {
        switch activity.state {
        case .searching:
            return L10n.format("正在搜索「%@」…", activity.query)
        case .completed:
            return L10n.format("搜索「%@」没有找到结果", activity.query)
        case .failed(let message):
            return L10n.format("搜索「%@」失败：%@", activity.query, message)
        }
    }
}

private struct SourcesView: View {
    let sources: [SearchSource]
    @State private var showAll = false

    private var visibleSources: [SearchSource] {
        showAll ? sources : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(FocusTheme.accent.opacity(0.8))
                Text("搜索来源")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(sources.count)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.05), in: Capsule())
            }

            if !visibleSources.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(visibleSources.enumerated()), id: \.element.id) { index, source in
                        SourceRow(index: index + 1, source: source)
                    }
                }
            }

            if !sources.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { showAll.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showAll
                             ? L10n.string("收起来源")
                             : L10n.format("查看全部 %ld 个来源", sources.count))
                        Image(systemName: showAll ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FocusTheme.accent.opacity(0.85))
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
            }
        }
        .padding(.top, 2)
    }
}

private struct SourceRow: View {
    let index: Int
    let source: SearchSource
    @State private var hovering = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = source.linkURL { openURL(url) }
        } label: {
            HStack(spacing: 9) {
                Text("\(index)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(FocusTheme.accent.opacity(0.9))
                    .frame(width: 16, height: 16)
                    .background(FocusTheme.accent.opacity(0.08), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.96))
                        .lineLimit(1)
                    Text(source.displaySiteName)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary.opacity(0.86))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary.opacity(hovering ? 0.9 : 0.45))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.085 : 0.055))
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(source.url)
    }
}

// MARK: - Error

private struct ErrorCard: View {
    let message: String
    let needsSetup: Bool
    @ObservedObject var model: SpotlightViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(FocusTheme.warning)
                    .padding(.top, 1)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary.opacity(0.75))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if needsSetup {
                Button {
                    model.openSettingsPage()
                } label: {
                    HStack(spacing: 4) {
                        Text("打开设置")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(FocusTheme.accentGradient, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(FocusTheme.warning.opacity(0.075))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(FocusTheme.warning.opacity(0.18), lineWidth: 0.7)
                }
        }
    }
}
