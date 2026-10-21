import Foundation
import Security
import DeepSeekFocusCore

/// Stores the API key in the macOS Keychain. Existing installations are
/// migrated from the legacy Application Support file on first read.
struct APIKeyStore {
    let fileURL: URL

    private let useKeychain: Bool
    private let service = "com.kainan.deepseekfocus"
    private let account = "deepseek-api-key"

    init(fileURL: URL? = nil) {
        self.useKeychain = fileURL == nil
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = base
                .appendingPathComponent("DeepSeekFocus", isDirectory: true)
                .appendingPathComponent("credentials.json", isDirectory: false)
        }
    }

    func read() throws -> String? {
        if useKeychain {
            if let value = (try? keychainRead()) ?? nil {
                return value
            }
            // Keep using a legacy file without prompting for Keychain access
            // at launch. New or edited keys are written to the Keychain.
            return try readLegacyFile()
            return nil
        }
        return try readLegacyFile()
    }

    func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete()
            return
        }

        if useKeychain {
            do {
                try keychainSave(trimmed)
                try? deleteLegacyFile()
                return
            } catch {
                // Keychain can be unavailable in unsigned/development builds.
                // Fall back to the legacy 0600 file so the app remains usable.
                try saveLegacyFile(trimmed)
                return
            }
        }
        try saveLegacyFile(trimmed)
    }

    func delete() throws {
        if useKeychain {
            keychainDelete()
        }
        try? deleteLegacyFile()
    }

    // MARK: - Keychain

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func keychainRead() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw APIKeyStoreError.keychain(status)
        }
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func keychainSave(_ value: String) throws {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStoreError.keychain(updateStatus)
        }

        var addQuery = baseQuery
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError.keychain(addStatus)
        }
    }

    private func keychainDelete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    // MARK: - Legacy file

    private func readLegacyFile() throws -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let stored = object["apiKey"] as? String {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private func saveLegacyFile(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let data = try JSONSerialization.data(
            withJSONObject: ["apiKey": trimmed],
            options: [.prettyPrinted, .sortedKeys]
        )

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try data.write(to: fileURL, options: [])
        } else {
            let created = FileManager.default.createFile(
                atPath: fileURL.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            )
            guard created else {
                throw APIKeyStoreError.writeFailed
            }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func deleteLegacyFile() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

enum APIKeyStoreError: LocalizedError {
    case writeFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .writeFailed:
            return L10n.string("无法写入本机 API Key 文件。")
        case .keychain(let status):
            return L10n.format("无法访问钥匙串（%ld）。", status)
        }
    }
}
