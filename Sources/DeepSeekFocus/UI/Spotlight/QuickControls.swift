import SwiftUI
import DeepSeekFocusCore

struct QuickModelControls: View {
    @ObservedObject var modelCatalog: ModelCatalog
    var configuration: SessionAIConfiguration
    var onModelChange: (DeepSeekModel) -> Void
    var onReasoningChange: (String, DeepSeekModel) -> Void
    var onWebSearchChange: (WebSearchMode) -> Void

    private var selectedModel: DeepSeekModel {
        modelCatalog.models.first(where: { $0.id == configuration.modelID })
            ?? DeepSeekModel.fallbackModel(id: configuration.modelID)
            ?? modelCatalog.models.first
            ?? DeepSeekModel.fallbackModels[0]
    }

    private var modelTitle: String {
        selectedModel.displayName
    }

    private var reasoningLevels: [String] {
        ["none"] + selectedModel.supportedReasoningLevels
    }

    var body: some View {
        HStack(spacing: 13) {
            Menu {
                ForEach(modelCatalog.models) { model in
                    Toggle(isOn: Binding(
                        get: { configuration.modelID == model.id },
                        set: { isSelected in
                            if isSelected { onModelChange(model) }
                        }
                    )) {
                        Text(model.displayName)
                    }
                }
            } label: {
                controlLabel(title: "模型", value: modelTitle, help: "切换模型")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                ForEach(reasoningLevels, id: \.self) { level in
                    Toggle(isOn: Binding(
                        get: { configuration.reasoningEffort == level },
                        set: { isSelected in
                            if isSelected {
                                onReasoningChange(level, selectedModel)
                            }
                        }
                    )) {
                        Text(ReasoningEffortCopy.title(for: level))
                    }
                }
            } label: {
                controlLabel(
                    title: "推理等级",
                    value: ReasoningEffortCopy.title(for: configuration.reasoningEffort),
                    help: "切换推理等级"
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                Toggle(isOn: Binding(
                    get: { configuration.webSearchMode == .automatic },
                    set: { isSelected in
                        if isSelected { onWebSearchChange(.automatic) }
                    }
                )) {
                    Text("自动搜索")
                }
                Toggle(isOn: Binding(
                    get: { configuration.webSearchMode == .off },
                    set: { isSelected in
                        if isSelected { onWebSearchChange(.off) }
                    }
                )) {
                    Text("关闭搜索")
                }
            } label: {
                controlLabel(
                    title: "联网",
                    value: configuration.webSearchMode == .automatic ? "自动" : "关闭",
                    help: "切换联网搜索"
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func controlLabel(title: String, value: String, help: String) -> some View {
        (Text(LocalizedStringKey(title)).foregroundColor(Color.primary.opacity(0.50))
            + Text(" ").foregroundColor(Color.primary.opacity(0.50))
            + Text(LocalizedStringKey(value)).foregroundColor(Color.primary.opacity(0.82))
            + Text("  ›").foregroundColor(Color.primary.opacity(0.40)))
            .font(.system(size: 11.5))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .help(LocalizedStringKey(help))
            .accessibilityLabel("\(L10n.string(title)): \(L10n.string(value))")
    }
}
