import Foundation
import DeepSeekFocusCore
import ServiceManagement

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    static var systemCode: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.lowercased().hasPrefix("zh") ? "zh-Hans" : "en"
    }

    var resolvedCode: String {
        switch self {
        case .system: return Self.systemCode
        case .simplifiedChinese, .english: return rawValue
        }
    }

    var locale: Locale { Locale(identifier: resolvedCode) }

    var title: String {
        switch self {
        case .system: return L10n.string("跟随系统")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }
}

enum WebSearchMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "自动搜索"
        case .off: return "关闭搜索"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "由模型判断是否需要搜索。新闻、实时数据等时效性问题会先调用 DeepSeek 搜索 API。"
        case .off:
            return "只使用模型已有知识回答，不发起任何联网搜索。"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let officialBaseURL = URL(string: "https://api.deepseek.com")!

    private enum Key {
        static let model = "deepseek.selectedModel"
        static let reasoning = "deepseek.reasoningEffort"
        static let searchMode = "deepseek.webSearchMode"
        static let shortcut = "deepseek.shortcut"
        static let hasLaunched = "deepseek.hasLaunched"
        static let lastLaunchedVersion = "deepseek.lastLaunchedVersion"
        static let appLanguage = "deepseek.appLanguage"
        static let showMenuBarIcon = "deepseek.showMenuBarIcon"
    }

    @Published var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            scheduleKeySave()
        }
    }
    @Published var selectedModelID: String {
        didSet { defaults.set(selectedModelID, forKey: Key.model) }
    }
    @Published var reasoningEffort: String {
        didSet { defaults.set(reasoningEffort, forKey: Key.reasoning) }
    }
    @Published var webSearchMode: WebSearchMode {
        didSet { defaults.set(webSearchMode.rawValue, forKey: Key.searchMode) }
    }
    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Key.appLanguage)
            L10n.languageCode = appLanguage.resolvedCode
            onLanguageChange?()
        }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }
    @Published private(set) var shortcut: AppShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) {
                defaults.set(data, forKey: Key.shortcut)
            }
        }
    }
    @Published var shortcutError: String?
    @Published var credentialError: String?
    @Published private(set) var launchAtLogin = false
    @Published var launchAtLoginError: String?

    let baseURL: URL
    var hotKeyRegistrationHandler: ((AppShortcut) -> String?)?
    var onLanguageChange: (() -> Void)?

    private let defaults: UserDefaults
    private let credentialStore: APIKeyStore
    private var keySaveTask: Task<Void, Never>?
    private var apiKeyNeedsSave = false

    init(
        defaults: UserDefaults = .standard,
        credentialStore: APIKeyStore = APIKeyStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore

        let environmentBase = environment["DEEPSEEK_FOCUS_BASE_URL"]
        if let environmentBase,
           let url = URL(string: environmentBase),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           url.host != nil {
            self.baseURL = url
        } else {
            self.baseURL = Self.officialBaseURL
        }

        var storedKey = ""
        var initialCredentialError: String?
        do {
            storedKey = try credentialStore.read() ?? ""
        } catch {
            initialCredentialError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        let environmentKey = environment["DEEPSEEK_FOCUS_API_KEY"] ?? ""
        self.apiKey = storedKey.isEmpty ? environmentKey : storedKey

        self.selectedModelID = defaults.string(forKey: Key.model) ?? "deepseek-flash"
        self.reasoningEffort = defaults.string(forKey: Key.reasoning) ?? "high"
        let storedMode = defaults.string(forKey: Key.searchMode)
        self.webSearchMode = WebSearchMode(rawValue: storedMode ?? "") ?? .automatic
        let language = AppLanguage(rawValue: defaults.string(forKey: Key.appLanguage) ?? "") ?? .system
        self.appLanguage = language
        self.showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
        L10n.languageCode = language.resolvedCode
        if let data = defaults.data(forKey: Key.shortcut),
           let decoded = try? JSONDecoder().decode(AppShortcut.self, from: data) {
            self.shortcut = decoded
        } else {
            self.shortcut = .default
        }
        self.credentialError = initialCredentialError

        refreshLaunchAtLoginState()
    }

    // MARK: - Conversation configuration

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resolvedLanguageCode: String { appLanguage.resolvedCode }

    func reasoningLevels(for model: DeepSeekModel) -> [String] {
        ["none"] + model.supportedReasoningLevels
    }

    func selectModel(_ model: DeepSeekModel) {
        selectedModelID = model.id
        let levels = reasoningLevels(for: model)
        if !levels.contains(reasoningEffort) {
            reasoningEffort = model.defaultReasoningLevel
        }
    }

    func selectReasoningLevel(_ level: String, model: DeepSeekModel) {
        guard reasoningLevels(for: model).contains(level) else { return }
        reasoningEffort = level
    }

    func reconcile(with models: [DeepSeekModel]) {
        guard !models.isEmpty else { return }
        if !models.contains(where: { $0.id == selectedModelID }) {
            if let preferred = models.first(where: { $0.id == "deepseek-flash" }) ?? models.first {
                selectedModelID = preferred.id
            }
        }
        guard let current = models.first(where: { $0.id == selectedModelID }) else { return }
        if !reasoningLevels(for: current).contains(reasoningEffort) {
            reasoningEffort = current.defaultReasoningLevel
        }
    }

    // MARK: - Shortcut

    @discardableResult
    func applyShortcut(_ newShortcut: AppShortcut) -> Bool {
        guard let hotKeyRegistrationHandler else {
            shortcutError = L10n.string("快捷键服务尚未就绪。")
            return false
        }
        if let error = hotKeyRegistrationHandler(newShortcut) {
            shortcutError = error
            return false
        }
        shortcut = newShortcut
        shortcutError = nil
        return true
    }

    func reportShortcutError(_ message: String) {
        shortcutError = message
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        guard Bundle.main.bundleIdentifier != nil else {
            launchAtLoginError = L10n.string("从源码运行时无法注册登录项，请先打包为 .app。")
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginState()
            if enabled, SMAppService.mainApp.status == .requiresApproval {
                launchAtLoginError = L10n.string("已添加登录项，但需要在系统设置的「通用 → 登录项」中允许。")
            }
        } catch {
            launchAtLoginError = L10n.format("无法更新登录项：%@", error.localizedDescription)
            refreshLaunchAtLoginState()
        }
    }

    private func refreshLaunchAtLoginState() {
        guard Bundle.main.bundleIdentifier != nil else {
            launchAtLogin = false
            return
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLogin = true
        default:
            launchAtLogin = false
        }
    }

    // MARK: - API key persistence

    private func scheduleKeySave() {
        apiKeyNeedsSave = true
        keySaveTask?.cancel()
        keySaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.flushAPIKey()
        }
    }

    func flushAPIKey() {
        keySaveTask?.cancel()
        keySaveTask = nil
        guard apiKeyNeedsSave else { return }
        do {
            try credentialStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            credentialError = nil
            apiKeyNeedsSave = false
        } catch {
            credentialError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Lifecycle

    func markLaunched(version: String) {
        defaults.set(true, forKey: Key.hasLaunched)
        defaults.set(version, forKey: Key.lastLaunchedVersion)
    }

    var hasLaunchedBefore: Bool {
        defaults.bool(forKey: Key.hasLaunched)
    }

    var lastLaunchedVersion: String? {
        defaults.string(forKey: Key.lastLaunchedVersion)
    }
}
