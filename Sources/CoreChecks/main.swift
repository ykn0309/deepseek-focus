import Foundation
import DeepSeekFocusCore

@main
struct CoreChecks {
    static func main() {
        var failures = 0

        func check(_ condition: Bool, _ message: String) {
            if condition {
                print("  ok  \(message)")
            } else {
                failures += 1
                print("  FAIL \(message)")
            }
        }

        print("SSE decoder")
        var decoder = SSEEventDecoder()
        check(decoder.consume(line: ": keep-alive") == nil, "ignores comments")
        check(decoder.consume(line: "data: {\"a\":1}") == nil, "buffers data")
        check(decoder.consume(line: "") == "{\"a\":1}", "emits event on blank line")
        _ = decoder.consume(line: "data: first")
        _ = decoder.consume(line: "data: second")
        check(decoder.consume(line: "") == "first\nsecond", "joins multiple data lines")
        _ = decoder.consume(line: "data: trailing")
        check(decoder.finish() == "trailing", "flushes final event")

        print("Tool call aggregation")
        var accumulator = ToolCallAccumulator()
        accumulator.consume([
            ToolCallDelta(index: 0, id: "call_abc", type: "function", function: .init(name: "web_", arguments: "{\"que"))
        ])
        accumulator.consume([
            ToolCallDelta(index: 0, function: .init(name: "search", arguments: "ry\":\"DeepSeek\"}"))
        ])
        let resolved = accumulator.resolved()
        check(resolved.count == 1, "resolves one call")
        check(resolved.first?.id == "call_abc", "keeps call id")
        check(resolved.first?.function.name == "web_search", "accumulates name fragments")
        check(resolved.first?.function.arguments == "{\"query\":\"DeepSeek\"}", "accumulates argument fragments")

        print("Model catalog decoding")
        let modelsJSON = """
        {"object":"list","data":[
          {"id":"deepseek-flash","object":"model","owned_by":"deepseek","name":"DeepSeek-V4.1-Flash",
           "context_window":1048576,"max_output_tokens":393216,
           "input_modalities":["text","image"],"output_modalities":["text"],
           "effort":{"supported_levels":["low","high","max"],"default_level":"high"}}
        ]}
        """
        if let list = try? JSONDecoder().decode(DeepSeekModelList.self, from: Data(modelsJSON.utf8)),
           let model = list.data.first {
            check(model.displayName == "DeepSeek-V4.1-Flash", "decodes display name")
            check(model.supportedReasoningLevels == ["low", "high", "max"], "decodes effort levels")
            check(model.defaultReasoningLevel == "high", "decodes default effort")
            check(model.contextWindow == 1_048_576, "decodes context window")
        } else {
            check(false, "decodes model list")
        }

        print("Search decoding")
        let searchJSON = """
        {"results":[{"rerank_score":2.4,"title":"A title","url":"https://example.com/a",
        "snippet":"short","summary":"long","content":"","site_name":"Example","site_icon":null,
        "date":"2026-06-01T00:00:00+00:00","authority":3}]}
        """
        if let response = try? JSONDecoder().decode(SearchResponse.self, from: Data(searchJSON.utf8)) {
            check(response.results.count == 1, "decodes search result")
            check(response.results[0].displaySiteName == "Example", "uses site name")
            check(response.results[0].linkURL != nil, "validates http URL")
        } else {
            check(false, "decodes search response")
        }

        print("Request encoding")
        let messages = [
            APIMessage.system("You are helpful."),
            APIMessage.user("Hi"),
            APIMessage.assistant(content: "Let me check.", reasoningContent: "reasoning", toolCalls: [
                ChatToolCall(id: "c1", function: .init(name: "web_search", arguments: "{\"query\":\"x\"}"))
            ]),
            APIMessage.tool("result", toolCallID: "c1")
        ]
        let request = ChatCompletionRequest(
            model: "deepseek-flash",
            messages: messages,
            reasoningEffort: "high",
            tools: [WebSearchTool.definition],
            maxTokens: 8_192
        )
        if let data = try? JSONEncoder().encode(request),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            check(json["reasoning_effort"] as? String == "high", "encodes reasoning_effort")
            check((json["thinking"] as? [String: Any])?["type"] as? String == "enabled", "encodes thinking")
            check(json["stream"] as? Bool == true, "encodes streaming")
            check(json["tools"] != nil, "encodes tools")
            if let encoded = json["messages"] as? [[String: Any]] {
                check(encoded[2]["reasoning_content"] as? String == "reasoning", "encodes reasoning_content")
                check(encoded[3]["tool_call_id"] as? String == "c1", "encodes tool_call_id")
                check((encoded[2]["tool_calls"] as? [[String: Any]])?.count == 1, "encodes tool calls")
            } else {
                check(false, "encodes message array")
            }
        } else {
            check(false, "encodes request JSON")
        }

        let disabled = ChatCompletionRequest(
            model: "deepseek-flash",
            messages: [.user("Hi")],
            reasoningEffort: "none",
            tools: nil,
            maxTokens: 2_048
        )
        if let data = try? JSONEncoder().encode(disabled),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            check((json["thinking"] as? [String: Any])?["type"] as? String == "disabled", "disables thinking for none")
            check(json["reasoning_effort"] == nil, "omits non-official reasoning_effort for none")
            check(json["tools"] == nil, "omits tools when disabled")
        }

        check(ReasoningEffortCopy.title(for: "custom") == "custom", "unknown effort label is unchanged")
        check(ReasoningEffortCopy.title(for: "none") == "Off", "synthetic off label")
        check(ReasoningEffortCopy.title(for: "low") == "Low", "official low label")
        check(ReasoningEffortCopy.title(for: "high") == "High", "official high label")
        check(ReasoningEffortCopy.title(for: "max") == "Max", "official max label")

        check(ConversationTitle.sanitize("“示例标题”") == "示例标题", "strips title quotes")
        check(ConversationTitle.sanitize("标题：AI 行业动态。\n解释内容") == "AI 行业动态", "strips title prefix and explanation")
        check(ConversationTitle.sanitize("   \n  ") == nil, "rejects an empty title")
        let titlePrompt = ConversationTitle.instruction(question: "介绍一下牛顿第二定律", answer: "牛顿第二定律描述了力、质量和加速度之间的关系。")
        check(titlePrompt.contains("介绍一下牛顿第二定律"), "title prompt includes question")
        check(titlePrompt.contains("牛顿第二定律"), "title prompt includes answer")
        check(titlePrompt.contains("使用简体中文"), "uses Chinese title instructions by default")

        let englishTitlePrompt = ConversationTitle.instruction(
            question: "Explain inflation",
            answer: "Inflation is a rise in the general price level.",
            languageCode: "en"
        )
        check(englishTitlePrompt.contains("Use English"), "localizes title instructions to English")
        check(englishTitlePrompt.contains("User: Explain inflation"), "keeps the question in English title prompt")

        print("Syntax highlighting")
        func hasToken(
            _ tokens: [SyntaxToken],
            _ kind: SyntaxTokenKind,
            in source: String,
            containing needle: String
        ) -> Bool {
            tokens.contains { token in
                token.kind == kind && source[token.range].contains(needle)
            }
        }

        let bashCode = """
        npx skills add vercel-labs/agent-skills --skill frontend-design
        export TOKEN="abc" # note
        echo $TOKEN
        """
        let bashTokens = SyntaxHighlighter.tokens(in: bashCode, language: "bash")
        check(hasToken(bashTokens, .comment, in: bashCode, containing: "note"), "highlights shell comments")
        check(hasToken(bashTokens, .string, in: bashCode, containing: "abc"), "highlights shell strings")
        check(hasToken(bashTokens, .keyword, in: bashCode, containing: "export"), "highlights shell keywords")
        check(hasToken(bashTokens, .variable, in: bashCode, containing: "$TOKEN"), "highlights shell variables")
        check(hasToken(bashTokens, .function, in: bashCode, containing: "npx"), "highlights shell commands")

        let swiftCode = "let answer = 42 // note\nprint(\"hi\")"
        let swiftTokens = SyntaxHighlighter.tokens(in: swiftCode, language: "swift")
        check(hasToken(swiftTokens, .keyword, in: swiftCode, containing: "let"), "highlights Swift keywords")
        check(hasToken(swiftTokens, .number, in: swiftCode, containing: "42"), "highlights numbers")
        check(hasToken(swiftTokens, .comment, in: swiftCode, containing: "note"), "highlights Swift comments")
        check(hasToken(swiftTokens, .string, in: swiftCode, containing: "hi"), "highlights Swift strings")
        check(hasToken(swiftTokens, .function, in: swiftCode, containing: "print"), "highlights function calls")

        let jsonCode = "{\"key\": true}"
        let jsonTokens = SyntaxHighlighter.tokens(in: jsonCode, language: "json")
        check(hasToken(jsonTokens, .property, in: jsonCode, containing: "key"), "highlights JSON keys")
        check(hasToken(jsonTokens, .literal, in: jsonCode, containing: "true"), "highlights JSON literals")

        check(VersionCompare.isNewer("v1.8.14", than: "1.8.13"), "detects a newer patch version")
        check(!VersionCompare.isNewer("v1.8.13", than: "1.8.13"), "equal versions are not newer")
        check(VersionCompare.isNewer("1.9", than: "1.8.99"), "compares missing components as zero")
        check(!VersionCompare.isNewer("1.8", than: "1.8.0"), "treats missing components as zero")
        check(!VersionCompare.isNewer("1.8.13-beta.1", than: "1.8.13"), "ignores prerelease suffix")

        print("Prompt and tool result")
        let prompt = FocusSystemPrompt.make(
            now: Date(timeIntervalSince1970: 1_782_000_000),
            timeZone: TimeZone(identifier: "Asia/Shanghai")!,
            webSearchEnabled: true
        )
        check(prompt.contains("web_search"), "mentions search tool when enabled")
        check(prompt.contains("当前时间"), "contains current time")
        let noWebPrompt = FocusSystemPrompt.make(webSearchEnabled: false)
        check(noWebPrompt.contains("联网搜索已关闭"), "reflects disabled search")
        check(noWebPrompt.contains("不要因为系统提示词是中文而改用中文"), "forces user-language matching in Chinese prompt")

        let englishPrompt = FocusSystemPrompt.make(webSearchEnabled: false, languageCode: "en")
        check(englishPrompt.contains("Current time"), "localizes the prompt to English")
        check(englishPrompt.contains("Web search is disabled"), "localizes disabled search to English")
        check(englishPrompt.contains("language of the user's latest message"), "forces user-language matching in English prompt")

        let sources = [
            SearchSource(
                title: "Example source",
                url: "https://example.com/source",
                summary: "This is a summary.",
                siteName: "Example"
            )
        ]
        let toolResult = WebSearchResultFormatter.make(query: "test query", sources: sources)
        check(toolResult.contains("https://example.com/source"), "formats source URL")
        check(toolResult.contains("This is a summary."), "formats source summary")
        check(toolResult.contains("test query"), "formats search query")

        let englishToolResult = WebSearchResultFormatter.make(
            query: "test query",
            sources: sources,
            languageCode: "en"
        )
        check(englishToolResult.contains("Search query: test query"), "localizes search results to English")
        check(englishToolResult.contains("Example source"), "keeps source titles in English results")

        if failures > 0 {
            print("\n\(failures) check(s) failed")
            exit(1)
        }
        print("\nAll core checks passed")
    }
}
