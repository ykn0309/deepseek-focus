import AppKit
import Foundation

/// Installs written before v1.8.19 used the Chinese bundle name. Auto-update
/// still replaces the old path, so on first launch the new build moves itself
/// to `DeepSeek Focus.app` and relaunches once.
@MainActor
enum AppBundleMigrator {
    private static let legacyName = "DeepSeek 聚焦.app"
    private static let modernName = "DeepSeek Focus.app"

    /// Returns true when a migration helper has been launched and the app is
    /// about to terminate.
    static func migrateIfNeeded() -> Bool {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let parent = bundleURL.deletingLastPathComponent().standardizedFileURL
        guard bundleURL.lastPathComponent == legacyName,
              parent.path == "/Applications" else { return false }

        let target = parent.appendingPathComponent(modernName)
        guard !FileManager.default.fileExists(atPath: target.path),
              FileManager.default.isWritableFile(atPath: parent.path) else { return false }

        let support: URL
        do {
            support = try updatesDirectory()
        } catch {
            return false
        }
        let marker = support.appendingPathComponent("rename-to-english-name-attempted")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return false }
        do {
            try Data().write(to: marker, options: .atomic)
        } catch {
            return false
        }

        let script = support.appendingPathComponent("rename-bundle.sh")
        let log = support.appendingPathComponent("rename.log")
        let content = """
        #!/bin/bash
        set -u
        PID="$1"
        OLD="$2"
        NEW="$3"
        LOG="$4"
        exec >>"$LOG" 2>&1
        echo "=== bundle rename $(date) ==="
        while /bin/kill -0 "$PID" 2>/dev/null; do /bin/sleep 0.2; done
        if [ -e "$NEW" ]; then
          echo "target already exists"
          /usr/bin/open "$OLD" 2>/dev/null || true
          exit 0
        fi
        if /bin/mv "$OLD" "$NEW"; then
          /usr/bin/xattr -dr com.apple.quarantine "$NEW" 2>/dev/null || true
          echo "renamed to $NEW"
          /bin/sleep 1
          /usr/bin/open "$NEW"
        else
          echo "rename failed"
          /usr/bin/open "$OLD" 2>/dev/null || true
          exit 1
        fi
        """

        do {
            try content.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: script.path
            )
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            process.arguments = [
                "/bin/bash",
                script.path,
                "\(ProcessInfo.processInfo.processIdentifier)",
                bundleURL.path,
                target.path,
                log.path
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: marker)
            return false
        }

        NSApplication.shared.terminate(nil)
        return true
    }

    private static func updatesDirectory() throws -> URL {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = base
            .appendingPathComponent("DeepSeekFocus", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }
}
