import AppKit
import Combine
import CryptoKit
import Foundation
import DeepSeekFocusCore

struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, releaseURL: URL)
        case downloading(version: String)
        case installing(version: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var releasePageURL: URL?

    private struct AvailableUpdate {
        let version: String
        let releaseURL: URL
        let zipURL: URL
        let checksumURL: URL?
    }

    private var availableUpdate: AvailableUpdate?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    private init() {}

    func check() async {
        guard !isBusy else { return }
        state = .checking
        releasePageURL = nil
        availableUpdate = nil

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

            releasePageURL = release.htmlURL

            guard let zipAsset = release.assets.first(where: {
                $0.name.lowercased().hasSuffix(".zip") &&
                $0.browserDownloadURL.scheme == "https" &&
                $0.browserDownloadURL.host == "github.com"
            }) else {
                state = .failed(L10n.string("Release 中没有可用的自动更新包。"))
                return
            }

            let checksumAsset = release.assets.first(where: {
                $0.name.lowercased().hasSuffix(".sha256") &&
                $0.browserDownloadURL.scheme == "https" &&
                $0.browserDownloadURL.host == "github.com"
            })

            if VersionCompare.isNewer(version, than: currentVersion) {
                availableUpdate = AvailableUpdate(
                    version: version,
                    releaseURL: release.htmlURL,
                    zipURL: zipAsset.browserDownloadURL,
                    checksumURL: checksumAsset?.browserDownloadURL
                )
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

    /// Downloads the latest ZIP, verifies its SHA-256 checksum and code
    /// signature, stages the app, then hands installation to a detached helper
    /// that waits for this process to exit before replacing the bundle.
    func downloadAndInstall() async {
        guard case .available = state, let update = availableUpdate else { return }
        _ = update.releaseURL

        state = .downloading(version: update.version)
        var downloadedZip: URL?
        var workDirectory: URL?

        do {
            let zipURL = try await downloadFile(update.zipURL)
            downloadedZip = zipURL
            try await verifyChecksum(of: zipURL, update: update)

            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("DeepSeekFocusUpdate-\(UUID().uuidString)", isDirectory: true)
            workDirectory = work
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, work.path])

            let contents = try FileManager.default.contentsOfDirectory(
                at: work,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            guard let appURL = contents.first(where: { $0.pathExtension.lowercased() == "app" }) else {
                throw UpdateInstallError(L10n.string("更新包中没有找到应用。"))
            }

            let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
            guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
                  let bundleIdentifier = info["CFBundleIdentifier"] as? String,
                  let bundleVersion = info["CFBundleShortVersionString"] as? String else {
                throw UpdateInstallError(L10n.string("更新包中的应用标识不匹配。"))
            }
            guard bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UpdateInstallError(L10n.string("更新包中的应用标识不匹配。"))
            }
            guard bundleVersion == update.version else {
                throw UpdateInstallError(L10n.string("更新包中的应用版本与 Release 不一致。"))
            }

            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])

            let stagedApp = try stage(appURL: appURL, version: update.version)
            let targetApp = Bundle.main.bundleURL.standardizedFileURL

            guard targetApp.path.hasPrefix("/Applications/") else {
                throw UpdateInstallError(L10n.string("请把应用放在 /Applications 后再自动更新。"))
            }
            guard FileManager.default.isWritableFile(atPath: targetApp.deletingLastPathComponent().path) else {
                throw UpdateInstallError(L10n.string("应用所在目录不可写，无法自动安装。"))
            }

            state = .installing(version: update.version)
            try launchInstaller(stagedApp: stagedApp, targetApp: targetApp, logVersion: update.version)

            // Give SwiftUI a moment to render the installing state before the
            // helper starts waiting for this process to exit.
            try? await Task.sleep(nanoseconds: 250_000_000)
            NSApplication.shared.terminate(nil)
        } catch {
            state = .failed(L10n.format("下载或安装更新失败：%@", error.localizedDescription))
        }

        if let downloadedZip {
            try? FileManager.default.removeItem(at: downloadedZip)
        }
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }

    private func downloadFile(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("DeepSeekFocus/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let HTTPResponse = response as? HTTPURLResponse,
              (200..<300).contains(HTTPResponse.statusCode) else {
            throw UpdateInstallError(L10n.string("下载更新失败。"))
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepSeekFocus-\(UUID().uuidString).zip")
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func verifyChecksum(of zipURL: URL, update: AvailableUpdate) async throws {
        guard let checksumURL = update.checksumURL else {
            throw UpdateInstallError(L10n.string("更新包缺少 SHA-256 校验文件，已取消安装。"))
        }
        let (data, response) = try await URLSession.shared.data(from: checksumURL)
        guard let HTTPResponse = response as? HTTPURLResponse,
              (200..<300).contains(HTTPResponse.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            throw UpdateInstallError(L10n.string("无法下载更新校验文件，已取消安装。"))
        }
        guard let expected = checksum(in: text, for: update.zipURL.lastPathComponent) else {
            throw UpdateInstallError(L10n.string("更新包校验文件格式不正确，已取消安装。"))
        }
        let actual = try sha256(of: zipURL)
        guard actual.lowercased() == expected.lowercased() else {
            throw UpdateInstallError(L10n.string("更新包校验失败，已取消安装。"))
        }
    }

    private func checksum(in text: String, for filename: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2 else { continue }
            var name = String(fields[1])
            if name.hasPrefix("*") { name.removeFirst() }
            if name == filename {
                return String(fields[0])
            }
        }
        return nil
    }

    private func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func stage(appURL: URL, version: String) throws -> URL {
        let support = try updatesDirectory()
        let stageDirectory = support
            .appendingPathComponent("staged-\(version)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stageDirectory, withIntermediateDirectories: true)
        let stagedApp = stageDirectory.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
        try run("/usr/bin/ditto", [appURL.path, stagedApp.path])
        return stagedApp
    }

    private func updatesDirectory() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw UpdateInstallError(L10n.string("无法找到应用数据目录。"))
        }
        let directory = applicationSupport
            .appendingPathComponent("DeepSeekFocus", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    private func launchInstaller(stagedApp: URL, targetApp: URL, logVersion: String) throws {
        let support = try updatesDirectory()
        let scriptURL = support.appendingPathComponent("install-\(logVersion).sh")
        let logURL = support.appendingPathComponent("install.log")

        let script = """
        #!/bin/bash
        set -u
        PID="$1"
        NEW="$2"
        TARGET="$3"
        LOG="$4"
        exec >>"$LOG" 2>&1
        echo "=== DeepSeek Focus update $(date) ==="
        while /bin/kill -0 "$PID" 2>/dev/null; do /bin/sleep 0.2; done
        BACKUP="${TARGET}.backup-$(date +%s)"
        if ! /bin/mv "$TARGET" "$BACKUP"; then
          echo "move failed"
          /usr/bin/open "$TARGET" 2>/dev/null || true
          exit 1
        fi
        if /usr/bin/ditto "$NEW" "$TARGET"; then
          /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
          /bin/rm -rf "$BACKUP"
          /bin/rm -rf "$(dirname "$NEW")"
          echo "installed"
          /usr/bin/open "$TARGET"
        else
          echo "copy failed; restoring"
          /bin/rm -rf "$TARGET"
          /bin/mv "$BACKUP" "$TARGET"
          /usr/bin/open "$TARGET"
          exit 1
        fi
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = [
            "/bin/bash",
            scriptURL.path,
            "\(ProcessInfo.processInfo.processIdentifier)",
            stagedApp.path,
            targetApp.path,
            logURL.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateInstallError(L10n.string("无法启动更新安装器。"))
        }
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw UpdateInstallError(L10n.format("无法执行 %@。", executable))
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateInstallError(
                detail?.isEmpty == false ? detail! : L10n.string("安装更新时执行命令失败。")
            )
        }
    }
}

private struct UpdateInstallError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
