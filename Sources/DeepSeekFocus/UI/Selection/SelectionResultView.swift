import SwiftUI
import DeepSeekFocusCore

struct SelectionResultView: View {
    @ObservedObject var model: SelectionResultModel
    var onClose: () -> Void
    var onContinue: (String, String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                bodyContent
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.action == .ask, !model.isStreaming, model.errorMessage == nil {
                Divider()
                footer
            } else if model.action != .ask, !model.isStreaming, model.errorMessage == nil {
                Divider()
                ephemeralHint
            }
        }
        .frame(width: 420, height: 460)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(FocusTheme.accent.opacity(0.10))
                    .frame(width: 26, height: 26)
                Image(systemName: headerIcon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(FocusTheme.accent)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(model.selectedText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.045), in: Circle())
            }
            .buttonStyle(.plain)
            .help("关闭")
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let errorMessage = model.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(FocusTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Text("请检查 API Key 或稍后重试。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        } else if model.action == .dictionary {
            if let entry = model.dictionary {
                DictionaryEntryView(entry: entry)
            } else if model.isStreaming {
                loadingView(text: "正在查询…")
            } else if !model.content.isEmpty {
                AssistantMarkdownView(text: model.content, isStreaming: false)
            } else {
                loadingView(text: "没有返回结果")
            }
        } else if model.content.isEmpty {
            loadingView(text: model.isStreaming ? "正在生成…" : "没有返回结果")
        } else {
            AssistantMarkdownView(text: model.content, isStreaming: model.isStreaming)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("快捷回答不会保存到历史")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                onContinue(model.selectedText, model.content)
            } label: {
                HStack(spacing: 4) {
                    Text("在对话中继续")
                        .font(.system(size: 10.5, weight: .medium))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8.5, weight: .semibold))
                }
                .foregroundStyle(FocusTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(FocusTheme.accent.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
    }

    private var ephemeralHint: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 9))
            Text(model.action == .dictionary ? "查词结果不会保存到历史" : "翻译结果不会保存到历史")
                .font(.system(size: 10))
            Spacer()
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
    }

    private func loadingView(text: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
    }

    private var headerTitle: LocalizedStringKey {
        switch model.action {
        case .ask: return "问 DeepSeek"
        case .translate: return "翻译"
        case .dictionary: return "查词"
        }
    }

    private var headerIcon: String {
        switch model.action {
        case .ask: return "sparkles"
        case .translate: return "character.bubble"
        case .dictionary: return "book.closed"
        }
    }
}

// MARK: - Dictionary layout

private struct DictionaryEntryView: View {
    let entry: DictionaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.term)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .textSelection(.enabled)

                HStack(spacing: 7) {
                    if let pronunciation = entry.pronunciation, !pronunciation.isEmpty {
                        Text(pronunciation)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                    }
                    if let partOfSpeech = entry.partOfSpeech, !partOfSpeech.isEmpty {
                        Text(partOfSpeech)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(FocusTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(FocusTheme.accent.opacity(0.08), in: Capsule())
                    }
                }
            }

            if !entry.definitions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("释义")
                    ForEach(Array(entry.definitions.enumerated()), id: \.offset) { index, definition in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 14, alignment: .trailing)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(definition.meaning)
                                    .font(.system(size: 12.5))
                                    .fixedSize(horizontal: false, vertical: true)
                                if let example = definition.example, !example.isEmpty {
                                    Text(example)
                                        .font(.system(size: 11))
                                        .italic()
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }

            if !entry.examples.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("例句")
                    ForEach(Array(entry.examples.enumerated()), id: \.offset) { _, example in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(example.text)
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                            if let translation = example.translation, !translation.isEmpty {
                                Text(translation)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            if !entry.synonyms.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    sectionLabel("同义词")
                    HStack(spacing: 5) {
                        ForEach(Array(entry.synonyms.prefix(6).enumerated()), id: \.offset) { _, synonym in
                            Text(synonym)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.045), in: Capsule())
                        }
                    }
                }
            }

            if let notes = entry.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("备注")
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.4)
    }
}
