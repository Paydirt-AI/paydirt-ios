//
// PaydirtFormView.swift
// Voice/text feedback collection UI
// Native Paydirt voice/text feedback collection
//

import SwiftUI
import AVFoundation

// MARK: - Main Feedback View
struct PaydirtFormView: View {
    @ObservedObject var viewModel: PaydirtFormViewModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTextEditorFocused: Bool
    let theme: PaydirtTheme
    let onCompletion: (Bool) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Dynamic question title with fade animation
            Text(viewModel.currentQuestion)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(theme.primaryText)
                .multilineTextAlignment(.center)
                .opacity(viewModel.titleOpacity)
                .animation(.easeInOut(duration: 0.3), value: viewModel.titleOpacity)

            // Text input area with loading overlay
            textInputArea

            // Action buttons with conditional display
            actionButtons
        }
        .padding(30)
        .background(formBackground)
        .cornerRadius(theme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .stroke(theme.border, lineWidth: 1)
        )
        .shadow(radius: 10)
        .padding(.horizontal, 20)
        .preferredColorScheme(theme.preferredColorScheme)
        .onAppear {
            isTextEditorFocused = false
            viewModel.onCompletion = { _ in
                onCompletion(true)
                onDismiss()
            }
            viewModel.onDismiss = onDismiss
        }
        .onChange(of: viewModel.isLoading) { isLoading in
            if isLoading {
                isTextEditorFocused = false
            }
        }
        .onChange(of: viewModel.currentQuestion) { _ in
            isTextEditorFocused = false
        }
        .alert("Microphone Access Required", isPresented: $viewModel.showMicrophoneAlert) {
            Button("Settings") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.openSettings()
            }
            Button("Cancel", role: .cancel) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } message: {
            Text("To use voice feedback, please enable microphone access in Settings > Privacy & Security > Microphone.")
        }
    }

    private var formBackground: Color {
        colorScheme == .dark ? theme.surface : theme.background
    }

    /// Text input area with placeholder and loading states
    private var textInputArea: some View {
        ZStack(alignment: .topLeading) {
            // Text editor for user input
            TextEditor(text: $viewModel.feedbackText)
                .id(viewModel.currentQuestion)
                .focused($isTextEditorFocused)
                .font(.body)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .paydirtScrollContentBackgroundHidden()
                .background(formBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundColor(theme.primaryText)
                .disabled(viewModel.isLoading || viewModel.networkError != nil)
                .accessibilityLabel("Feedback answer")
                .accessibilityHint("Enter your response to the current question")

            // Placeholder text when empty - MUST match TextEditor padding exactly
            if viewModel.feedbackText.isEmpty && viewModel.networkError == nil && !viewModel.isLoading {
                Text("Tell us...")
                    .font(.body)
                    .foregroundColor(theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical)
                    .allowsHitTesting(false)
            }

            // Loading overlay during API calls
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: theme.secondaryText))
                    .scaleEffect(1.2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .accessibilityLabel("Loading next question")
            }

            // Error overlay when network error occurs
            if let errorMessage = viewModel.networkError {
                errorOverlay(message: errorMessage)
                    .transition(.opacity)
            }
        }
        .frame(height: 200)
        .animation(.easeInOut(duration: 0.3), value: viewModel.networkError)
    }

    /// Error overlay UI with retry and dismiss options
    private func errorOverlay(message: String) -> some View {
        VStack(spacing: 16) {
            // Error icon
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundColor(theme.error)

            // Error message
            Text(message)
                .font(.subheadline)
                .foregroundColor(theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            // Action buttons
            HStack(spacing: 16) {
                // Try Again button
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.retryLastAction()
                }) {
                    Text("Try Again")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(theme.accentText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                // Dismiss button
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.dismissWithError()
                }) {
                    Text("Dismiss")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(theme.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
            Button("Use text") { viewModel.useTextAfterError() }
                .font(.caption)
                .foregroundColor(theme.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(formBackground)
    }

    /// Action buttons container with conditional display based on recording state
    private var actionButtons: some View {
        ZStack {
            if viewModel.isRecording {
                listeningControls
            } else {
                defaultControls
            }

            // Audio popup hint (shows temporarily)
            if viewModel.showVoiceHint && !viewModel.isRecording && !isTextEditorFocused {
                audioPopup
            }
        }
        .opacity(viewModel.isLoading ? 0 : 1)
        .disabled(viewModel.isLoading)
    }

    /// Controls displayed during audio recording
    private var listeningControls: some View {
        HStack {
            // Cancel recording button
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.cancelRecording()
            }) {
                Image(systemName: "xmark")
                    .foregroundColor(theme.primaryText)
                    .font(.title2)
                    .frame(width: 70, height: 70)
                    .background(theme.surface)
                    .overlay(Circle().stroke(theme.border, lineWidth: 1))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Cancel recording")

            Spacer()

            // Recording status indicator
            Text("Listening...")
                .font(.callout)
                .foregroundColor(theme.secondaryText)

            Spacer()

            // Complete recording button - checkmark
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.stopAndProcessRecording()
            }) {
                Image(systemName: "checkmark")
                    .foregroundColor(theme.accentText)
                    .font(.title2)
                    .frame(width: 70, height: 70)
                    .background(theme.accent)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Use recording")
        }
    }

    /// Default controls - mic only, checkmark when typing
    private var defaultControls: some View {
        HStack {
            if viewModel.hasSubmittedResponse || !viewModel.feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Finish") {
                    isTextEditorFocused = false
                    viewModel.completeFeedback()
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(theme.primaryText)
                .accessibilityLabel("Finish and send feedback")
            }
            Spacer()

            if viewModel.feedbackText.isEmpty {
                // Microphone button
                Button(action: {
                    isTextEditorFocused = false  // Dismiss keyboard before recording
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.startRecording()
                }) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(theme.secondaryText)
                        .font(.title)
                        .frame(width: 70, height: 70)
                        .background(theme.surface)
                        .overlay(Circle().stroke(theme.border, lineWidth: 1))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Record voice feedback")
                .disabled(viewModel.isLoading || viewModel.networkError != nil)
            } else {
                // Checkmark button to submit
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.processTextFeedback()
                }) {
                    Image(systemName: "checkmark")
                        .foregroundColor(theme.accentText)
                        .font(.title)
                        .frame(width: 70, height: 70)
                        .background(theme.accent)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Submit answer")
                .disabled(viewModel.isLoading || viewModel.networkError != nil)
            }
        }
    }

    /// Audio hint - gray text with arrow pointing to mic
    private var audioPopup: some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                Text("Tap here")
                    .font(.system(size: 20))
                    .foregroundColor(theme.secondaryText)
                Image(systemName: "arrow.right")
                    .font(.system(size: 20))
                    .foregroundColor(theme.secondaryText)
            }
            .padding(.trailing, 80) // Position to left of mic button
        }
    }
}

private extension View {
    @ViewBuilder
    func paydirtScrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

// MARK: - Triangle Shape
/// Custom shape for creating speech bubble tail in audio popup
struct Triangle: Shape {
    /// Creates triangular path for speech bubble pointer
    /// - Parameter rect: Rectangle bounds for the triangle
    /// - Returns: Path defining triangle shape
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - View Model
@MainActor
class PaydirtFormViewModel: NSObject, ObservableObject {
    @Published var currentQuestion: String
    @Published var feedbackText = "" {
        didSet {
            if !feedbackText.isEmpty {
                showVoiceHint = false
            }
        }
    }
    @Published var isLoading = false
    @Published var titleOpacity: Double = 1.0
    @Published var isRecording = false
    @Published var showMicrophoneAlert = false
    @Published var showVoiceHint = true
    @Published var hasSubmittedResponse = false  // Track if user has submitted at least one response
    @Published var networkError: String? = nil  // Error message for network failures

    private let formId: String
    private let userId: String?
    private let metadata: [String: Any]?
    private let appContext: String?
    private let apiClient: any PaydirtConversationClient
    private let submissionStore: PendingSubmissionStore
    private var activeTask: Task<Void, Never>?
    private var conversation: [ConversationMessage] = []
    private let conversationId = UUID()
    private var snapshotVersion = 0
    private var previousResponseId: String?
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var lastAction: (() async -> Void)? = nil  // Store last action for retry
    private var isFinalized = false
    private let onSubmission: ((PaydirtSubmissionResult) -> Void)?

    var onCompletion: (([ConversationMessage]) -> Void)?
    var onDismiss: (() -> Void)?

    init(
        form: PaydirtForm,
        userId: String?,
        metadata: [String: Any]?,
        apiClient: any PaydirtConversationClient,
        submissionStore: PendingSubmissionStore = .shared,
        onSubmission: ((PaydirtSubmissionResult) -> Void)? = nil
    ) {
        self.formId = form.id
        self.currentQuestion = form.prompt
        self.userId = userId
        self.metadata = metadata
        self.appContext = metadata?["app_context"] as? String
        self.apiClient = apiClient
        self.submissionStore = submissionStore
        self.onSubmission = onSubmission
        super.init()
        cleanupExpiredRecordings()

        // Add initial question to conversation
        conversation.append(ConversationMessage(role: "assistant", content: form.prompt, input_type: nil))
        checkpoint(status: "in_progress")
    }

    /// Persist one complete conversation snapshot. Local encrypted storage is
    /// written synchronously before the best-effort network upsert begins.
    @discardableResult
    private func checkpoint(status: String) -> Bool {
        snapshotVersion += 1
        let version = snapshotVersion
        let snapshot = PendingSubmission(
            id: conversationId,
            formId: formId,
            userId: userId,
            conversation: conversation,
            metadata: metadata,
            status: status,
            snapshotVersion: version
        )
        guard submissionStore.save(snapshot) else {
            networkError = "Could not save feedback on this device. Please try again."
            return false
        }

        let messages = conversation
        Task {
            do {
                try await apiClient.submitResponse(
                    submissionId: conversationId,
                    formId: formId,
                    userId: userId,
                    conversation: messages,
                    metadata: metadata,
                    status: status,
                    snapshotVersion: version
                )
                if status == "completed" || status == "abandoned" {
                    submissionStore.remove(id: conversationId, snapshotVersion: version)
                }
            } catch {
                PaydirtLogger.shared.warning(
                    "Queue",
                    "Conversation snapshot remains encrypted for retry: \(conversationId)"
                )
            }
        }
        return true
    }

    func processTextFeedback() {
        let feedback = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isFinalized, !isLoading, !feedback.isEmpty else { return }

        feedbackText = ""
        conversation.append(ConversationMessage(role: "user", content: feedback, input_type: "text"))
        hasSubmittedResponse = true
        checkpoint(status: "in_progress")

        PaydirtLogger.shared.info("Form", "Sending message with \(conversation.count) messages in history")

        isLoading = true
        titleOpacity = 0.3

        // Store action for potential retry
        lastAction = { [weak self] in
            guard let self = self else { return }
            await self.executeTextFeedback(feedback: feedback)
        }

        activeTask = Task {
            await executeTextFeedback(feedback: feedback)
        }
    }

    /// Internal method to execute text feedback - separated for retry support
    private func executeTextFeedback(feedback: String) async {
        guard !isFinalized, !Task.isCancelled else { return }
        // Also retries a failed local write without appending the accepted answer.
        guard checkpoint(status: "in_progress") else {
            isLoading = false
            titleOpacity = 1
            return
        }
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
        do {
            let response = try await apiClient.sendMessage(
                formId: formId,
                message: feedback,
                conversationHistory: conversation,
                previousResponseId: previousResponseId,
                appContext: appContext
            )

            guard !isFinalized, !Task.isCancelled else { return }
            previousResponseId = response.response_id

            PaydirtLogger.shared.info("Form", "Response: is_complete=\(response.is_complete), follow_up=\(response.follow_up_question ?? "nil")")

            // Do not add late AI output after the user has already closed the form.
            if !isFinalized, let followUp = response.follow_up_question {
                conversation.append(ConversationMessage(role: "assistant", content: followUp, input_type: nil))
                checkpoint(status: "in_progress")
                await animateQuestionChange(to: followUp)
            } else {
                PaydirtLogger.shared.info("Form", "No follow-up question received")
            }

            // Clear error state on success
            networkError = nil
        } catch {
            guard !isFinalized, !Task.isCancelled else { return }
            PaydirtLogger.shared.error("Form", "Failed to process feedback: \(error)")
            networkError = "Unable to send feedback. Please check your connection."
        }

        isLoading = false
        titleOpacity = 1.0
    }

    func startRecording() {
        guard !isFinalized, !isLoading, networkError == nil else { return }
        let session = AVAudioSession.sharedInstance()

        switch session.recordPermission {
        case .granted:
            beginRecording()
        case .denied:
            showMicrophoneAlert = true
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.beginRecording()
                    }
                }
            }
        @unknown default:
            break
        }
    }

    private func beginRecording() {
        guard !isFinalized, !isLoading else { return }
        cancelRecording()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let audioURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("paydirt_recording_\(UUID().uuidString).m4a")
            recordingURL = audioURL

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey: 64000
            ]

            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.prepareToRecord()
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: audioURL.path
            )
            audioRecorder?.record(forDuration: 120)
            isRecording = true
            showVoiceHint = false
            feedbackText = ""

            PaydirtLogger.shared.info("Audio", "Recording started")
        } catch {
            PaydirtLogger.shared.error("Audio", "Recording failed: \(error)")
        }
    }

    func cancelRecording() {
        audioRecorder?.stop()
        isRecording = false
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        audioRecorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func stopAndProcessRecording() {
        audioRecorder?.stop()
        isRecording = false

        guard let url = recordingURL else {
            PaydirtLogger.shared.error("Audio", "No recording URL available")
            return
        }

        processRecording(at: url)
    }

    /// Separate entry point also used by lifecycle tests with protected fixtures.
    func processRecording(at url: URL) {
        guard !isFinalized, !isLoading else { return }
        recordingURL = url
        isLoading = true
        titleOpacity = 0.3
        lastAction = { [weak self] in await self?.executeAudioProcessing(url: url) }
        activeTask = Task { await executeAudioProcessing(url: url) }
    }

    /// Internal method to execute audio processing - separated for retry support
    private func executeAudioProcessing(url: URL) async {
        guard !isFinalized, !Task.isCancelled else { return }
        do {
            let audioData = try Data(contentsOf: url)
            let transcription = try await apiClient.transcribeAudio(audioData: audioData)
            guard !isFinalized, !Task.isCancelled else { return }
            guard !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                networkError = "Could not understand audio. Try again or use text."
                isLoading = false
                titleOpacity = 1
                return
            }
            conversation.append(ConversationMessage(role: "user", content: transcription, input_type: "audio"))
            hasSubmittedResponse = true
            // The answer is now accepted. Every subsequent retry persists it and
            // requests a follow-up; it never uploads or appends the answer again.
            lastAction = { [weak self] in await self?.executeTextFeedback(feedback: transcription) }
            await executeTextFeedback(feedback: transcription)
        } catch {
            guard !isFinalized, !Task.isCancelled else { return }
            // Keep the protected recording until retry, discard or expiry.
            networkError = "Unable to process audio. Try again or use text."
            isLoading = false
            titleOpacity = 1
        }
    }

    func completeFeedback() {
        PaydirtLogger.shared.info("Form", "completeFeedback called, conversation count: \(conversation.count)")

        guard !isFinalized else { return }

        // Only the explicit Finish action may accept an editor draft.
        let draft = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty {
            conversation.append(ConversationMessage(role: "user", content: draft, input_type: "text"))
            feedbackText = ""
            hasSubmittedResponse = true
        }

        guard hasSubmittedResponse else {
            PaydirtLogger.shared.info("Form", "Not enough messages (\(conversation.count)), dismissing without submit")
            abandonFeedback()
            return
        }

        let submission = PendingSubmission(
            id: conversationId,
            formId: formId,
            userId: userId,
            conversation: conversation,
            metadata: metadata,
            status: "completed",
            snapshotVersion: snapshotVersion + 1
        )
        snapshotVersion = submission.snapshotVersion

        guard submissionStore.save(submission) else {
            networkError = "Could not save feedback on this device. Please try again."
            lastAction = { [weak self] in self?.completeFeedback() }
            isLoading = false
            return
        }
        isFinalized = true
        activeTask?.cancel()
        lastAction = nil
        cancelRecording()
        onSubmission?(PaydirtSubmissionResult(
            responseId: submission.id.uuidString.lowercased(),
            formId: formId,
            userId: userId,
            messages: conversation.map {
                PaydirtFeedbackMessage(
                    role: $0.role,
                    content: $0.content,
                    inputType: $0.input_type
                )
            },
            metadata: metadata
        ))

        let finalConversation = conversation

        // Fire-and-forget: the form dismisses immediately, while the encrypted
        // snapshot remains until the API durably accepts the completed response.
        Task {
            do {
                PaydirtLogger.shared.info("Form", "Submitting response for form \(formId)")
                try await apiClient.submitResponse(
                    submissionId: submission.id,
                    formId: formId,
                    userId: userId,
                    conversation: finalConversation,
                    metadata: metadata,
                    status: "completed",
                    snapshotVersion: submission.snapshotVersion
                )
                // Success - remove from pending queue
                submissionStore.remove(id: submission.id, snapshotVersion: submission.snapshotVersion)
                PaydirtLogger.shared.info("Form", "Feedback submitted successfully")
            } catch {
                PaydirtLogger.shared.error("Form", "Submission failed, queued for retry: \(error)")
                // Stays in pending queue for retry on next app launch
            }
        }

        // Dismiss IMMEDIATELY - don't wait for API call
        onCompletion?(conversation)
    }

    /// Checkpoint accepted turns when the app is interrupted. This deliberately
    /// does not finalize the response, so Slack still receives only one message
    /// after an explicit Finish action.
    func saveProgressForInterruption() {
        guard !isFinalized else { return }
        checkpoint(status: "in_progress")
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Retry the last failed action after a network error
    func retryLastAction() {
        guard !isFinalized, !isLoading, let lastAction else { return }
        networkError = nil
        isLoading = true
        titleOpacity = 0.3

        activeTask = Task { await lastAction() }
    }

    /// Dismiss the form when user chooses to abandon after an error
    func dismissWithError() {
        abandonFeedback()
    }

    func abandonFeedback() {
        guard !isFinalized else { return }
        isFinalized = true
        activeTask?.cancel()
        lastAction = nil
        feedbackText = ""
        cancelRecording()
        checkpoint(status: "abandoned")
        onDismiss?()
    }

    func useTextAfterError() {
        guard !isFinalized else { return }
        activeTask?.cancel()
        cancelRecording()
        lastAction = nil
        networkError = nil
        isLoading = false
        titleOpacity = 1
    }

    private func cleanupExpiredRecordings() {
        let directory = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for file in files where file.lastPathComponent.hasPrefix("paydirt_recording_") {
            let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate
            if let created, Date().timeIntervalSince(created) > 24 * 60 * 60 {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Automatically hides audio feature popup after delay
    func hideAudioPopupAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000) // 6 seconds
            await MainActor.run {
                withAnimation {
                    showVoiceHint = false
                }
            }
        }
    }

    private func animateQuestionChange(to newQuestion: String) async {
        withAnimation(.easeInOut(duration: 0.3)) {
            titleOpacity = 0
        }

        try? await Task.sleep(nanoseconds: 300_000_000)

        guard !isFinalized, !Task.isCancelled else { return }
        currentQuestion = newQuestion
        showVoiceHint = false  // No hint on follow-up questions

        withAnimation(.easeInOut(duration: 0.3)) {
            titleOpacity = 1
        }
    }
}

// MARK: - AVAudioRecorderDelegate
extension PaydirtFormViewModel: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            PaydirtLogger.shared.info("Audio", "Recording finished - Success: \(flag)")
            if flag && isRecording {
                stopAndProcessRecording()
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            if let error = error {
                PaydirtLogger.shared.error("Audio", "Recording encode error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - SwiftUI Preview

#if DEBUG
struct PaydirtFormView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Background to simulate app content
            Color.blue.opacity(0.3)
                .ignoresSafeArea()

            // Preview overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // The form
            let mockForm = PaydirtForm(
                id: "preview-form",
                name: "Cancellation Survey",
                type: "cancellation",
                prompt: "Why did you cancel your subscription?",
                enabled: true
            )
            let mockApiClient = PaydirtAPIClient(apiKey: "preview-key", baseURL: "https://api.paydirt.ai")
            let viewModel = PaydirtFormViewModel(
                form: mockForm,
                userId: "preview-user",
                metadata: nil,
                apiClient: mockApiClient
            )

            PaydirtFormView(
                viewModel: viewModel,
                theme: .automatic,
                onCompletion: { _ in },
                onDismiss: {}
            )
        }
        .previewDisplayName("Form View")
    }
}
#endif
