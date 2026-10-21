import Foundation

// MARK: - Models

public struct DeepSeekModelEffort: Codable, Equatable, Sendable {
    public var supportedLevels: [String]
    public var defaultLevel: String?

    public init(supportedLevels: [String], defaultLevel: String? = nil) {
        self.supportedLevels = supportedLevels
        self.defaultLevel = defaultLevel
    }

    enum CodingKeys: String, CodingKey {
        case supportedLevels = "supported_levels"
        case defaultLevel = "default_level"
    }
}

public struct DeepSeekModel: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var object: String?
    public var ownedBy: String?
    public var name: String?
    public var contextWindow: Int?
    public var maxOutputTokens: Int?
    public var inputModalities: [String]?
    public var outputModalities: [String]?
    public var effort: DeepSeekModelEffort?

    public init(
        id: String,
        object: String? = "model",
        ownedBy: String? = "deepseek",
        name: String? = nil,
        contextWindow: Int? = nil,
        maxOutputTokens: Int? = nil,
        inputModalities: [String]? = nil,
        outputModalities: [String]? = nil,
        effort: DeepSeekModelEffort? = nil
    ) {
        self.id = id
        self.object = object
        self.ownedBy = ownedBy
        self.name = name
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.inputModalities = inputModalities
        self.outputModalities = outputModalities
        self.effort = effort
    }

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case ownedBy = "owned_by"
        case name
        case contextWindow = "context_window"
        case maxOutputTokens = "max_output_tokens"
        case inputModalities = "input_modalities"
        case outputModalities = "output_modalities"
        case effort
    }

    public var displayName: String {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return id
        }
        return name
    }

    /// Effort levels currently advertised by the API, without the synthetic "none" level.
    public var supportedReasoningLevels: [String] {
        let levels = effort?.supportedLevels ?? []
        let valid = levels.filter { !$0.isEmpty && $0 != "none" }
        return valid.isEmpty ? ["low", "high", "max"] : valid
    }

    public var defaultReasoningLevel: String {
        if let level = effort?.defaultLevel, supportedReasoningLevels.contains(level) {
            return level
        }
        if supportedReasoningLevels.contains("high") { return "high" }
        return supportedReasoningLevels.first ?? "high"
    }

    public static let fallbackModels: [DeepSeekModel] = [
        DeepSeekModel(
            id: "deepseek-flash",
            name: "DeepSeek-V4.1-Flash",
            contextWindow: 1_048_576,
            maxOutputTokens: 393_216,
            inputModalities: ["text", "image"],
            effort: DeepSeekModelEffort(supportedLevels: ["low", "high", "max"], defaultLevel: "high")
        ),
        DeepSeekModel(
            id: "deepseek-v4-pro",
            name: "DeepSeek-V4-Pro",
            contextWindow: 1_048_576,
            maxOutputTokens: 393_216,
            inputModalities: ["text"],
            effort: DeepSeekModelEffort(supportedLevels: ["low", "high", "max"], defaultLevel: "high")
        )
    ]

    public static func fallbackModel(id: String) -> DeepSeekModel? {
        fallbackModels.first { $0.id == id }
    }
}

public struct DeepSeekModelList: Decodable, Sendable {
    public let data: [DeepSeekModel]
}

// MARK: - Search

public struct SearchSource: Codable, Identifiable, Hashable, Sendable {
    public var title: String
    public var url: String
    public var snippet: String?
    public var summary: String?
    public var content: String?
    public var siteName: String?
    public var siteIcon: String?
    public var date: String?
    public var authority: Int?
    public var rerankScore: Double?

    public init(
        title: String,
        url: String,
        snippet: String? = nil,
        summary: String? = nil,
        content: String? = nil,
        siteName: String? = nil,
        siteIcon: String? = nil,
        date: String? = nil,
        authority: Int? = nil,
        rerankScore: Double? = nil
    ) {
        self.title = title
        self.url = url
        self.snippet = snippet
        self.summary = summary
        self.content = content
        self.siteName = siteName
        self.siteIcon = siteIcon
        self.date = date
        self.authority = authority
        self.rerankScore = rerankScore
    }

    enum CodingKeys: String, CodingKey {
        case title
        case url
        case snippet
        case summary
        case content
        case siteName = "site_name"
        case siteIcon = "site_icon"
        case date
        case authority
        case rerankScore = "rerank_score"
    }

    public var id: String { url }

    public var domain: String {
        guard let host = URL(string: url)?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public var displaySiteName: String {
        if let siteName, !siteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return siteName
        }
        return domain
    }

    public var linkURL: URL? {
        guard let value = URL(string: url), let scheme = value.scheme,
              scheme == "http" || scheme == "https" else { return nil }
        return value
    }
}

public struct SearchResponse: Decodable, Sendable {
    public let results: [SearchSource]
}

// MARK: - History and usage

public struct ChatToolCall: Codable, Equatable, Sendable {
    public var id: String
    public var type: String
    public var function: ChatFunctionCall

    public init(id: String, type: String = "function", function: ChatFunctionCall) {
        self.id = id
        self.type = type
        self.function = function
    }
}

public struct ChatFunctionCall: Codable, Equatable, Sendable {
    public var name: String
    public var arguments: String

    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var promptTokensDetails: PromptTokenDetails?
    public var completionTokensDetails: CompletionTokenDetails?

    public init(
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        promptTokensDetails: PromptTokenDetails? = nil,
        completionTokensDetails: CompletionTokenDetails? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.promptTokensDetails = promptTokensDetails
        self.completionTokensDetails = completionTokensDetails
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptTokensDetails = "prompt_tokens_details"
        case completionTokensDetails = "completion_tokens_details"
    }

    public struct PromptTokenDetails: Codable, Equatable, Sendable {
        public var cachedTokens: Int?
        enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens" }
        public init(cachedTokens: Int? = nil) { self.cachedTokens = cachedTokens }
    }

    public struct CompletionTokenDetails: Codable, Equatable, Sendable {
        public var reasoningTokens: Int?
        enum CodingKeys: String, CodingKey { case reasoningTokens = "reasoning_tokens" }
        public init(reasoningTokens: Int? = nil) { self.reasoningTokens = reasoningTokens }
    }
}

// MARK: - Errors

public enum DeepSeekError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case invalidBaseURL
    case invalidRequest(String)
    case http(status: Int, message: String?)
    case invalidResponse(String)
    case network(String)
    case streamIncomplete
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return L10n.string("还没有配置 DeepSeek API Key。请在设置中填写后再试。")
        case .invalidBaseURL:
            return L10n.string("DeepSeek API 地址无效。")
        case .invalidRequest(let message):
            return L10n.format("请求无法发送：%@", message)
        case .http(let status, let message):
            return Self.friendlyHTTPMessage(status: status, serverMessage: message)
        case .invalidResponse(let message):
            return L10n.format("DeepSeek 返回了无法解析的数据：%@", message)
        case .network(let message):
            return L10n.format("网络连接失败：%@", message)
        case .streamIncomplete:
            return L10n.string("连接提前结束，回答可能不完整。")
        case .cancelled:
            return L10n.string("已停止生成。")
        }
    }

    public var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }

    private static func friendlyHTTPMessage(status: Int, serverMessage: String?) -> String {
        let detail = serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch status {
        case 400:
            if let detail, !detail.isEmpty { return L10n.format("请求参数有误：%@", detail) }
            return L10n.string("请求参数有误。")
        case 401:
            return L10n.string("API Key 无效或已过期，请在设置中检查。")
        case 402:
            return L10n.string("DeepSeek 账户余额不足，请充值后再试。")
        case 403:
            return L10n.string("请求被 DeepSeek 拒绝。")
        case 404:
            return L10n.string("找不到 DeepSeek API 接口，请稍后重试。")
        case 408:
            return L10n.string("请求超时，请重试。")
        case 413:
            return L10n.string("请求内容过大。")
        case 429:
            return L10n.string("请求过于频繁，请稍后再试。")
        case 500...599:
            return L10n.format("DeepSeek 服务暂时不可用（HTTP %ld），请稍后重试。", status)
        default:
            if let detail, !detail.isEmpty { return detail }
            return L10n.format("请求失败（HTTP %ld）。", status)
        }
    }
}

// MARK: - Envelope

public struct APIErrorEnvelope: Decodable, Sendable {
    public struct APIError: Decodable, Sendable {
        public let message: String?
        public let type: String?
        public let code: String?
    }
    public let error: APIError?
}

// MARK: - Formatting helpers

public enum ReasoningEffortCopy {
    /// Display labels intentionally use DeepSeek's official effort identifiers
    /// rather than Chinese aliases. "none" is the app's synthetic off switch.
    public static func title(for level: String) -> String {
        switch level {
        case "none": return "Off"
        case "minimal": return "Minimal"
        case "low": return "Low"
        case "medium": return "Medium"
        case "high": return "High"
        case "xhigh": return "XHigh"
        case "max": return "Max"
        default: return level.isEmpty ? "—" : level
        }
    }

    public static func detail(for level: String) -> String {
        switch level {
        case "none": return "不展示思考过程，响应最快。"
        case "minimal": return "最少的思考，适合简单问答。"
        case "low": return "轻量思考，速度与质量平衡。"
        case "medium": return "标准思考深度。"
        case "high": return "更完整的推理，适合复杂问题。"
        case "xhigh": return "更深入的推理，响应会更慢。"
        case "max": return "最深入的推理，耗时和消耗最高。"
        default: return "由 DeepSeek 模型决定思考深度。"
        }
    }
}


public enum ChatFinishReason {
    /// Returns a user-facing notice when a terminal finish reason is not a
    /// normal `stop`. A nil result means the response is complete.
    public static func notice(for reason: String?) -> String? {
        guard let reason, !reason.isEmpty, reason != "stop" else { return nil }
        switch reason {
        case "length":
            return L10n.string("回答达到长度上限，可能不完整。")
        case "content_filter":
            return L10n.string("回答被内容安全策略截断。")
        case "aborted":
            return L10n.string("生成被中断，回答可能不完整。")
        case "tool_calls":
            return L10n.string("模型未能在本轮完成最终回答。")
        case "insufficient_system_resource":
            return L10n.string("服务资源不足，回答可能不完整。")
        default:
            return L10n.format("回答提前结束（%@），可能不完整。", reason)
        }
    }
}
