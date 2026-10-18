import Combine
import Foundation
import DeepSeekFocusCore

struct SearchActivity: Identifiable, Equatable, Codable {
    enum State: Equatable, Codable {
        case searching
        case completed(count: Int)
        case failed(message: String)
    }

    var id: UUID = UUID()
    var query: String
    var state: State
}

struct SessionAIConfiguration: Equatable {
    var modelID: String
    var reasoningEffort: String
    var webSearchMode: WebSearchMode
}

struct ConversationTurn: Identifiable, Codable {
    var id: UUID = UUID()
    let question: String
    var answer = ""
    var reasoning = ""
    var sources: [SearchSource] = []
    var activities: [SearchActivity] = []
    var isStreaming = true
    var errorMessage: String?
    var needsSetup = false
    var wasStopped = false
    var usedSearch = false
    var reasoningStartedAt: Date?
    var reasoningDuration: TimeInterval?

    var hasReasoning: Bool {
        !reasoning.isEmpty || reasoningStartedAt != nil
    }
}

@MainActor
private final class GenerationJob {
    let id: UUID
    let createdAt: Date
    var title: String?
    var titleGenerated: Bool
    let languageCode: String
    var configuration: SessionAIConfiguration
    let engine: ConversationEngine
    var turns: [ConversationTurn]
    var isStreaming = true
    var task: Task<Void, Never>?

    init(
        id: UUID,
        createdAt: Date,
        title: String?,
        titleGenerated: Bool,
        languageCode: String,
        configuration: SessionAIConfiguration,
        engine: ConversationEngine,
        turns: [ConversationTurn]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.titleGenerated = titleGenerated
        self.languageCode = languageCode
        self.configuration = configuration
        self.engine = engine
        self.turns = turns
    }
}

@MainActor
final class SpotlightViewModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var isConversation = false
    @Published private(set) var isStreaming = false
    @Published private(set) var turns: [ConversationTurn] = []
    @Published private(set) var focusToken = 0
    @Published private(set) var scrollTick = 0
    @Published var isHistoryPresented = false
    @Published var isShowingSettings = false
    @Published var sessionConfiguration: SessionAIConfiguration

    let settings: AppSettings
    let modelCatalog: ModelCatalog
    let historyStore: ConversationHistoryStore

    var onRequestExpand: (() -> Void)?
    var onRequestCollapse: (() -> Void)?
    var onHide: (() -> Void)?

    private var engine = ConversationEngine()
    private var streamTask: Task<Void, Never>?
    private var activeJob: GenerationJob?
    private var backgroundJobs: [UUID: GenerationJob] = [:]
    private var lastScrollTime = Date.distantPast
    @Published private(set) var currentSessionID: UUID?
    private var currentSessionCreatedAt: Date?
    private var currentSessionTitle: String?
    private var currentSessionTitleGenerated = false
    private var currentSessionLanguageCode: String
    private var settingsReturnToHistory = false

    init(settings: AppSettings, modelCatalog: ModelCatalog, historyStore: ConversationHistoryStore) {
        self.settings = settings
        self.modelCatalog = modelCatalog
        self.historyStore = historyStore
        let model = modelCatalog.selectedModel
        let levels = ["none"] + model.supportedReasoningLevels
        let effort = levels.contains(settings.reasoningEffort)
            ? settings.reasoningEffort
            : model.defaultReasoningLevel
        self.sessionConfiguration = SessionAIConfiguration(
            modelID: model.id,
            reasoningEffort: effort,
            webSearchMode: settings.webSearchMode
        )
        self.currentSessionLanguageCode = settings.resolvedLanguageCode
    }

    var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    // MARK: - Actions

    func requestFocus() {
        focusToken &+= 1
    }

    private func ensureSessionIdentity() {
        guard currentSessionID == nil else { return }
        currentSessionID = UUID()
        currentSessionCreatedAt = Date()
        currentSessionTitle = nil
        currentSessionTitleGenerated = false
    }

    func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        if !isConversation {
            isConversation = true
            onRequestExpand?()
        }

        let hasKey = settings.hasAPIKey
        var turn = ConversationTurn(question: text)
        if !hasKey {
            turn.isStreaming = false
            turn.errorMessage = DeepSeekError.missingAPIKey.errorDescription
            turn.needsSetup = true
        }
        ensureSessionIdentity()
        turns.append(turn)
        input = ""
        focusToken &+= 1
        requestScroll(force: true)

        guard hasKey, let sessionID = currentSessionID else {
            isStreaming = false
            return
        }

        isStreaming = true
        let configuration = ChatAgentConfiguration(
            apiKey: settings.apiKey,
            baseURL: settings.baseURL,
            model: sessionConfiguration.modelID,
            reasoningEffort: sessionConfiguration.reasoningEffort,
            webSearchEnabled: sessionConfiguration.webSearchMode == .automatic,
            languageCode: currentSessionLanguageCode,
            now: Date(),
            timeZone: .current
        )

        let job = GenerationJob(
            id: sessionID,
            createdAt: currentSessionCreatedAt ?? Date(),
            title: currentSessionTitle,
            titleGenerated: currentSessionTitleGenerated,
            languageCode: currentSessionLanguageCode,
            configuration: sessionConfiguration,
            engine: engine,
            turns: turns
        )
        backgroundJobs[job.id] = job
        activeJob = job

        let task = Task { [weak self] in
            guard let self else { return }
            let stream = job.engine.send(userText: text, configuration: configuration)
            do {
                for try await event in stream {
                    try Task.checkCancellation()
                    self.consume(event, for: job)
                }
                self.finish(job, cancelled: false, error: nil)
            } catch {
                if Task.isCancelled {
                    self.finish(job, cancelled: true, error: nil)
                } else if let deepSeekError = error as? DeepSeekError, deepSeekError.isCancellation {
                    self.finish(job, cancelled: true, error: nil)
                } else {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.finish(job, cancelled: false, error: message)
                }
            }
        }
        job.task = task
        streamTask = task
    }

    func stopGenerating() {
        streamTask?.cancel()
    }

    /// Called whenever the palette is summoned from a shortcut/menu. Every summon starts with
    /// a clean search field; the previous conversation stays available in history.
    func beginFreshInvocation() {
        persistCurrentSessionIfNeeded()
        activeJob = nil
        streamTask = nil
        engine = ConversationEngine()
        turns = []
        input = ""
        isStreaming = false
        isConversation = false
        isHistoryPresented = false
        isShowingSettings = false
        settingsReturnToHistory = false
        resetSessionConfigurationToDefaults()
        currentSessionID = nil
        currentSessionCreatedAt = nil
        currentSessionTitle = nil
        currentSessionTitleGenerated = false
        currentSessionLanguageCode = settings.resolvedLanguageCode
        focusToken &+= 1
    }

    func newConversation() {
        persistCurrentSessionIfNeeded()
        activeJob = nil
        streamTask = nil
        engine = ConversationEngine()
        turns = []
        input = ""
        isStreaming = false
        // Starting a new chat from the expanded page stays expanded. The new
        // session gets a fresh composer instead of collapsing to the initial bar.
        isConversation = true
        isShowingSettings = false
        settingsReturnToHistory = false
        resetSessionConfigurationToDefaults()
        currentSessionID = nil
        currentSessionCreatedAt = nil
        currentSessionTitle = nil
        currentSessionTitleGenerated = false
        currentSessionLanguageCode = settings.resolvedLanguageCode
        focusToken &+= 1
        onRequestExpand?()
    }

    func openHistory() {
        if !isConversation {
            isConversation = true
            onRequestExpand?()
        }
        isHistoryPresented = true
    }

    func closeHistory() {
        isHistoryPresented = false
    }

    func toggleHistory() {
        if isHistoryPresented {
            closeHistory()
        } else {
            openHistory()
        }
    }

    func loadHistorySession(_ session: ConversationSession) {
        if currentSessionID != session.id {
            persistCurrentSessionIfNeeded()
        }
        activeJob = nil
        streamTask = nil

        if let job = backgroundJobs[session.id] {
            activeJob = job
            engine = job.engine
            turns = job.turns
            isStreaming = job.isStreaming
            streamTask = job.task
            input = ""
            isConversation = !job.turns.isEmpty
            currentSessionID = job.id
            currentSessionCreatedAt = job.createdAt
            currentSessionTitle = job.title ?? session.title
            currentSessionTitleGenerated = job.titleGenerated
            currentSessionLanguageCode = job.languageCode
            sessionConfiguration = job.configuration
            focusToken &+= 1
            onRequestExpand?()
            requestScroll(force: true)
            return
        }

        let restoredTurns = session.turns.map { stored -> ConversationTurn in
            var turn = stored
            turn.isStreaming = false
            turn.wasStopped = false
            return turn
        }
        turns = restoredTurns
        engine = ConversationEngine(messages: session.apiMessages)
        isStreaming = false
        input = ""
        isConversation = !restoredTurns.isEmpty
        currentSessionID = session.id
        currentSessionCreatedAt = session.createdAt
        currentSessionTitle = session.title
        currentSessionTitleGenerated = session.autoTitleGenerated ?? false
        currentSessionLanguageCode = session.languageCode ?? settings.resolvedLanguageCode
        applyConfiguration(from: session)
        focusToken &+= 1
        onRequestExpand?()
        requestScroll(force: true)
    }

    func clearHistory() {
        for job in backgroundJobs.values {
            job.task?.cancel()
        }
        backgroundJobs.removeAll()
        activeJob = nil
        streamTask = nil
        isStreaming = false
        historyStore.clear()
        currentSessionID = nil
        currentSessionCreatedAt = nil
    }

    /// Saves the current session without changing its position in history by
    /// default. Only a finished message turn should count as new activity.
    func persistCurrentSessionIfNeeded(touch: Bool = false) {
        if let job = activeJob, job.id == currentSessionID {
            persist(job, touch: touch)
            return
        }

        guard !turns.isEmpty else { return }
        let apiMessages = engine.messages
        guard !apiMessages.isEmpty else { return }

        let now = Date()
        let id = currentSessionID ?? UUID()
        let previousUpdatedAt = currentSessionID.flatMap { id in
            historyStore.sessions.first(where: { $0.id == id })?.updatedAt
        }
        let updatedAt = touch ? now : (previousUpdatedAt ?? now)
        if currentSessionID == nil {
            currentSessionID = id
            currentSessionCreatedAt = now
        }
        let createdAt = currentSessionCreatedAt ?? now
        let firstQuestion = turns.first?.question ?? "未命名会话"
        let fallback = String(firstQuestion.replacingOccurrences(of: "\n", with: " ").prefix(48))
        let storedTitle = currentSessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (storedTitle?.isEmpty == false ? storedTitle! : fallback)
        let storedTurns = turns.map { turn -> ConversationTurn in
            var copy = turn
            copy.isStreaming = false
            return copy
        }
        let session = ConversationSession(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            title: title.isEmpty ? "未命名会话" : title,
            turns: storedTurns,
            apiMessages: apiMessages,
            modelID: sessionConfiguration.modelID,
            reasoningEffort: sessionConfiguration.reasoningEffort,
            webSearchMode: sessionConfiguration.webSearchMode.rawValue,
            autoTitleGenerated: currentSessionTitleGenerated,
            languageCode: currentSessionLanguageCode
        )
        historyStore.upsert(session)
    }

    private func persist(_ job: GenerationJob, touch: Bool) {
        guard !job.turns.isEmpty, !job.engine.messages.isEmpty else { return }

        let now = Date()
        let previousUpdatedAt = historyStore.sessions
            .first(where: { $0.id == job.id })?.updatedAt
        let updatedAt = touch ? now : (previousUpdatedAt ?? now)
        let firstQuestion = job.turns.first?.question ?? "未命名会话"
        let fallback = String(firstQuestion.replacingOccurrences(of: "\n", with: " ").prefix(48))
        let storedTitle = job.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (storedTitle?.isEmpty == false ? storedTitle! : fallback)
        let storedTurns = job.turns.map { turn -> ConversationTurn in
            var copy = turn
            copy.isStreaming = false
            return copy
        }
        let session = ConversationSession(
            id: job.id,
            createdAt: job.createdAt,
            updatedAt: updatedAt,
            title: title.isEmpty ? "未命名会话" : title,
            turns: storedTurns,
            apiMessages: job.engine.messages,
            modelID: job.configuration.modelID,
            reasoningEffort: job.configuration.reasoningEffort,
            webSearchMode: job.configuration.webSearchMode.rawValue,
            autoTitleGenerated: job.titleGenerated,
            languageCode: job.languageCode
        )
        historyStore.upsert(session)

        if currentSessionID == job.id {
            currentSessionCreatedAt = job.createdAt
            currentSessionTitle = job.title
            currentSessionTitleGenerated = job.titleGenerated
            currentSessionLanguageCode = job.languageCode
        }
    }

    func renameHistorySession(_ session: ConversationSession, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        historyStore.updateTitle(id: session.id, title: trimmed, generated: true)
        if currentSessionID == session.id {
            currentSessionTitle = trimmed
            currentSessionTitleGenerated = true
        }
    }

    func deleteHistorySession(_ session: ConversationSession) {
        if let job = backgroundJobs.removeValue(forKey: session.id) {
            job.task?.cancel()
            if activeJob === job {
                activeJob = nil
                streamTask = nil
                isStreaming = false
            }
        }
        let deletingCurrent = currentSessionID == session.id
        if deletingCurrent {
            activeJob = nil
            streamTask = nil
            engine = ConversationEngine()
            turns = []
            input = ""
            isStreaming = false
            currentSessionID = nil
            currentSessionCreatedAt = nil
            currentSessionTitle = nil
            currentSessionTitleGenerated = false
            resetSessionConfigurationToDefaults()
            focusToken &+= 1
        }
        historyStore.delete(id: session.id)
    }

    func requestHide() {
        onHide?()
    }

    // MARK: - In-panel settings

    func openSettingsPage() {
        guard !isShowingSettings else { return }
        settingsReturnToHistory = isHistoryPresented
        isHistoryPresented = false
        isShowingSettings = true
        if !isConversation {
            isConversation = true
            onRequestExpand?()
        }
    }

    func closeSettingsPage() {
        guard isShowingSettings else { return }
        settings.flushAPIKey()
        isShowingSettings = false
        isConversation = true
        if turns.isEmpty {
            resetSessionConfigurationToDefaults()
            currentSessionTitle = nil
            currentSessionTitleGenerated = false
        }
        if settingsReturnToHistory {
            isHistoryPresented = true
        }
        settingsReturnToHistory = false
        focusToken &+= 1
        onRequestExpand?()
    }

    // MARK: - Per-session AI configuration

    func selectSessionModel(_ model: DeepSeekModel) {
        var updated = sessionConfiguration
        updated.modelID = model.id
        let levels = ["none"] + model.supportedReasoningLevels
        if !levels.contains(updated.reasoningEffort) {
            updated.reasoningEffort = model.defaultReasoningLevel
        }
        sessionConfiguration = updated
        persistSessionConfigurationIfNeeded()
    }

    func selectSessionReasoningLevel(_ level: String, model: DeepSeekModel) {
        guard (["none"] + model.supportedReasoningLevels).contains(level) else { return }
        var updated = sessionConfiguration
        updated.reasoningEffort = level
        sessionConfiguration = updated
        persistSessionConfigurationIfNeeded()
    }

    func selectSessionWebSearchMode(_ mode: WebSearchMode) {
        var updated = sessionConfiguration
        updated.webSearchMode = mode
        sessionConfiguration = updated
        persistSessionConfigurationIfNeeded()
    }

    private func resetSessionConfigurationToDefaults() {
        let model = modelCatalog.selectedModel
        let levels = ["none"] + model.supportedReasoningLevels
        let effort = levels.contains(settings.reasoningEffort)
            ? settings.reasoningEffort
            : model.defaultReasoningLevel
        sessionConfiguration = SessionAIConfiguration(
            modelID: model.id,
            reasoningEffort: effort,
            webSearchMode: settings.webSearchMode
        )
    }

    private func applyConfiguration(from session: ConversationSession) {
        let model = modelCatalog.models.first(where: { $0.id == session.modelID })
            ?? DeepSeekModel.fallbackModel(id: session.modelID)
            ?? modelCatalog.selectedModel
        let levels = ["none"] + model.supportedReasoningLevels
        let effort = levels.contains(session.reasoningEffort)
            ? session.reasoningEffort
            : model.defaultReasoningLevel
        let mode = WebSearchMode(rawValue: session.webSearchMode ?? "") ?? settings.webSearchMode
        sessionConfiguration = SessionAIConfiguration(
            modelID: model.id,
            reasoningEffort: effort,
            webSearchMode: mode
        )
    }

    private func persistSessionConfigurationIfNeeded() {
        guard let currentSessionID else { return }
        historyStore.updateConfiguration(
            id: currentSessionID,
            modelID: sessionConfiguration.modelID,
            reasoningEffort: sessionConfiguration.reasoningEffort,
            webSearchMode: sessionConfiguration.webSearchMode
        )
    }

    // MARK: - Automatic title generation

    private func startTitleGeneration(
        sessionID: UUID,
        turn: ConversationTurn,
        modelID: String,
        languageCode: String
    ) {
        let question = turn.question.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = turn.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !answer.isEmpty, settings.hasAPIKey else { return }

        let apiKey = settings.apiKey
        let baseURL = settings.baseURL
        let maxTitleLength = languageCode.lowercased().hasPrefix("en") ? 60 : 30
        Task { [weak self] in
            guard let self else { return }
            let request = ChatCompletionRequest(
                model: modelID,
                messages: [.user(ConversationTitle.instruction(
                    question: question,
                    answer: answer,
                    languageCode: languageCode
                ))],
                reasoningEffort: "none",
                tools: nil,
                maxTokens: 64
            )
            let client = DeepSeekClient(baseURL: baseURL)
            var raw = ""
            do {
                for try await event in client.streamChat(apiKey: apiKey, requestBody: request) {
                    if case .content(let delta) = event {
                        raw += delta
                    }
                }
            } catch {
                return
            }
            guard let title = ConversationTitle.sanitize(raw, maxLength: maxTitleLength) else { return }
            guard let stored = self.historyStore.sessions.first(where: { $0.id == sessionID }),
                  stored.autoTitleGenerated != true else { return }
            self.historyStore.updateTitle(id: sessionID, title: title, generated: true)
            if self.currentSessionID == sessionID {
                self.currentSessionTitle = title
                self.currentSessionTitleGenerated = true
            }
        }
    }

    // MARK: - Event handling

    private func consume(_ event: AgentEvent, for job: GenerationJob) {
        let isActive = activeJob === job

        func update(_ mutate: (inout ConversationTurn) -> Void) {
            guard !job.turns.isEmpty else { return }
            mutate(&job.turns[job.turns.count - 1])
            if isActive {
                turns = job.turns
            }
        }

        switch event {
        case .reasoningDelta(let delta):
            update { turn in
                if turn.reasoningStartedAt == nil {
                    turn.reasoningStartedAt = Date()
                }
                turn.reasoning += delta
            }

        case .contentDelta(let delta):
            update { turn in
                if turn.reasoningStartedAt != nil, turn.reasoningDuration == nil {
                    turn.reasoningDuration = Date().timeIntervalSince(turn.reasoningStartedAt ?? Date())
                }
                turn.answer += delta
            }

        case .searchStarted(let query):
            update { turn in
                turn.usedSearch = true
                if turn.reasoningStartedAt != nil, turn.reasoningDuration == nil {
                    turn.reasoningDuration = Date().timeIntervalSince(turn.reasoningStartedAt ?? Date())
                }
                turn.activities.append(SearchActivity(query: query, state: .searching))
            }

        case .searchSucceeded(let query, let sources):
            update { turn in
                if let index = turn.activities.lastIndex(where: { $0.query == query && $0.state == .searching }) {
                    turn.activities[index].state = .completed(count: sources.count)
                }
                var seenURLs = Set(turn.sources.map(\.url))
                for source in sources where seenURLs.insert(source.url).inserted {
                    turn.sources.append(source)
                }
            }

        case .searchFailed(let query, let message):
            update { turn in
                if let index = turn.activities.lastIndex(where: { $0.query == query && $0.state == .searching }) {
                    turn.activities[index].state = .failed(message: message)
                }
            }

        case .completed:
            break
        }

        if isActive {
            requestScroll()
        }
    }

    private func finish(_ job: GenerationJob, cancelled: Bool, error: String?) {
        guard job.isStreaming, backgroundJobs[job.id] === job else { return }
        job.isStreaming = false
        job.task = nil

        if !job.turns.isEmpty {
            job.turns[job.turns.count - 1].isStreaming = false
            if cancelled {
                job.turns[job.turns.count - 1].wasStopped = true
            }
            if let error {
                job.turns[job.turns.count - 1].errorMessage = error
            }
            if job.turns[job.turns.count - 1].reasoningStartedAt != nil,
               job.turns[job.turns.count - 1].reasoningDuration == nil {
                job.turns[job.turns.count - 1].reasoningDuration = Date().timeIntervalSince(
                    job.turns[job.turns.count - 1].reasoningStartedAt ?? Date()
                )
            }
            for index in job.turns[job.turns.count - 1].activities.indices {
                if job.turns[job.turns.count - 1].activities[index].state == .searching {
                    job.turns[job.turns.count - 1].activities[index].state = .failed(message: "搜索已中断")
                }
            }
        }

        let isActive = activeJob === job
        if isActive {
            turns = job.turns
            isStreaming = false
            streamTask = nil
            activeJob = nil
            requestScroll(force: true)
        }

        persist(job, touch: true)
        backgroundJobs.removeValue(forKey: job.id)

        if !cancelled, error == nil, job.turns.count == 1, !job.titleGenerated,
           let firstTurn = job.turns.first {
            startTitleGeneration(
                sessionID: job.id,
                turn: firstTurn,
                modelID: job.configuration.modelID,
                languageCode: job.languageCode
            )
        }
    }

    private func requestScroll(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastScrollTime) > 0.055 else { return }
        lastScrollTime = now
        scrollTick &+= 1
    }

}
