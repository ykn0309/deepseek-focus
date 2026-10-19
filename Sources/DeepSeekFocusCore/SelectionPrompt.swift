import Foundation

public enum SelectionAction: String, Sendable {
    case ask
    case translate
    case dictionary
}

public struct SelectionActionConfiguration: Codable, Equatable, Sendable {
    public var modelID: String
    public var reasoningEffort: String
    public var webSearchEnabled: Bool

    public init(modelID: String, reasoningEffort: String, webSearchEnabled: Bool) {
        self.modelID = modelID
        self.reasoningEffort = reasoningEffort
        self.webSearchEnabled = webSearchEnabled
    }

    public static func defaultConfiguration(
        for action: SelectionAction,
        modelID: String,
        reasoningEffort: String
    ) -> SelectionActionConfiguration {
        switch action {
        case .ask:
            return SelectionActionConfiguration(
                modelID: modelID,
                reasoningEffort: reasoningEffort,
                webSearchEnabled: true
            )
        case .translate, .dictionary:
            return SelectionActionConfiguration(
                modelID: modelID,
                reasoningEffort: "none",
                webSearchEnabled: false
            )
        }
    }
}

public enum TranslationTarget: String, CaseIterable, Codable, Sendable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chinese: return L10n.string("中文")
        case .english: return "English"
        }
    }

    public static func systemDefault(for languageCode: String) -> TranslationTarget {
        languageCode.lowercased().hasPrefix("zh") ? .chinese : .english
    }
}

public enum SelectionPrompt {
    public static func make(
        text: String,
        action: SelectionAction,
        targetLanguage: TranslationTarget
    ) -> String {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case .ask:
            return content
        case .translate:
            switch targetLanguage {
            case .chinese:
                return "请把下面的内容翻译成中文，只输出译文：\n\n\(content)"
            case .english:
                return "Translate the following text into English. Output only the translation:\n\n\(content)"
            }
        case .dictionary:
            return content
        }
    }
}

public enum SelectionDictionaryPrompt {
    public static func make(text: String, languageCode: String) -> String {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isChinese = languageCode.lowercased().hasPrefix("zh")
        let instruction: String
        if isChinese {
            instruction = """
            请以简明词典的方式解释下面的词。释义、例句翻译使用中文；英文词给出 IPA 音标，中文词给出拼音。
            """
        } else {
            instruction = """
            Look up the term below in a concise dictionary style. Use English for definitions and example translations; give IPA for English terms and pinyin for Chinese terms.
            """
        }
        return """
        \(instruction)

        Return ONLY a valid JSON object with no markdown fences and no commentary, using exactly this shape:
        {"term":"...","pronunciation":"...","partOfSpeech":"...","definitions":[{"meaning":"...","example":"..."}],"examples":[{"text":"...","translation":"..."}],"synonyms":["..."],"notes":"..."}

        The term is:
        \(term)
        """
    }
}
