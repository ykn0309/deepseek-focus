import Foundation

/// Small runtime localization helper shared by Core and the app.
///
/// SwiftUI's static `Text` values are localized by the system using the
/// `.strings` resources in the app bundle. Dynamic strings (errors, status
/// messages, AppKit menu titles and formatted labels) use this helper so they
/// can switch immediately with the in-app language setting.
public enum L10n {
    public static var languageCode = "zh-Hans"

    public static var isEnglish: Bool {
        languageCode.lowercased().hasPrefix("en")
    }

    public static func string(_ key: String) -> String {
        guard isEnglish else { return key }
        return englishStrings[key] ?? key
    }

    public static func format(_ key: String, _ args: CVarArg...) -> String {
        String(
            format: string(key),
            locale: Locale(identifier: languageCode),
            arguments: args
        )
    }

    private static let englishStrings: [String: String] = {
        guard let localizationPath = Bundle.main.path(forResource: "en", ofType: "lproj") else {
            return [:]
        }
        let stringsPath = (localizationPath as NSString)
            .appendingPathComponent("Localizable.strings")
        return NSDictionary(contentsOfFile: stringsPath) as? [String: String] ?? [:]
    }()
}
