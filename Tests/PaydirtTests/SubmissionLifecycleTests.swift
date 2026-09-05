import XCTest
@testable import Paydirt

private final class MemoryQueue {
    var records: [PendingSubmission] = []
    var failWrites = false
    lazy var store = PendingSubmissionStore(read: { self.records }, write: {
        guard !self.failWrites else { return false }
        self.records = $0
        return true
    })
}

private actor StubClient: PaydirtConversationClient {
    var transcriptionFailures = 0
    var followUpFailures = 0
    var transcriptionCalls = 0
    var followUpCalls = 0
    var statuses: [String] = []
    var submissionSucceeds = false
    var delayedTranscription: CheckedContinuation<String, Never>?
    var holdTranscription = false

    func configure(transcriptionFailures: Int = 0, followUpFailures: Int = 0, holdTranscription: Bool = false) {
        self.transcriptionFailures = transcriptionFailures
        self.followUpFailures = followUpFailures
        self.holdTranscription = holdTranscription
    }
    func sendMessage(formId: String, message: String, conversationHistory: [ConversationMessage], previousResponseId: String?, appContext: String?) async throws -> FollowUpResponse {
        followUpCalls += 1
        if followUpFailures > 0 { followUpFailures -= 1; throw URLError(.notConnectedToInternet) }
        return FollowUpResponse(follow_up_question: "Anything else?", is_complete: false, response_id: "follow-up")
    }
    func submitResponse(submissionId: UUID, formId: String, userId: String?, conversation: [ConversationMessage], metadata: [String: Any]?, status: String, snapshotVersion: Int) async throws {
        statuses.append(status)
        if !submissionSucceeds { throw URLError(.notConnectedToInternet) }
    }
    func transcribeAudio(audioData: Data) async throws -> String {
        transcriptionCalls += 1
        if transcriptionFailures > 0 { transcriptionFailures -= 1; throw URLError(.notConnectedToInternet) }
        if holdTranscription { return await withCheckedContinuation { delayedTranscription = $0 } }
        return "Please add calendar sync."
    }
    func releaseTranscription() { delayedTranscription?.resume(returning: "A late answer"); delayedTranscription = nil }
}

final class SubmissionLifecycleTests: XCTestCase {
    private func snapshot(id: UUID = UUID(), version: Int, status: String = "in_progress") -> PendingSubmission {
        PendingSubmission(id: id, formId: "form", userId: nil,
                          conversation: [ConversationMessage(role: "user", content: "Answer", input_type: "text")],
                          metadata: nil, status: status, snapshotVersion: version)
    }

    func testStaleAcknowledgmentAndRetryPreserveNewestSnapshot() {
        let memory = MemoryQueue()
        let id = UUID()
        XCTAssertTrue(memory.store.save(snapshot(id: id, version: 1)))
        XCTAssertTrue(memory.store.save(snapshot(id: id, version: 2, status: "completed")))
        XCTAssertTrue(memory.store.remove(id: id, snapshotVersion: 1))
        XCTAssertEqual(memory.store.load().first?.snapshotVersion, 2)
        XCTAssertFalse(memory.store.save(snapshot(id: id, version: 1)))
        XCTAssertEqual(memory.store.load().first?.status, "completed")
        XCTAssertTrue(memory.store.remove(id: id, snapshotVersion: 2))
        XCTAssertFalse(memory.store.save(snapshot(id: id, version: 2, status: "completed")))
        XCTAssertTrue(memory.store.load().isEmpty)
    }

    func testTerminalSnapshotRejectsLaterDraftAndDifferentTranscript() {
        let memory = MemoryQueue()
        let id = UUID()
        XCTAssertTrue(memory.store.save(snapshot(id: id, version: 2, status: "completed")))
        XCTAssertFalse(memory.store.save(snapshot(id: id, version: 3)))
        var conflict = snapshot(id: id, version: 2, status: "completed")
        conflict.conversation = [ConversationMessage(role: "user", content: "Different", input_type: "text")]
        XCTAssertFalse(memory.store.save(conflict))
    }

    func testPersistenceFailureDoesNotAcknowledgeRemoval() {
        let memory = MemoryQueue()
        let submission = snapshot(version: 1, status: "completed")
        XCTAssertTrue(memory.store.save(submission))
        memory.failWrites = true
        XCTAssertFalse(memory.store.remove(id: submission.id, snapshotVersion: 1))
        XCTAssertEqual(memory.store.load().count, 1)
        memory.failWrites = false
        XCTAssertTrue(memory.store.save(submission))
    }

    func testRelaunchNeverCompletesDraft() async {
        let memory = MemoryQueue()
        XCTAssertTrue(memory.store.save(snapshot(version: 3)))
        let client = StubClient()
        await memory.store.retryPending(using: client)
        let statuses = await client.statuses
        XCTAssertEqual(statuses, [])
        XCTAssertEqual(memory.store.load().first?.status, "in_progress")
    }

    @MainActor
    private func model(_ memory: MemoryQueue, _ client: StubClient, submitted: ((PaydirtSubmissionResult) -> Void)? = nil) -> PaydirtFormViewModel {
        PaydirtFormViewModel(form: PaydirtForm(id: "form", name: "Test", type: "cancellation", prompt: "Why?", enabled: true), userId: nil, metadata: nil, apiClient: client, submissionStore: memory.store, onSubmission: submitted)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for lifecycle transition")
    }

    @MainActor
    func testExplicitFinishPersistsOnceAndAbandonDoesNotPromoteEditorDraft() async {
        let memory = MemoryQueue(), client = StubClient()
        var callbacks = 0
        let vm = model(memory, client, submitted: { _ in callbacks += 1 })
        vm.feedbackText = "My answer"
        vm.completeFeedback()
        vm.completeFeedback()
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(memory.store.load().first?.status, "completed")
        XCTAssertEqual(memory.store.load().first?.conversation.filter { $0.role == "user" }.count, 1)

        let otherMemory = MemoryQueue()
        let other = model(otherMemory, client)
        other.feedbackText = "Unsent draft"
        other.dismissWithError()
        XCTAssertEqual(otherMemory.store.load().first?.status, "abandoned")
        XCTAssertFalse(otherMemory.store.load().first!.conversation.contains { $0.role == "user" })
    }

    @MainActor
    func testFailedFinishStaysOpenAndRetryDoesNotDuplicateAnswer() async {
        let memory = MemoryQueue(), client = StubClient()
        var callbacks = 0
        let vm = model(memory, client, submitted: { _ in callbacks += 1 })
        memory.failWrites = true
        vm.feedbackText = "Keep this answer"
        vm.completeFeedback()
        XCTAssertEqual(callbacks, 0)
        XCTAssertNotNil(vm.networkError)
        memory.failWrites = false
        vm.retryLastAction()
        await waitUntil { callbacks == 1 }
        XCTAssertEqual(memory.store.load().first?.conversation.filter { $0.role == "user" }.count, 1)
        XCTAssertEqual(memory.store.load().first?.status, "completed")
    }

    @MainActor
    func testEmptyFinishDoesNotComplete() {
        let memory = MemoryQueue(), client = StubClient()
        var callbacks = 0
        let vm = model(memory, client, submitted: { _ in callbacks += 1 })
        vm.feedbackText = " \n "
        vm.completeFeedback()
        XCTAssertEqual(callbacks, 0)
        XCTAssertEqual(memory.store.load().first?.status, "abandoned")
    }

    @MainActor
    func testTranscriptionRetryRetainsAudioAndFollowupRetryDoesNotRetranscribe() async throws {
        let memory = MemoryQueue(), client = StubClient()
        await client.configure(transcriptionFailures: 1, followUpFailures: 1)
        let vm = model(memory, client)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("paydirt_test_\(UUID()).m4a")
        try Data("fake recording consumed only by stub".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        vm.processRecording(at: file)
        await waitUntil { !vm.isLoading }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        vm.retryLastAction()
        await waitUntil { !vm.isLoading }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNotNil(vm.networkError)
        vm.retryLastAction()
        await waitUntil { !vm.isLoading }
        let transcriptionCalls = await client.transcriptionCalls
        XCTAssertEqual(transcriptionCalls, 2)
        XCTAssertEqual(memory.store.load().first?.conversation.filter { $0.role == "user" }.count, 1)
        XCTAssertNil(vm.networkError)
    }

    @MainActor
    func testLateTranscriptionCannotAppendAfterAbandon() async throws {
        let memory = MemoryQueue(), client = StubClient()
        await client.configure(holdTranscription: true)
        let vm = model(memory, client)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("paydirt_test_\(UUID()).m4a")
        try Data("stub".utf8).write(to: file)
        vm.processRecording(at: file)
        for _ in 0..<100 {
            if await client.delayedTranscription != nil { break }
            await Task.yield()
        }
        vm.abandonFeedback()
        await client.releaseTranscription()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(memory.store.load().first?.status, "abandoned")
        XCTAssertFalse(memory.store.load().first!.conversation.contains { $0.role == "user" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    @MainActor
    func testVoicePersistenceFailureRetainsRecordingAndRetriesAcceptedText() async throws {
        let memory = MemoryQueue(), client = StubClient()
        let vm = model(memory, client)
        memory.failWrites = true
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("paydirt_test_\(UUID()).m4a")
        try Data("stub".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        vm.processRecording(at: file)
        await waitUntil { !vm.isLoading }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNotNil(vm.networkError)
        memory.failWrites = false
        vm.retryLastAction()
        await waitUntil { !vm.isLoading }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let transcriptionCalls = await client.transcriptionCalls
        XCTAssertEqual(transcriptionCalls, 1)
        XCTAssertEqual(memory.store.load().first?.conversation.filter { $0.role == "user" }.count, 1)
    }

    @MainActor
    func testErrorDismissAfterAcceptedAnswerAbandonsWithoutCompletion() async {
        let memory = MemoryQueue(), client = StubClient()
        await client.configure(followUpFailures: 1)
        var callbacks = 0
        let vm = model(memory, client, submitted: { _ in callbacks += 1 })
        vm.feedbackText = "An accepted answer"
        vm.processTextFeedback()
        await waitUntil { !vm.isLoading }
        XCTAssertNotNil(vm.networkError)
        vm.dismissWithError()
        await memory.store.retryPending(using: client)
        let statuses = await client.statuses
        XCTAssertFalse(statuses.contains("completed"))
        XCTAssertEqual(memory.store.load().first?.status, "abandoned")
        XCTAssertEqual(callbacks, 0)
    }
}
