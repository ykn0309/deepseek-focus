import Foundation

// MARK: - Messages

public struct APIMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public var role: Role
    public var content: String?
    public var reasoningContent: String?
    public var toolCalls: [ChatToolCall]?
    public var toolCallID: String?

    /// DeepSeek rejects assistant messages that have neither text nor tool calls.
    /// Reasoning-only responses must not be replayed as assistant history.
    public var isEmptyAssistantMessage: Bool {
        guard role == .assistant else { return false }
        let hasText = !(content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasToolCalls = !(toolCalls ?? []).isEmpty
        return !hasText && !hasToolCalls
    }

    public init(
        role: Role,
        content: String?,
        reasoningContent: String? = nil,
        toolCalls: [ChatToolCall]? = nil,
        toolCallID: String? = nil
    ) {
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    public static func system(_ content: String) -> APIMessage {
        APIMessage(role: .system, content: content)
    }

    public static func user(_ content: String) -> APIMessage {
        APIMessage(role: .user, content: content)
    }

    public static func assistant(
        content: String?,
        reasoningContent: String? = nil,
        toolCalls: [ChatToolCall]? = nil
    ) -> APIMessage {
        APIMessage(
            role: .assistant,
            content: content,
            reasoningContent: reasoningContent,
            toolCalls: toolCalls
        )
    }

    public static func tool(_ content: String, toolCallID: String) -> APIMessage {
        APIMessage(role: .tool, content: content, toolCallID: toolCallID)
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)

        // DeepSeek requires assistant `content` to be present and nullable when
        // the assistant turn consists only of tool calls. Swift's synthesized
        // encoder omits nil optionals, so encode it explicitly.
        if role == .assistant {
            if let content {
                try container.encode(content, forKey: .content)
            } else {
                try container.encodeNil(forKey: .content)
            }
        } else if let content {
            try container.encode(content, forKey: .content)
        }

        if let reasoningContent {
            try container.encode(reasoningContent, forKey: .reasoningContent)
        }
        if let toolCalls {
            try container.encode(toolCalls, forKey: .toolCalls)
        }
        if let toolCallID {
            try container.encode(toolCallID, forKey: .toolCallID)
        }
    }
}

// MARK: - Request

public struct ThinkingConfiguration: Encodable, Sendable {
    public var type: String
    public init(enabled: Bool) { self.type = enabled ? "enabled" : "disabled" }
}

public struct StreamOptions: Encodable, Sendable {
    public var includeUsage: Bool
    public init(includeUsage: Bool = true) { self.includeUsage = includeUsage }
    enum CodingKeys: String, CodingKey { case includeUsage = "include_usage" }
}

public struct ChatCompletionRequest: Encodable, Sendable {
    public var model: String
    public var messages: [APIMessage]
    public var stream: Bool
    public var thinking: ThinkingConfiguration
    public var reasoningEffort: String?
    public var tools: [ToolDefinition]?
    public var toolChoice: String?
    public var streamOptions: StreamOptions
    public var maxTokens: Int

    public init(
        model: String,
        messages: [APIMessage],
        reasoningEffort: String,
        tools: [ToolDefinition]?,
        maxTokens: Int
    ) {
        self.model = model
        self.messages = messages
        self.stream = true
        self.thinking = ThinkingConfiguration(enabled: reasoningEffort != "none")
        // "none" is the app's synthetic switch for thinking.disabled. It is not
        // an effort level returned by DeepSeek's /models endpoint, so omit it.
        self.reasoningEffort = reasoningEffort == "none" ? nil : reasoningEffort
        self.tools = tools
        // Let the API apply its default (`auto`) rather than sending an explicit
        // tool_choice value, which differs across compatible endpoints.
        self.toolChoice = nil
        self.streamOptions = StreamOptions()
        self.maxTokens = maxTokens
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case thinking
        case reasoningEffort = "reasoning_effort"
        case tools
        case toolChoice = "tool_choice"
        case streamOptions = "stream_options"
        case maxTokens = "max_tokens"
    }
}

// MARK: - Tools

public struct ToolDefinition: Encodable, Equatable, Sendable {
    public var type: String
    public var function: FunctionDefinition

    public init(type: String = "function", function: FunctionDefinition) {
        self.type = type
        self.function = function
    }

    public struct FunctionDefinition: Encodable, Equatable, Sendable {
        public var name: String
        public var description: String
        public var parameters: JSONSchema

        public init(name: String, description: String, parameters: JSONSchema) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }
}

/// The tiny part of JSON Schema used by the app's single function tool.
public struct JSONSchema: Encodable, Equatable, Sendable {
    public struct Property: Encodable, Equatable, Sendable {
        public var type: String
        public var description: String

        public init(type: String, description: String) {
            self.type = type
            self.description = description
        }
    }

    public var type: String
    public var properties: [String: Property]
    public var required: [String]
    public var additionalProperties: Bool

    public init(
        type: String = "object",
        properties: [String: Property],
        required: [String],
        additionalProperties: Bool = false
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }

    enum CodingKeys: String, CodingKey {
        case type
        case properties
        case required
        case additionalProperties
    }
}

public enum WebSearchTool {
    public static let functionName = "web_search"

    public static let definition = ToolDefinition(
        function: .init(
            name: functionName,
            description: "使用 DeepSeek 搜索 API 检索实时网页。适用于新闻、实时数据、价格、天气、近期事件、人物近况、事实核查，或你不确定的信息。不要在纯推理、翻译、创意写作或普通编程问题上调用。",
            parameters: JSONSchema(
                properties: [
                    "query": .init(
                        type: "string",
                        description: "简洁、具体的搜索查询，最多 128 个字符。可使用 DeepSeek 搜索语法，如 site:、lang:、after:。"
                    )
                ],
                required: ["query"]
            )
        )
    )
}

// MARK: - Streaming

public struct ToolCallDelta: Decodable, Equatable, Sendable {
    public var index: Int
    public var id: String?
    public var type: String?
    public var function: FunctionDelta?

    public init(index: Int, id: String? = nil, type: String? = nil, function: FunctionDelta? = nil) {
        self.index = index
        self.id = id
        self.type = type
        self.function = function
    }

    public struct FunctionDelta: Decodable, Equatable, Sendable {
        public var name: String?
        public var arguments: String?

        public init(name: String? = nil, arguments: String? = nil) {
            self.name = name
            self.arguments = arguments
        }
    }
}

public struct ChatCompletionChunk: Decodable, Sendable {
    public struct Choice: Decodable, Sendable {
        public var index: Int?
        public var delta: Delta
        public var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case delta
            case finishReason = "finish_reason"
        }
    }

    public struct Delta: Decodable, Sendable {
        public var role: String?
        public var content: String?
        public var reasoningContent: String?
        public var toolCalls: [ToolCallDelta]?

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case reasoningContent = "reasoning_content"
            case toolCalls = "tool_calls"
        }
    }

    public var id: String?
    public var choices: [Choice]
    public var usage: TokenUsage?
}

public enum ChatStreamEvent: Sendable {
    case reasoning(String)
    case content(String)
    case toolCalls([ToolCallDelta])
    case finished(reason: String?, usage: TokenUsage?)
}

// MARK: - Aggregation

public struct ToolCallAccumulator: Sendable {
    public struct PartialCall: Sendable {
        public var id: String
        public var name: String
        public var arguments: String
    }

    private var storage: [Int: PartialCall] = [:]
    private var order: [Int] = []

    public init() {}

    public mutating func consume(_ deltas: [ToolCallDelta]) {
        for delta in deltas {
            if storage[delta.index] == nil {
                storage[delta.index] = PartialCall(id: "", name: "", arguments: "")
                order.append(delta.index)
            }
            if let id = delta.id, !id.isEmpty {
                storage[delta.index]?.id = id
            }
            if let name = delta.function?.name, !name.isEmpty {
                storage[delta.index]?.name += name
            }
            if let arguments = delta.function?.arguments {
                storage[delta.index]?.arguments += arguments
            }
        }
    }

    public var isEmpty: Bool { storage.isEmpty }

    public func resolved() -> [ChatToolCall] {
        order.compactMap { index in
            guard let partial = storage[index], !partial.name.isEmpty else { return nil }
            let id = partial.id.isEmpty ? "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))" : partial.id
            return ChatToolCall(
                id: id,
                function: ChatFunctionCall(name: partial.name, arguments: partial.arguments)
            )
        }
    }
}

// MARK: - Prompt

public enum FocusSystemPrompt {
    public static func make(
        now: Date = Date(),
        timeZone: TimeZone = .current,
        webSearchEnabled: Bool,
        languageCode: String = "zh-Hans"
    ) -> String {
        let english = languageCode.lowercased().hasPrefix("en")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: english ? "en_US" : "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = english ? "EEEE, MMMM d, yyyy HH:mm" : "yyyy 年 M 月 d 日 EEEE HH:mm"
        let dateText = formatter.string(from: now)
        let timeZoneName = timeZone.identifier

        var lines: [String] = english
            ? [
                "You are \"DeepSeek Focus\", a macOS AI search and Q&A assistant for users who want fast, reliable answers.",
                "",
                "Current time: \(dateText) (\(timeZoneName)).",
                "",
                "Response requirements:",
                "- Always answer in the language of the user's latest message. If the user writes in English, answer in English; if the user writes in Chinese, use Simplified Chinese. Never switch language just because this system prompt is written in English.",
                "- Lead with the direct answer, then add only the explanation that is needed. Keep it concise and readable in a small floating panel.",
                "- Use Markdown. Short paragraphs, lists, bold text, and code blocks are welcome, but do not output a top-level heading and do not repeat the user's question.",
                "- Do not fabricate facts, links, data, or quotations.",
                "- If real-time information is needed and you cannot confirm it, state the uncertainty honestly."
            ]
            : [
                "你是「DeepSeek 聚焦」，一个常驻 macOS 的 AI 搜索与问答助手。你面向的是希望快速得到可靠答案的用户。",
                "",
                "当前时间：\(dateText)（\(timeZoneName)）。",
                "",
                "回答要求：",
                "- 始终使用用户最新一条消息的语言回答：用户用英文提问就用英文回答，用中文提问就用简体中文回答。不要因为系统提示词是中文而改用中文。",
                "- 先给直接答案，再补充必要解释。保持简洁，适合在小型浮层中快速阅读。",
                "- 使用 Markdown 组织内容。可以使用短段落、列表、粗体和代码块，但不要输出一级标题，也不要重复用户的问题。",
                "- 不要编造事实，不要虚构链接、数据或引文。",
                "- 当问题涉及实时信息且你无法确认时，坦率说明不确定性。"
            ]

        if webSearchEnabled {
            lines.append(contentsOf: english
                ? [
                    "",
                    "Web search is enabled:",
                    "- For news, live data, prices, weather, recent events, people's current status, product or policy updates, or facts you are unsure about, call the `web_search` tool first.",
                    "- Everyday conversation, pure reasoning, translation, creative writing, general knowledge, and ordinary coding questions usually do not need a search. Do not search just to appear thorough.",
                    "- When using search results, cite sources as Markdown links in the relevant sentence using `[Site name](URL)`. Only cite links that actually appear in the tool result.",
                    "- If the search returns nothing useful, say so honestly and answer cautiously from your existing knowledge."
                ]
                : [
                    "",
                    "联网搜索已开启：",
                    "- 对于新闻、实时数据、价格、天气、近期事件、人物近况、产品或政策更新，或你自己没有把握的事实，先调用 `web_search` 工具。",
                    "- 日常闲聊、纯推理、翻译、创意写作、常识和普通编程问题通常不需要搜索。不要为了显得严谨而进行不必要的搜索。",
                    "- 使用搜索结果时，请在相关句子后用 Markdown 链接引用来源，格式为 `[站点名](URL)`。只引用工具返回内容中实际存在的链接。",
                    "- 如果搜索没有返回有用结果，请如实说明，并基于已有知识谨慎回答。"
                ])
        } else {
            lines.append(contentsOf: english
                ? [
                    "",
                    "Web search is disabled:",
                    "- You cannot access live web pages. Do not claim that you just searched.",
                    "- When a question depends on information that may be out of date, briefly remind the user that web search can be enabled in Settings."
                ]
                : [
                    "",
                    "联网搜索已关闭：",
                    "- 你无法访问实时网页，不要声称自己刚刚搜索过。",
                    "- 当问题依赖可能过时的信息时，简要提醒用户可以在设置中开启联网搜索。"
                ])
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Tool result formatting

public enum WebSearchResultFormatter {
    public static func make(
        query: String,
        sources: [SearchSource],
        languageCode: String = "zh-Hans"
    ) -> String {
        let english = languageCode.lowercased().hasPrefix("en")
        guard !sources.isEmpty else {
            return english
                ? "Web search found no results for \"\(query)\". Do not invent sources; you may say that nothing relevant was found."
                : "联网搜索没有找到与「\(query)」相关的结果。不要编造来源；可以直接说明没有找到相关信息。"
        }

        var lines: [String] = english
            ? [
                "The following real-time web results were retrieved through the DeepSeek Search API. Answer only from verifiable content in these results, and add the matching Markdown link after the relevant sentence.",
                "Search query: \(query)",
                "Result count: \(sources.count)",
                ""
            ]
            : [
                "以下是通过 DeepSeek 搜索 API 检索到的实时网页结果。请仅基于这些结果中可核实的内容作答，并在相关句子后附上对应的 Markdown 链接。",
                "搜索查询：\(query)",
                "结果数量：\(sources.count)",
                ""
            ]

        for (index, source) in sources.enumerated() {
            lines.append("[\(index + 1)] \(source.title)")
            lines.append(english ? "URL: \(source.url)" : "URL: \(source.url)")
            if !source.displaySiteName.isEmpty {
                lines.append(english ? "Site: \(source.displaySiteName)" : "站点: \(source.displaySiteName)")
            }
            if let date = source.date, !date.isEmpty {
                lines.append(english ? "Date: \(date)" : "日期: \(date)")
            }
            let body = [source.summary, source.snippet, source.content]
                .compactMap { $0 }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if let body {
                lines.append(english ? "Content: \(String(body.prefix(1_600)))" : "内容: \(String(body.prefix(1_600)))")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
