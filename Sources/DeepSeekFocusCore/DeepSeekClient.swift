import Foundation

public final class DeepSeekClient {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "https://api.deepseek.com")!, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 600
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.waitsForConnectivity = false
            configuration.httpAdditionalHeaders = [
                "User-Agent": "DeepSeekFocus/1.0 (macOS)"
            ]
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - Models

    public func fetchModels(apiKey: String) async throws -> [DeepSeekModel] {
        let key = normalizedAPIKey(apiKey)
        guard !key.isEmpty else { throw DeepSeekError.missingAPIKey }
        guard let url = endpoint("/models") else { throw DeepSeekError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await execute(request)
        try validate(response: response, data: data)
        do {
            let list = try JSONDecoder().decode(DeepSeekModelList.self, from: data)
            var seen = Set<String>()
            let models = list.data.filter { model in
                !model.id.isEmpty && seen.insert(model.id).inserted
            }
            guard !models.isEmpty else {
                throw DeepSeekError.invalidResponse(L10n.string("模型列表为空"))
            }
            return models
        } catch let error as DeepSeekError {
            throw error
        } catch {
            throw DeepSeekError.invalidResponse(L10n.string("模型列表格式不正确"))
        }
    }

    // MARK: - Chat

    public func streamChat(
        apiKey: String,
        requestBody: ChatCompletionRequest
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return }
                do {
                    let key = self.normalizedAPIKey(apiKey)
                    guard !key.isEmpty else { throw DeepSeekError.missingAPIKey }
                    guard let url = self.endpoint("/chat/completions") else {
                        throw DeepSeekError.invalidBaseURL
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 180
                    do {
                        request.httpBody = try JSONEncoder().encode(requestBody)
                    } catch {
                        throw DeepSeekError.invalidRequest(L10n.string("无法编码对话内容"))
                    }

                    let (bytes, response) = try await self.session.bytes(for: request)

                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count >= 131_072 { break }
                        }
                        throw self.httpError(status: http.statusCode, data: body)
                    }

                    var didEmitFinish = false
                    var lastFinishReason: String?
                    var lastUsage: TokenUsage?

                    // URLSession's AsyncLineSequence intentionally omits empty lines, so SSE
                    // events cannot be framed by waiting for the blank separator. OpenAI-compatible
                    // chat streams put each JSON payload on its own `data:` line, which we handle
                    // immediately. This is also more responsive than buffering until a blank line.
                    for try await rawLine in bytes.lines {
                        try Task.checkCancellation()
                        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
                        guard line.hasPrefix("data:") else { continue }
                        var payload = String(line.dropFirst(5))
                        if payload.hasPrefix(" ") { payload.removeFirst() }
                        payload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                        if payload == "[DONE]" { break }
                        guard !payload.isEmpty else { continue }

                        let chunk: ChatCompletionChunk
                        do {
                            chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(payload.utf8))
                        } catch {
                            throw DeepSeekError.invalidResponse(L10n.string("流式数据格式不正确"))
                        }

                        if let usage = chunk.usage {
                            lastUsage = usage
                        }
                        guard let choice = chunk.choices.first else { continue }
                        if let reasoning = choice.delta.reasoningContent, !reasoning.isEmpty {
                            continuation.yield(.reasoning(reasoning))
                        }
                        if let content = choice.delta.content, !content.isEmpty {
                            continuation.yield(.content(content))
                        }
                        if let calls = choice.delta.toolCalls, !calls.isEmpty {
                            continuation.yield(.toolCalls(calls))
                        }
                        if let reason = choice.finishReason {
                            lastFinishReason = reason
                            if !didEmitFinish {
                                didEmitFinish = true
                                continuation.yield(.finished(reason: reason, usage: lastUsage))
                            }
                        }
                    }

                    if !didEmitFinish {
                        continuation.yield(.finished(reason: lastFinishReason, usage: lastUsage))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: DeepSeekError.cancelled)
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: DeepSeekError.cancelled)
                } catch let error as DeepSeekError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: DeepSeekError.network(error.localizedDescription))
                } catch {
                    continuation.finish(throwing: DeepSeekError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Search

    public func search(
        apiKey: String,
        query: String,
        originalQuestion: String? = nil,
        count: Int = 6
    ) async throws -> [SearchSource] {
        let key = normalizedAPIKey(apiKey)
        guard !key.isEmpty else { throw DeepSeekError.missingAPIKey }
        let trimmedQuery = Self.truncated(query.trimmingCharacters(in: .whitespacesAndNewlines), length: 128)
        guard !trimmedQuery.isEmpty else {
            throw DeepSeekError.invalidRequest(L10n.string("搜索关键词不能为空"))
        }

        let path = baseURL.path.hasSuffix("/v1") ? "/tools/search" : "/v1/tools/search"
        guard let url = endpoint(path) else { throw DeepSeekError.invalidBaseURL }

        var lastError: DeepSeekError = .network(L10n.string("搜索请求失败"))
        for attempt in 0..<3 {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 40
            let body = SearchRequestBody(
                query: trimmedQuery,
                count: min(max(count, 1), 50),
                originalQuestion: originalQuestion.map { Self.truncated($0, length: 128) },
                needContent: false
            )
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw DeepSeekError.invalidRequest(L10n.string("无法编码搜索参数"))
            }

            do {
                let (data, response) = try await execute(request)
                try validate(response: response, data: data)
                do {
                    let result = try JSONDecoder().decode(SearchResponse.self, from: data)
                    return result.results.filter { $0.linkURL != nil }
                } catch {
                    throw DeepSeekError.invalidResponse(L10n.string("搜索结果格式不正确"))
                }
            } catch let error as DeepSeekError {
                lastError = error
                guard Self.shouldRetry(error: error, attempt: attempt) else { throw error }
            } catch let error as URLError {
                lastError = .network(error.localizedDescription)
                guard attempt < 2, error.code != .cancelled else {
                    throw error.code == .cancelled ? DeepSeekError.cancelled : lastError
                }
            } catch is CancellationError {
                throw DeepSeekError.cancelled
            } catch {
                lastError = .network(error.localizedDescription)
                guard attempt < 2 else { throw lastError }
            }

            let delay = 0.7 * pow(2.0, Double(attempt))
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        throw lastError
    }

    // MARK: - Plumbing

    private func endpoint(_ path: String) -> URL? {
        var raw = baseURL.absoluteString
        while raw.hasSuffix("/") { raw.removeLast() }
        let suffix = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: raw + suffix),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else {
            return nil
        }
        return url
    }

    private func execute(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw DeepSeekError.cancelled }
            throw DeepSeekError.network(error.localizedDescription)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse(L10n.string("缺少 HTTP 响应"))
        }
        guard (200...299).contains(http.statusCode) else {
            throw httpError(status: http.statusCode, data: data)
        }
    }

    private func httpError(status: Int, data: Data) -> DeepSeekError {
        let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        return .http(status: status, message: envelope?.error?.message)
    }

    private func normalizedAPIKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncated(_ text: String, length: Int) -> String {
        guard text.count > length else { return text }
        return String(text.prefix(length))
    }

    private static func shouldRetry(error: DeepSeekError, attempt: Int) -> Bool {
        guard attempt < 2 else { return false }
        switch error {
        case .http(let status, _):
            return status == 408 || status == 429 || (500...599).contains(status)
        case .network, .cancelled:
            return true
        default:
            return false
        }
    }
}

private struct SearchRequestBody: Encodable {
    let query: String
    let count: Int
    let originalQuestion: String?
    let needContent: Bool

    enum CodingKeys: String, CodingKey {
        case query
        case count
        case originalQuestion = "ori_question"
        case needContent = "need_content"
    }
}
