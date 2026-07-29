//
// PendingSubmissionStore.swift
// Local queue for failed submissions with automatic retry
//

import Foundation
import CryptoKit
import Security

struct PendingSubmission: Codable {
    let id: UUID
    let formId: String
    let userId: String?
    var conversation: [ConversationMessage]
    let metadataJSON: Data?  // Store [String: Any] as JSON Data
    let createdAt: Date
    var updatedAt: Date
    var status: String
    var snapshotVersion: Int
    var retryCount: Int

    // Convenience to decode metadata back to [String: Any]
    var metadata: [String: Any]? {
        guard let data = metadataJSON else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    init(
        id: UUID = UUID(),
        formId: String,
        userId: String?,
        conversation: [ConversationMessage],
        metadata: [String: Any]?,
        status: String = "in_progress",
        snapshotVersion: Int = 0
    ) {
        self.id = id
        self.formId = formId
        self.userId = userId
        self.conversation = conversation
        self.metadataJSON = metadata.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        self.createdAt = Date()
        self.updatedAt = Date()
        self.status = status
        self.snapshotVersion = snapshotVersion
        self.retryCount = 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, formId, userId, conversation, metadataJSON, createdAt, updatedAt, status, snapshotVersion, retryCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        formId = try values.decode(String.self, forKey: .formId)
        userId = try values.decodeIfPresent(String.self, forKey: .userId)
        conversation = try values.decode([ConversationMessage].self, forKey: .conversation)
        metadataJSON = try values.decodeIfPresent(Data.self, forKey: .metadataJSON)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? "completed"
        snapshotVersion = try values.decodeIfPresent(Int.self, forKey: .snapshotVersion) ?? 0
        retryCount = try values.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
    }
}

class PendingSubmissionStore {
    static let shared = PendingSubmissionStore()
    private let legacyDefaultsKey = "paydirt_pending_submissions"
    private let encryptionKeyAccount = "pending-submissions-encryption-key"
    private let queue = DispatchQueue(label: "ai.paydirt.pending")

    private init() {
        migrateLegacyQueueIfNeeded()
    }

    func save(_ submission: PendingSubmission) {
        let saved = queue.sync {
            guard var pending = loadInternal() else {
                return false
            }
            pending.removeAll { $0.id == submission.id }
            pending.append(submission)
            return persist(pending)
        }
        if saved {
            PaydirtLogger.shared.info("Queue", "Saved submission for retry: \(submission.id)")
        } else {
            PaydirtLogger.shared.error("Queue", "Could not persist submission for retry")
        }
    }

    func remove(id: UUID) {
        queue.sync {
            guard var pending = loadInternal() else {
                return
            }
            pending.removeAll { $0.id == id }
            _ = persist(pending)
        }
    }

    private func loadInternal() -> [PendingSubmission]? {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return []
        }

        guard let encryptedData = try? Data(contentsOf: storageURL),
              let key = loadOrCreateEncryptionKey(),
              let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData),
              let data = try? AES.GCM.open(sealedBox, using: key),
              let submissions = try? JSONDecoder().decode([PendingSubmission].self, from: data)
        else {
            PaydirtLogger.shared.error("Queue", "Could not decrypt pending submissions; encrypted data was preserved")
            return nil
        }
        return submissions
    }

    func load() -> [PendingSubmission] {
        queue.sync { loadInternal() ?? [] }
    }

    @discardableResult
    private func persist(_ submissions: [PendingSubmission]) -> Bool {
        do {
            if submissions.isEmpty {
                try? FileManager.default.removeItem(at: storageURL)
                return true
            }

            try FileManager.default.createDirectory(
                at: storageDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )

            guard let key = loadOrCreateEncryptionKey() else {
                return false
            }

            let data = try JSONEncoder().encode(submissions)
            let sealed = try AES.GCM.seal(data, using: key)
            guard let encryptedData = sealed.combined else {
                return false
            }
            try encryptedData.write(
                to: storageURL,
                options: [.atomic, .completeFileProtectionUnlessOpen]
            )
            return true
        } catch {
            PaydirtLogger.shared.error("Queue", "Encrypted queue write failed: \(error.localizedDescription)")
            return false
        }
    }

    private var storageDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Paydirt", isDirectory: true)
    }

    private var storageURL: URL {
        storageDirectoryURL.appendingPathComponent("pending-submissions.dat")
    }

    private func migrateLegacyQueueIfNeeded() {
        queue.sync {
            guard let legacyData = UserDefaults.standard.data(forKey: legacyDefaultsKey),
                  let submissions = try? JSONDecoder().decode([PendingSubmission].self, from: legacyData)
            else {
                return
            }

            if persist(submissions) {
                UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
                PaydirtLogger.shared.info("Queue", "Migrated pending submissions to encrypted storage")
            }
        }
    }

    private func loadOrCreateEncryptionKey() -> SymmetricKey? {
        if let storedKey = loadEncryptionKey() {
            return SymmetricKey(data: storedKey)
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.paydirt.sdk",
            kSecAttrAccount as String: encryptionKeyAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: keyData,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            return SymmetricKey(data: keyData)
        }

        if status == errSecDuplicateItem, let storedKey = loadEncryptionKey() {
            return SymmetricKey(data: storedKey)
        }

        PaydirtLogger.shared.error("Queue", "Could not create encryption key (status \(status))")
        return nil
    }

    private func loadEncryptionKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.paydirt.sdk",
            kSecAttrAccount as String: encryptionKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    func retryPending(using apiClient: PaydirtAPIClient) async {
        let pending = load()
        guard !pending.isEmpty else { return }

        PaydirtLogger.shared.info("Queue", "Retrying \(pending.count) pending submissions")

        for var submission in pending {
            if submission.status == "in_progress" {
                let hasAnswer = submission.conversation.contains {
                    $0.role == "user" && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                if !hasAnswer {
                    remove(id: submission.id)
                    continue
                }
                // A live draft left behind across an app launch is a finished
                // session. Finalize the one durable snapshot and deliver once.
                submission.status = "completed"
                submission.snapshotVersion += 1
                submission.updatedAt = Date()
                save(submission)
            }

            do {
                try await apiClient.submitResponse(
                    submissionId: submission.id,
                    formId: submission.formId,
                    userId: submission.userId,
                    conversation: submission.conversation,
                    metadata: submission.metadata,
                    status: submission.status,
                    snapshotVersion: submission.snapshotVersion
                )
                if submission.status == "completed" || submission.status == "abandoned" {
                    remove(id: submission.id)
                }
                PaydirtLogger.shared.info("Queue", "Retry succeeded: \(submission.id)")
            } catch {
                submission.retryCount += 1
                remove(id: submission.id)
                save(submission)
                PaydirtLogger.shared.warning(
                    "Queue",
                    "Retry \(submission.retryCount) failed; encrypted submission remains queued: \(submission.id)"
                )
            }
        }
    }
}
