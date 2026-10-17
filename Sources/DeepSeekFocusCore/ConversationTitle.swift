import Foundation

/// Helpers for the small, cheap title-generation request made after the first
/// assistant reply. Keeping the prompt and sanitizer here makes them testable
/// without a network request.
public enum ConversationTitle {
    public static func instruction(
        question: String,
        answer: String,
        languageCode: String = "zh-Hans"
    ) -> String {
        let shortQuestion = String(question.prefix(500))
        let shortAnswer = String(answer.prefix(2_000))
        if languageCode.lowercased().hasPrefix("en") {
            return """
            You are a chat title generator. Create a short, specific title for the conversation below.

            Requirements:
            - Use English.
            - At most 8 words or 60 characters.
            - Output only the title itself, with no quotes, numbering, prefix, explanation, or trailing punctuation.

            User: \(shortQuestion)

            Assistant: \(shortAnswer)
            """
        }
        return """
        你是会话命名助手。请根据下面这段对话生成一个简短、具体的会话标题。

        要求：
        - 使用简体中文；
        - 不超过 14 个汉字或 28 个字符；
        - 只输出标题本身，不要引号、序号、前缀、解释或结尾标点。

        用户：\(shortQuestion)

        助手：\(shortAnswer)
        """
    }

    public static func sanitize(_ raw: String, maxLength: Int = 30) -> String? {
        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }

        // Models occasionally prefix the title or add an explanation after a newline.
        if let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true).first {
            text = String(firstLine)
        }

        let prefixes = ["标题：", "标题:", "Title:", "title:"]
        var removedPrefix = true
        while removedPrefix {
            removedPrefix = false
            for prefix in prefixes where text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                removedPrefix = true
            }
        }

        let quotes = CharacterSet(charactersIn: "\"'“”‘’《》「」『』【】")
        let trailing = CharacterSet(charactersIn: " \t\n\r.。!！?？;；,，:：")
        text = text.trimmingCharacters(in: quotes.union(trailing))

        text = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }
        if text.count > maxLength {
            text = String(text.prefix(maxLength))
            text = text.trimmingCharacters(in: quotes.union(trailing))
        }
        return text.isEmpty ? nil : text
    }
}
