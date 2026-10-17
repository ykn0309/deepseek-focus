import Foundation
import Combine
import DeepSeekFocusCore

enum ConnectionState: Equatable {
    case notConfigured
    case unverified
    case checking
    case connected
    case failed

    var titleKey: String {
        switch self {
        case .notConfigured: return "待配置"
        case .unverified: return "待验证"
        case .checking: return "验证中"
        case .connected: return "已连接"
        case .failed: return "连接失败"
        }
    }
}

@MainActor
final class ModelCatalog: ObservableObject {
    @Published private(set) var models: [DeepSeekModel]
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var connectionState: ConnectionState
    @Published private(set) var connectionMessage: String?

    private let settings: AppSettings
    private let defaults: UserDefaults
    private var apiKeyObserver: AnyCancellable?
    private static let cacheKey = "deepseek.modelCatalog"
    private static let cacheDateKey = "deepseek.modelCatalogDate"
    private static let verifiedKey = "deepseek.keyVerified"

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults

        var cached: [DeepSeekModel] = []
        if let data = defaults.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode([DeepSeekModel].self, from: data),
           !decoded.isEmpty {
            cached = decoded
        }
        self.models = cached.isEmpty ? DeepSeekModel.fallbackModels : cached
        if let date = defaults.object(forKey: Self.cacheDateKey) as? Date {
            self.lastUpdated = date
        }
        let verified = defaults.bool(forKey: Self.verifiedKey)
        if settings.hasAPIKey {
            self.connectionState = verified ? .connected : .unverified
        } else {
            self.connectionState = .notConfigured
        }
        settings.reconcile(with: self.models)

        apiKeyObserver = settings.$apiKey
            .dropFirst()
            .sink { [weak self] _ in
                self?.invalidateConnection()
            }
    }

    func invalidateConnection() {
        guard !isLoading else { return }
        error = nil
        connectionMessage = nil
        defaults.set(false, forKey: Self.verifiedKey)
        connectionState = settings.hasAPIKey ? .unverified : .notConfigured
    }

    var selectedModel: DeepSeekModel {
        models.first(where: { $0.id == settings.selectedModelID })
            ?? DeepSeekModel.fallbackModel(id: settings.selectedModelID)
            ?? DeepSeekModel.fallbackModels[0]
    }

    var statusText: String {
        if isLoading { return L10n.string("正在从 DeepSeek 获取模型列表…") }
        if let error { return error }
        if let lastUpdated {
            return L10n.format(
                "已同步 %ld 个模型 · %@",
                models.count,
                Self.relativeString(for: lastUpdated)
            )
        }
        return L10n.string("使用内置的模型信息")
    }

    func refreshIfStale(apiKey: String? = nil) async {
        let key = (apiKey ?? settings.apiKey).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < 3_600, error == nil,
           connectionState != .unverified {
            return
        }
        await refresh(apiKey: key)
    }

    func refresh(apiKey: String? = nil) async {
        guard !isLoading else { return }
        let key = (apiKey ?? settings.apiKey).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            connectionState = .notConfigured
            connectionMessage = nil
            error = L10n.string("请先填写 DeepSeek API Key。")
            defaults.set(false, forKey: Self.verifiedKey)
            return
        }

        isLoading = true
        connectionState = .checking
        connectionMessage = nil
        error = nil
        defer { isLoading = false }

        do {
            let client = DeepSeekClient(baseURL: settings.baseURL)
            let fetched = try await client.fetchModels(apiKey: key)
            models = fetched
            lastUpdated = Date()
            settings.reconcile(with: fetched)
            persistCache(fetched)
            connectionState = .connected
            connectionMessage = L10n.format("API Key 验证成功，已同步 %ld 个模型。", fetched.count)
            defaults.set(true, forKey: Self.verifiedKey)
        } catch let error as DeepSeekError {
            connectionState = .failed
            connectionMessage = nil
            self.error = error.errorDescription
            defaults.set(false, forKey: Self.verifiedKey)
        } catch {
            connectionState = .failed
            connectionMessage = nil
            self.error = L10n.format("获取模型列表失败：%@", error.localizedDescription)
            defaults.set(false, forKey: Self.verifiedKey)
        }
    }

    private func persistCache(_ models: [DeepSeekModel]) {
        guard let data = try? JSONEncoder().encode(models) else { return }
        defaults.set(data, forKey: Self.cacheKey)
        defaults.set(Date(), forKey: Self.cacheDateKey)
    }

    private static func relativeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: L10n.languageCode)
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
