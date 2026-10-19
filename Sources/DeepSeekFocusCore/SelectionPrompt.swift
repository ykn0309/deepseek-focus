import Foundation

public enum SelectionAction: String, Sendable {
    case ask
    case translate
}

public enum SelectionPrompt {
    public static func make(
        text: String,
        action: SelectionAction,
        languageCode: String
    ) -> String {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case .ask:
            return content
        case .translate:
            let hasHan = content.unicodeScalars.contains { scalar in
                switch scalar.value {
                case 0x3400...0x9FFF, 0xF900...0xFAFF: return true
                default: return false
                }
            }
            if languageCode.lowercased().hasPrefix("zh") {
                let target = hasHan ? "英文" : "中文"
                return "请把下面的内容翻译成\(target)，只输出译文：\n\n\(content)"
            }
            let target = hasHan ? "English" : "Chinese"
            return "Translate the following text into \(target). Output only the translation:\n\n\(content)"
        }
    }
}
