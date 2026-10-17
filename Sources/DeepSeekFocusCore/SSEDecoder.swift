import Foundation

/// Incremental decoder for a Server-Sent Events stream that exposes events as data payloads.
public struct SSEEventDecoder {
    private var dataLines: [String] = []

    public init() {}

    /// Feed a single line (without its trailing newline). Returns a complete event payload when
    /// the blank line separating events is encountered.
    public mutating func consume(line: String) -> String? {
        let normalized = line.hasSuffix("\r") ? String(line.dropLast()) : line
        if normalized.isEmpty {
            return flush()
        }
        if normalized.hasPrefix(":") {
            return nil
        }

        let field: String
        var value: String
        if let colon = normalized.firstIndex(of: ":") {
            field = String(normalized[..<colon])
            let afterColon = normalized.index(after: colon)
            value = String(normalized[afterColon...])
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            field = normalized
            value = ""
        }

        if field == "data" {
            dataLines.append(value)
        }
        return nil
    }

    /// Finish the stream. Some servers close without a final blank line.
    public mutating func finish() -> String? {
        flush()
    }

    private mutating func flush() -> String? {
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        dataLines.removeAll(keepingCapacity: true)
        return payload
    }
}
