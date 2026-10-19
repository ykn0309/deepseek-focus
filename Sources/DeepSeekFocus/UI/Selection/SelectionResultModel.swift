import Foundation
import SwiftUI
import DeepSeekFocusCore

@MainActor
final class SelectionResultModel: ObservableObject {
    @Published private(set) var action: SelectionAction = .ask
    @Published private(set) var selectedText = ""
    @Published private(set) var content = ""
    @Published private(set) var dictionary: DictionaryEntry?
    @Published private(set) var isStreaming = false
    @Published private(set) var errorMessage: String?

    private let settings: AppSettings
    private var engine = ConversationEngine()
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start(text: String, action: SelectionAction) {
        cancel()
        requestID = UUID()
        let id = requestID
        selectedText = text
        self.action = action
        content = ""
        dictionary = nil
        errorMessage = nil
        isStreaming = true

        guard settings.hasAPIKey else {
            errorMessage = DeepSeekError.missingAPIKey.errorDescription
            isStreaming = false
            return
        }

        let prompt: String
        switch action {
        case .ask:
            prompt = SelectionPrompt.make(text: text, action: .ask, targetLanguage: settings.translationTarget)
        case .translate:
            prompt = SelectionPrompt.make(text: text, action: .translate, targetLanguage: settings.translationTarget)
        case .dictionary:
            prompt = SelectionDictionaryPrompt.make(text: text, languageCode: settings.resolvedLanguageCode)
        }

        let selectionConfiguration = settings.selectionConfiguration(for: action)
        let configuration = ChatAgentConfiguration(
            apiKey: settings.apiKey,
            baseURL: settings.baseURL,
            model: selectionConfiguration.modelID.isEmpty ? settings.selectedModelID : selectionConfiguration.modelID,
            reasoningEffort: selectionConfiguration.reasoningEffort.isEmpty ? settings.reasoningEffort : selectionConfiguration.reasoningEffort,
            webSearchEnabled: selectionConfiguration.webSearchEnabled,
            languageCode: settings.resolvedLanguageCode,
            now: Date(),
            timeZone: .current
        )
        engine = ConversationEngine()

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await event in self.engine.send(userText: prompt, configuration: configuration) {
                    guard self.requestID == id, !Task.isCancelled else { return }
                    if case .contentDelta(let delta) = event {
                        self.content += delta
                    }
                }
                guard self.requestID == id, !Task.isCancelled else { return }
                self.isStreaming = false
                if action == .dictionary {
                    self.dictionary = DictionaryEntry.parse(self.content)
                }
            } catch is CancellationError {
                // A new selection or a dismissed result cancels the request.
            } catch {
                guard self.requestID == id else { return }
                self.errorMessage = error.localizedDescription
                self.isStreaming = false
            }
        }
    }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
        isStreaming = false
    }
}
