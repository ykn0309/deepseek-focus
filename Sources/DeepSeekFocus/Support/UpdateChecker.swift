import Combine
import Foundation
import DeepSeekFocusCore

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, releaseURL: URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }

    func check() async {
        guard !isChecking else { return }
        state = .checking

        guard let url = URL(string: "https://api.github.com/repos/ykn0309/deepseek-focus/releases/latest") else {
            state = .failed(L10n.string("检查更新失败：无效的更新地址。"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DeepSeekFocus/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 20

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)

        do {
            let (data, response) = try await session.data(for: request)
            guard let HTTPResponse = response as? HTTPURLResponse else {
                state = .failed(L10n.string("检查更新失败：服务器没有返回有效响应。"))
                return
            }

            switch HTTPResponse.statusCode {
            case 200..<300:
                break
            case 404:
                state = .failed(L10n.string("尚未发布可用的 Release。"))
                return
            case 403:
                state = .failed(L10n.string("GitHub API 请求过于频繁，请稍后再试。"))
                return
            default:
                state = .failed(L10n.format("检查更新失败：HTTP %ld", HTTPResponse.statusCode))
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            var version = release.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            if version.first == "v" || version.first == "V" {
                version.removeFirst()
            }
            guard !version.isEmpty,
                  release.htmlURL.scheme == "https",
                  release.htmlURL.host == "github.com" else {
                state = .failed(L10n.string("GitHub Releases 返回了无法解析的数据。"))
                return
            }

            if VersionCompare.isNewer(version, than: currentVersion) {
                state = .available(version: version, releaseURL: release.htmlURL)
            } else {
                state = .upToDate
            }
        } catch is DecodingError {
            state = .failed(L10n.string("GitHub Releases 返回了无法解析的数据。"))
        } catch {
            state = .failed(L10n.format("检查更新失败：%@", error.localizedDescription))
        }
    }
}
