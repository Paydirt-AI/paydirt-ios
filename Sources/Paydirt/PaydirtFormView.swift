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
        .background(theme.background)
        .cornerRadius(theme.cornerRadius)
        .shadow(radius: 10)
        .padding(.horizontal, 20)
        .preferredColorScheme(theme.preferredColorScheme)
        .onAppear {
            viewModel.onCompletion = { _ in
                onCompletion(true)
                onDismiss()
            }
            viewModel.onDismiss = onDismiss
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

    /// Text input area with placeholder and loading states
    private var textInputArea: some View {
        ZStack(alignment: .topLeading) {
            // Background rectangle
            Rectangle()
                .fill(theme.surface)
                .frame(height: 200)
                .cornerRadius(8)

            // Text editor for user input
            TextEditor(text: $viewModel.feedbackText)
                .focused($isTextEditorFocused)
                .font(.body)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .background(Color.clear)
                .foregroundColor(theme.primaryText)
                .disabled(viewModel.isLoading || viewModel.networkError != nil)
                .accessibilityLabel("Feedback answer")
                .accessibilityHint("Enter your response to the current question")

            // Placeholder text when empty - MUST match TextEditor padding exactly
            if viewModel.feedbackText.isEmpty && viewModel.networkError == nil {
                Text("Please tell us your feedback...")
                    .font(.body)
                    .foregroundColor(theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical)
                    .allowsHitTesting(false)
            }

            // Loading overlay during API calls
            if viewModel.isLoading {
                Rectangle()
                    .fill(theme.surface)
                    .frame(height: 200)
                    .cornerRadius(8)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: theme.secondaryText))
                            .scaleEffect(1.2)
                    )
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
        Rectangle()
            .fill(theme.surface)
            .frame(height: 200)
            .cornerRadius(8)
            .overlay(
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
                }
            )
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
            if viewModel.showVoiceHint && !viewModel.isRecording {
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
    private let apiClient: PaydirtAPIClient
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
        apiClient: PaydirtAPIClient,
        onSubmission: ((PaydirtSubmissionResult) -> Void)? = nil
    ) {
        self.formId = form.id
        self.currentQuestion = form.prompt
        self.userId = userId
        self.metadata = metadata
        self.appContext = metadata?["app_context"] as? String
        self.apiClient = apiClient
        self.onSubmission = onSubmission
        super.init()

        // Add initial question to conversation
        conversation.append(ConversationMessage(role: "assistant", content: form.prompt, input_type: nil))
        checkpoint(status: "in_progress")
    }

    /// Persist one complete conversation snapshot. Local encrypted storage is
    /// written synchronously before the best-effort network upsert begins.
    private func checkpoint(status: String) {
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
        PendingSubmissionStore.shared.save(snapshot)

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
                    PendingSubmissionStore.shared.remove(id: conversationId)
                }
            } catch {
                PaydirtLogger.shared.warning(
                    "Queue",
                    "Conversation snapshot remains encrypted for retry: \(conversationId)"
                )
            }
        }
    }

    func processTextFeedback() {
        let feedback = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feedback.isEmpty else { return }

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

        Task {
            await executeTextFeedback(feedback: feedback)
        }
    }

    /// Internal method to execute text feedback - separated for retry support
    private func executeTextFeedback(feedback: String) async {
        do {
            let response = try await apiClient.sendMessage(
                formId: formId,
                message: feedback,
                conversationHistory: conversation,
                previousResponseId: previousResponseId,
                appContext: appContext
            )

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
            PaydirtLogger.shared.error("Form", "Failed to process feedback: \(error)")
            networkError = "Unable to send feedback. Please check your connection."
        }

        isLoading = false
        titleOpacity = 1.0
    }

    func startRecording() {
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
    }

    func stopAndProcessRecording() {
        audioRecorder?.stop()
        isRecording = false

        guard let url = recordingURL else {
            PaydirtLogger.shared.error("Audio", "No recording URL available")
            return
        }

        isLoading = true
        titleOpacity = 0.3

        // Store action for potential retry
        lastAction = { [weak self] in
            guard let self = self else { return }
            await self.executeAudioProcessing(url: url)
        }

        Task {
            await executeAudioProcessing(url: url)
        }
    }

    /// Internal method to execute audio processing - separated for retry support
    private func executeAudioProcessing(url: URL) async {
        defer {
            // Cleanup recording file in all paths
            try? FileManager.default.removeItem(at: url)
        }

        do {
            // Read audio data
            let audioData = try Data(contentsOf: url)
            PaydirtLogger.shared.info("Audio", "Audio data size: \(audioData.count) bytes")

            // Transcribe via Paydirt API (which uses OpenAI Whisper)
            let transcription = try await apiClient.transcribeAudio(audioData: audioData)
            PaydirtLogger.shared.info("Audio", "Transcription completed (\(transcription.count) characters)")

            if !transcription.isEmpty {
                // Add to conversation
                conversation.append(ConversationMessage(role: "user", content: transcription, input_type: "audio"))
                hasSubmittedResponse = true
                checkpoint(status: "in_progress")

                // Get follow-up
                let response = try await apiClient.sendMessage(
                    formId: formId,
                    message: transcription,
                    conversationHistory: conversation,
                    previousResponseId: previousResponseId,
                    appContext: appContext
                )

                previousResponseId = response.response_id

                PaydirtLogger.shared.info("Audio", "Response: is_complete=\(response.is_complete), follow_up=\(response.follow_up_question ?? "nil")")

                if !isFinalized, let followUp = response.follow_up_question {
                    conversation.append(ConversationMessage(role: "assistant", content: followUp, input_type: nil))
                    checkpoint(status: "in_progress")
                    await animateQuestionChange(to: followUp)
                } else {
                    PaydirtLogger.shared.info("Audio", "No follow-up question received")
                }

                // Clear error state on success
                networkError = nil
            } else {
                PaydirtLogger.shared.error("Audio", "Empty transcription returned")
                networkError = "Could not understand audio. Please try again."
            }
        } catch {
            PaydirtLogger.shared.error("Audio", "Transcription failed: \(error)")
            networkError = "Unable to process audio. Please check your connection."
        }

        isLoading = false
        titleOpacity = 1.0
    }

    func completeFeedback() {
        PaydirtLogger.shared.info("Form", "completeFeedback called, conversation count: \(conversation.count)")

        guard !isFinalized else { return }

        // If the user dismisses while text is still in the editor, include
        // those exact words in the final conversation instead of discarding it.
        let draft = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty {
            conversation.append(ConversationMessage(role: "user", content: draft, input_type: "text"))
            feedbackText = ""
            hasSubmittedResponse = true
        }

        isFinalized = true

        guard hasSubmittedResponse else {
            PaydirtLogger.shared.info("Form", "Not enough messages (\(conversation.count)), dismissing without submit")
            checkpoint(status: "abandoned")
            onDismiss?()
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

        // Save to local queue first (guarantees we don't lose it)
        PendingSubmissionStore.shared.save(submission)
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
        // snapshot remains until the API and single Slack delivery succeed.
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
                PendingSubmissionStore.shared.remove(id: submission.id)
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
    /// after an intentional completion or dismissal.
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
        networkError = nil
        isLoading = true
        titleOpacity = 0.3

        Task {
            await lastAction?()
        }
    }

    /// Dismiss the form when user chooses to abandon after an error
    func dismissWithError() {
        networkError = nil
        completeFeedback()
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
