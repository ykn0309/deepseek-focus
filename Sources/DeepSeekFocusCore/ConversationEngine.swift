import Foundation

public struct ChatAgentConfiguration: Sendable {
    public var apiKey: String
    public var baseURL: URL
    public var model: String
    public var reasoningEffort: String
    public var webSearchEnabled: Bool
    public var languageCode: String
    public var now: Date
    public var timeZone: TimeZone
    public var maxSearchCount: Int

    public init(
        apiKey: String,
        baseURL: URL,
        model: String,
        reasoningEffort: String,
        webSearchEnabled: Bool,
        languageCode: String = "zh-Hans",
        now: Date = Date(),
        timeZone: TimeZone = .current,
        maxSearchCount: Int = 4
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.webSearchEnabled = webSearchEnabled
        self.languageCode = languageCode
        self.now = now
        self.timeZone = timeZone
        self.maxSearchCount = maxSearchCount
    }
}

public enum AgentEvent: Sendable {
    case reasoningDelta(String)
    case contentDelta(String)
    case searchStarted(query: String)
    case searchSucceeded(query: String, sources: [SearchSource])
    case searchFailed(query: String, message: String)
    case completed(usage: TokenUsage?, finishReason: String?)
}

/// Runs one assistant turn, including any model-initiated web searches, and keeps the raw
/// OpenAI-compatible message history required for multi-turn conversations.
@MainActor
public final class ConversationEngine {
    public private(set) var messages: [APIMessage] = []

    public init() {}

    public init(messages: [APIMessage]) {
        self.messages = messages.filter { !$0.isEmptyAssistantMessage }
    }

    public func reset() {
        messages.removeAll()
    }

    public func send(userText: String, configuration: ChatAgentConfiguration) -> AsyncThrowingStream<AgentEvent, Error> {
        let question = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append(.user(question))

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.runTurn(
                        question: question,
                        configuration: configuration,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: DeepSeekError.cancelled)
                } catch let error as DeepSeekError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: DeepSeekError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runTurn(
        question: String,
        configuration: ChatAgentConfiguration,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws {
        let client = DeepSeekClient(baseURL: configuration.baseURL)
        var allowTools = configuration.webSearchEnabled
        var searchCount = 0
        var searchCache: [String: [SearchSource]] = [:]
        var finalUsage: TokenUsage?
        var finalFinishReason: String?
        let maxRounds = 5

        for round in 0..<maxRounds {
            try Task.checkCancellation()
            let request = makeRequest(configuration: configuration, toolsEnabled: allowTools)
            var accumulator = ToolCallAccumulator()
            var roundText = ""
            var roundReasoning = ""
            var roundUsage: TokenUsage?
            var streamError: Error?

            let stream = client.streamChat(apiKey: configuration.apiKey, requestBody: request)
            do {
                for try await event in stream {
                    try Task.checkCancellation()
                    switch event {
                    case .reasoning(let delta):
                        roundReasoning += delta
                        continuation.yield(.reasoningDelta(delta))
                    case .content(let delta):
                        roundText += delta
                        continuation.yield(.contentDelta(delta))
                    case .toolCalls(let deltas):
                        accumulator.consume(deltas)
                    case .finished(let reason, let usage):
                        if let usage { roundUsage = usage }
                        if let reason { finalFinishReason = reason }
                    }
                }
            } catch {
                streamError = error
            }
            if let streamError {
                throw streamError
            }

            let toolCalls = accumulator.resolved()
            let answerText = roundText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answerText.isEmpty || !toolCalls.isEmpty else {
                throw DeepSeekError.invalidResponse(L10n.string("模型没有返回最终回答。"))
            }
            self.messages.append(.assistant(
                content: answerText.isEmpty ? nil : roundText,
                reasoningContent: roundReasoning.isEmpty ? nil : roundReasoning,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            ))
            if let roundUsage { finalUsage = roundUsage }

            guard !toolCalls.isEmpty else {
                continuation.yield(.completed(usage: finalUsage, finishReason: finalFinishReason))
                return
            }

            // Every tool call must receive a matching tool message, including unsupported tools,
            // otherwise the next request is rejected by the API.
            for call in toolCalls {
                try Task.checkCancellation()
                let toolResult: String
                if call.function.name != WebSearchTool.functionName {
                    toolResult = "未知工具：\(call.function.name)。请直接回答，或使用 web_search。"
                } else if searchCount >= configuration.maxSearchCount {
                    toolResult = "本轮联网搜索次数已达上限。请基于已有信息直接回答，不要再调用搜索。"
                } else {
                    guard let query = Self.searchQuery(from: call.function.arguments) else {
                        toolResult = "搜索参数不是有效的 JSON。请使用 {\"query\": \"关键词\"} 格式重新调用。"
                        self.messages.append(.tool(toolResult, toolCallID: call.id))
                        continue
                    }
                    if let cached = searchCache[query] {
                        toolResult = WebSearchResultFormatter.make(query: query, sources: cached, languageCode: configuration.languageCode)
                        continuation.yield(.searchSucceeded(query: query, sources: cached))
                    } else {
                        searchCount += 1
                        continuation.yield(.searchStarted(query: query))
                        do {
                            let sources = try await client.search(
                                apiKey: configuration.apiKey,
                                query: query,
                                originalQuestion: question
                            )
                            searchCache[query] = sources
                            toolResult = WebSearchResultFormatter.make(query: query, sources: sources, languageCode: configuration.languageCode)
                            continuation.yield(.searchSucceeded(query: query, sources: sources))
                        } catch let error as DeepSeekError where error.isCancellation {
                            throw error
                        } catch {
                            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            continuation.yield(.searchFailed(query: query, message: message))
                            toolResult = "联网搜索失败：\(message)。请不要重复调用搜索，基于已有信息谨慎回答，并说明搜索不可用。"
                        }
                    }
                }
                self.messages.append(.tool(toolResult, toolCallID: call.id))
            }

            // Keep at least two tool-free rounds so the model is guaranteed an
            // opportunity to produce a final answer if it keeps requesting searches.
            allowTools = configuration.webSearchEnabled
                && searchCount < configuration.maxSearchCount
                && round < 2
        }

        continuation.yield(.completed(usage: finalUsage, finishReason: finalFinishReason))
    }

    private func makeRequest(
        configuration: ChatAgentConfiguration,
        toolsEnabled: Bool
    ) -> ChatCompletionRequest {
        let system = FocusSystemPrompt.make(
            now: configuration.now,
            timeZone: configuration.timeZone,
            webSearchEnabled: configuration.webSearchEnabled,
            languageCode: configuration.languageCode
        )
        let usableMessages = messages.filter { !$0.isEmptyAssistantMessage }
        let messagesWithSystem = [APIMessage.system(system)] + usableMessages
        return ChatCompletionRequest(
            model: configuration.model,
            messages: messagesWithSystem,
            reasoningEffort: configuration.reasoningEffort,
            tools: toolsEnabled ? [WebSearchTool.definition] : nil,
            maxTokens: Self.maxTokens(for: configuration.reasoningEffort)
        )
    }

    private static func maxTokens(for effort: String) -> Int {
        switch effort {
        case "none": return 4_096
        case "low", "minimal": return 8_192
        case "max", "xhigh": return 32_768
        default: return 16_384
        }
    }

    private static func searchQuery(from arguments: String) -> String? {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["query"] as? String else {
            return nil
        }
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        if query.count > 128 { return String(query.prefix(128)) }
        return query
    }
}
