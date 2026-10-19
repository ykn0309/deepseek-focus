import SwiftUI

struct HistoryBrowser: View {
    @ObservedObject var history: ConversationHistoryStore
    var currentSessionID: UUID?
    var generatingSessionIDs: Set<UUID> = []
    var onNewConversation: () -> Void
    var onSelect: (ConversationSession) -> Void
    var onDelete: (ConversationSession) -> Void
    var onRename: (ConversationSession, String) -> Void

    @State private var query = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            newConversationButton
            searchField
                .padding(.top, 9)
            content
                .padding(.top, 5)
        }
        .padding(.horizontal, 13)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var filteredSessions: [ConversationSession] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return history.sessions }
        return history.sessions.filter { session in
            session.title.localizedCaseInsensitiveContains(needle)
                || session.turns.contains { $0.question.localizedCaseInsensitiveContains(needle) }
        }
    }


    private var newConversationButton: some View {
        Button {
            query = ""
            onNewConversation()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("开启新对话")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(.primary.opacity(0.80))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.62))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.13), lineWidth: 0.8)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .withoutFocusRing()
        .help("开始新对话（⌘N）")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("搜索历史会话", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(.primary.opacity(0.82))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .withoutFocusRing()
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.primary.opacity(0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.12), lineWidth: 0.8)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if filteredSessions.isEmpty {
            VStack(spacing: 5) {
                Text(LocalizedStringKey(query.isEmpty ? "还没有历史会话" : "没有找到匹配的会话"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(LocalizedStringKey(query.isEmpty ? "发送消息后会自动保存在这里。" : "试试其他关键词。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        Text(LocalizedStringKey(section.title))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 7)
                            .padding(.top, section.id == sections.first?.id ? 9 : 14)
                            .padding(.bottom, 5)

                        ForEach(section.sessions) { session in
                            HistorySessionRow(
                                session: session,
                                isCurrent: session.id == currentSessionID,
                                isGenerating: generatingSessionIDs.contains(session.id),
                                action: { onSelect(session) },
                                onDelete: { onDelete(session) },
                                onRename: { title in onRename(session, title) }
                            )
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: .infinity)
        }
    }


    private var sections: [HistorySection] {
        let now = Date()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        var today: [ConversationSession] = []
        var week: [ConversationSession] = []
        var month: [ConversationSession] = []
        var older: [ConversationSession] = []

        for session in filteredSessions {
            if Calendar.current.isDateInToday(session.updatedAt) {
                today.append(session)
            } else if session.updatedAt >= weekAgo {
                week.append(session)
            } else if session.updatedAt >= monthAgo {
                month.append(session)
            } else {
                older.append(session)
            }
        }

        return [
            HistorySection(id: "today", title: "今天", sessions: today),
            HistorySection(id: "week", title: "7 天内", sessions: week),
            HistorySection(id: "month", title: "30 天内", sessions: month),
            HistorySection(id: "older", title: "更早", sessions: older)
        ].filter { !$0.sessions.isEmpty }
    }
}

private struct HistorySection: Identifiable {
    let id: String
    let title: String
    let sessions: [ConversationSession]
}

private struct HistorySessionRow: View {
    let session: ConversationSession
    let isCurrent: Bool
    let isGenerating: Bool
    let action: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void

    @State private var hovering = false
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @State private var forceMenuVisible = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        Group {
            if isRenaming {
                renameRow
            } else {
                normalRow
            }
        }
        .onHover { hovering = $0 }
    }

    private var normalRow: some View {
        ZStack(alignment: .trailing) {
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 12.5, weight: isCurrent ? .medium : .regular))
                        .foregroundStyle(isCurrent ? FocusTheme.accent : .primary.opacity(0.82))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .scaleEffect(1.1)
                            .tint(FocusTheme.accent)
                            .frame(width: 20, height: 20)
                            .help("正在生成")
                            .accessibilityLabel("正在生成")
                    }

                    // Reserve the trailing space so the title doesn't jump
                    // when the ellipsis appears.
                    Color.clear
                        .frame(width: 20, height: 20)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(rowBackground)
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .withoutFocusRing()

            if hovering || isCurrent || forceMenuVisible {
                Menu {
                    Button {
                        beginRenaming()
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.trailing, 4)
                .simultaneousGesture(TapGesture().onEnded {
                    forceMenuVisible = true
                })
                .help("更多操作")
                .accessibilityLabel("更多操作")
            }
        }
    }

    private var renameRow: some View {
        HStack(spacing: 4) {
            TextField("", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($renameFocused)
                .onSubmit { commitRename() }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.65))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(FocusTheme.accent.opacity(0.45), lineWidth: 0.9)
                        }
                }

            Button {
                commitRename()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(FocusTheme.accent)
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("保存")

            Button {
                isRenaming = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("取消")
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(FocusTheme.accent.opacity(0.07))
        }
    }

    private func beginRenaming() {
        forceMenuVisible = false
        draftTitle = session.title
        isRenaming = true
        DispatchQueue.main.async {
            renameFocused = true
        }
    }

    private func commitRename() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isRenaming = false
            return
        }
        onRename(trimmed)
        isRenaming = false
    }

    private var rowBackground: Color {
        if isCurrent {
            return FocusTheme.accent.opacity(hovering ? 0.16 : 0.11)
        }
        return Color.primary.opacity(hovering ? 0.055 : 0)
    }
}
