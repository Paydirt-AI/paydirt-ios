//
// PendingSubmissionStore.swift
// Local queue for failed submissions with automatic retry
//

import Foundation

struct PendingSubmission: Codable {
    let id: UUID
    let formId: String
    let userId: String?
    let conversation: [ConversationMessage]
    let metadataJSON: Data?  // Store [String: Any] as JSON Data
    let createdAt: Date
    var retryCount: Int

    // Convenience to decode metadata back to [String: Any]
    var metadata: [String: Any]? {
        guard let data = metadataJSON else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    init(formId: String, userId: String?, conversation: [ConversationMessage], metadata: [String: Any]?) {
        self.id = UUID()
        self.formId = formId
        self.userId = userId
        self.conversation = conversation
        self.metadataJSON = metadata.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        self.createdAt = Date()
        self.retryCount = 0
    }
}

class PendingSubmissionStore {
    static let shared = PendingSubmissionStore()
    private let key = "paydirt_pending_submissions"
    private let maxRetries = 3
    private let queue = DispatchQueue(label: "ai.paydirt.pending")

    private init() {}

    func save(_ submission: PendingSubmission) {
        queue.sync {
            var pending = loadInternal()
            pending.append(submission)
            persist(pending)
        }
        PaydirtLogger.shared.info("Queue", "Saved submission for retry: \(submission.id)")
    }

    func remove(id: UUID) {
        queue.sync {
            var pending = loadInternal()
            pending.removeAll { $0.id == id }
            persist(pending)
        }
    }

    private func loadInternal() -> [PendingSubmission] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let submissions = try? JSONDecoder().decode([PendingSubmission].self, from: data)
        else { return [] }
        return submissions
    }

    func load() -> [PendingSubmission] {
        queue.sync { loadInternal() }
    }

    private func persist(_ submissions: [PendingSubmission]) {
        if let data = try? JSONEncoder().encode(submissions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func retryPending(using apiClient: PaydirtAPIClient) async {
        let pending = load()
        guard !pending.isEmpty else { return }

        PaydirtLogger.shared.info("Queue", "Retrying \(pending.count) pending submissions")

        for var submission in pending where submission.retryCount < maxRetries {
            do {
                try await apiClient.submitResponse(
                    formId: submission.formId,
                    userId: submission.userId,
                    conversation: submission.conversation,
                    metadata: submission.metadata
                )
                remove(id: submission.id)
                PaydirtLogger.shared.info("Queue", "Retry succeeded: \(submission.id)")
            } catch {
                submission.retryCount += 1
                remove(id: submission.id)
                if submission.retryCount < maxRetries {
                    save(submission)
                    PaydirtLogger.shared.info("Queue", "Retry failed, will retry later: \(submission.id)")
                } else {
                    PaydirtLogger.shared.error("Queue", "Max retries reached, dropping: \(submission.id)")
                }
            }
        }
    }
}
