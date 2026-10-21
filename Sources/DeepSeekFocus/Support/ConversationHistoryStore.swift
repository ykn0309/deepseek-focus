import Foundation
import Combine
import DeepSeekFocusCore

struct ConversationSession: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var turns: [ConversationTurn]
    var apiMessages: [APIMessage]
    var modelID: String
    var reasoningEffort: String
    var webSearchMode: String? = nil
    var autoTitleGenerated: Bool? = nil
    var languageCode: String? = nil

    var turnCount: Int { turns.count }
}

@MainActor
final class ConversationHistoryStore: ObservableObject {
    @Published private(set) var sessions: [ConversationSession] = []
    @Published private(set) var recoveryMessage: String?

    private let fileURL: URL
    private let backupURL: URL
    private let maxSessions: Int

    init(fileURL: URL? = nil, maxSessions: Int = 50) {
        self.maxSessions = maxSessions
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = base
                .appendingPathComponent("DeepSeekFocus", isDirectory: true)
                .appendingPathComponent("history.json", isDirectory: false)
        }
        self.backupURL = self.fileURL.deletingLastPathComponent()
            .appendingPathComponent("history.backup.json", isDirectory: false)
        load()
    }

    func upsert(_ session: ConversationSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            // Saving the same session should not move it in the sidebar. Only
            // re-sort when its last-activity date actually changed.
            let needsResort = sessions[index].updatedAt != session.updatedAt
            sessions[index] = session
            if needsResort {
                sortSessions()
            }
        } else {
            sessions.append(session)
            sortSessions()
            if sessions.count > maxSessions {
                sessions.removeLast(sessions.count - maxSessions)
            }
        }
        persist()
    }

    private func sortSessions() {
        sessions.sort { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func updateTitle(id: UUID, title: String, generated: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].title = title
        sessions[index].autoTitleGenerated = generated
        persist()
    }

    func updateConfiguration(
        id: UUID,
        modelID: String,
        reasoningEffort: String,
        webSearchMode: WebSearchMode
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].modelID = modelID
        sessions[index].reasoningEffort = reasoningEffort
        sessions[index].webSearchMode = webSearchMode.rawValue
        persist()
    }

    func delete(id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        sessions = []
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([ConversationSession].self, from: data) {
            sessions = decoded
            sortSessions()
            return
        }

        // Keep a copy of the damaged file and try the last known-good backup.
        let stamp = Int(Date().timeIntervalSince1970)
        let corruptURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("history.corrupt-\(stamp).json", isDirectory: false)
        try? FileManager.default.copyItem(at: fileURL, to: corruptURL)

        if let backupData = try? Data(contentsOf: backupURL),
           let decoded = try? JSONDecoder().decode([ConversationSession].self, from: backupData) {
            sessions = decoded
            sortSessions()
            recoveryMessage = L10n.string("历史记录文件损坏，已从备份恢复会话。")
        } else {
            sessions = []
            recoveryMessage = L10n.string("历史记录文件损坏，已保留损坏文件，但无法恢复会话。")
        }
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            if let existing = try? Data(contentsOf: fileURL),
               (try? JSONDecoder().decode([ConversationSession].self, from: existing)) != nil {
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            }

            let data = try JSONEncoder().encode(sessions)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            // History persistence is best-effort; a failed write should never block chatting.
        }
    }
}
