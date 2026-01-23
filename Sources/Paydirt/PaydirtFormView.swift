//
// PaydirtFormView.swift
// Voice/text feedback collection UI
// Based on DifferentSDK with Paydirt API integration
//

import SwiftUI
import AVFoundation

// MARK: - Main Feedback View
struct PaydirtFormView: View {
    @ObservedObject var viewModel: PaydirtFormViewModel
    let theme: PaydirtTheme
    let onCompletion: (Bool) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Dynamic question title with fade animation
            Text(viewModel.currentQuestion)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .opacity(viewModel.titleOpacity)
                .animation(.easeInOut(duration: 0.3), value: viewModel.titleOpacity)

            // Text input area with loading overlay
            textInputArea

            // Action buttons with conditional display
            actionButtons
        }
        .padding(30)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding(.horizontal, 20)
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
                .fill(Color.white)
                .frame(height: 200)
                .cornerRadius(8)

            // Text editor for user input
            TextEditor(text: $viewModel.feedbackText)
                .font(.body)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .background(Color.clear)
                .colorScheme(.light)
                .disabled(viewModel.isLoading)

            // Placeholder text when empty - MUST match TextEditor padding exactly
            if viewModel.feedbackText.isEmpty {
                Text("Please tell us your feedback...")
                    .font(.body)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }

            // Loading overlay during API calls
            if viewModel.isLoading {
                Rectangle()
                    .fill(Color.white)
                    .frame(height: 200)
                    .cornerRadius(8)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                            .scaleEffect(1.2)
                    )
            }
        }
        .frame(height: 200)
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
                    .foregroundColor(.black)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(Color.white)
                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    .clipShape(Circle())
            }

            Spacer()

            // Recording status indicator
            Text("Listening...")
                .font(.callout)
                .foregroundColor(.gray)

            Spacer()

            // Complete recording button - checkmark
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.stopAndProcessRecording()
            }) {
                Image(systemName: "checkmark")
                    .foregroundColor(.white)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(Color.black)
                    .clipShape(Circle())
            }
        }
    }

    /// Default controls - matches DifferentSDK exactly
    private var defaultControls: some View {
        HStack {
            // Done button - only shows after first response
            if viewModel.hasSubmittedResponse {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.completeFeedback()
                }) {
                    Text("Done")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }

            Spacer()

            HStack(spacing: 8) {
                // Microphone button to start recording
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.startRecording()
                }) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.gray)
                        .font(.callout)
                        .frame(width: 40, height: 40)
                        .background(Color.white)
                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        .clipShape(Circle())
                }

                // Submit button - checkmark (same for text and voice)
                // Only shows when there's text to submit
                if !viewModel.feedbackText.isEmpty {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.processTextFeedback()
                    }) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                            .font(.callout)
                            .frame(width: 40, height: 40)
                            .background(Color.black)
                            .clipShape(Circle())
                    }
                }
            }
        }
    }

    /// Audio feature hint popup with speech bubble design
    private var audioPopup: some View {
        HStack {
            Spacer()

            ZStack {
                Text("Say it with audio!")
                    .font(.caption)
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .overlay(
                        // Speech bubble tail
                        Triangle()
                            .fill(Color.white)
                            .frame(width: 6, height: 4)
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                            .offset(x: 42, y: 13)
                    )
            }
            .offset(x: -15, y: -45)

            Spacer().frame(width: 40)
        }
        .onAppear {
            viewModel.hideAudioPopupAfterDelay()
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

    private let formId: String
    private let userId: String?
    private let metadata: [String: Any]?
    private let apiClient: PaydirtAPIClient
    private var conversation: [ConversationMessage] = []
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    var onCompletion: (([ConversationMessage]) -> Void)?
    var onDismiss: (() -> Void)?

    init(
        form: PaydirtForm,
        userId: String?,
        metadata: [String: Any]?,
        apiClient: PaydirtAPIClient
    ) {
        self.formId = form.id
        self.currentQuestion = form.prompt
        self.userId = userId
        self.metadata = metadata
        self.apiClient = apiClient
        super.init()

        // Add initial question to conversation
        conversation.append(ConversationMessage(role: "assistant", content: form.prompt, input_type: nil))

        // Setup notification for app foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkMicrophonePermission()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func checkMicrophonePermission() {
        // Just check status, don't request
    }

    func processTextFeedback() {
        let feedback = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feedback.isEmpty else { return }

        feedbackText = ""
        conversation.append(ConversationMessage(role: "user", content: feedback, input_type: "text"))

        PaydirtLogger.shared.info("Form", "Sending message with \(conversation.count) messages in history")

        isLoading = true
        titleOpacity = 0.3

        Task {
            do {
                let response = try await apiClient.sendMessage(
                    formId: formId,
                    message: feedback,
                    conversationHistory: conversation
                )

                PaydirtLogger.shared.info("Form", "Response: is_complete=\(response.is_complete), follow_up=\(response.follow_up_question ?? "nil")")

                // Mark that user has submitted at least one response - show Done button
                hasSubmittedResponse = true

                if response.is_complete {
                    await completeFeedback()
                } else if let followUp = response.follow_up_question {
                    conversation.append(ConversationMessage(role: "assistant", content: followUp, input_type: nil))
                    await animateQuestionChange(to: followUp)
                } else {
                    PaydirtLogger.shared.error("Form", "No follow-up and not complete - unexpected state")
                }
            } catch {
                PaydirtLogger.shared.error("Form", "Failed to process feedback: \(error)")
            }

            isLoading = false
            titleOpacity = 1.0
        }
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

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioURL = documentsPath.appendingPathComponent("paydirt_recording_\(Date().timeIntervalSince1970).m4a")
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
            audioRecorder?.record()
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

        Task {
            do {
                // Read audio data
                let audioData = try Data(contentsOf: url)
                PaydirtLogger.shared.info("Audio", "Audio data size: \(audioData.count) bytes")

                // Transcribe via Paydirt API (which uses OpenAI Whisper)
                let transcription = try await apiClient.transcribeAudio(audioData: audioData)
                PaydirtLogger.shared.info("Audio", "Transcription result: '\(transcription)'")

                if !transcription.isEmpty {
                    // Add to conversation
                    conversation.append(ConversationMessage(role: "user", content: transcription, input_type: "audio"))

                    // Get follow-up
                    let response = try await apiClient.sendMessage(
                        formId: formId,
                        message: transcription,
                        conversationHistory: conversation
                    )

                    PaydirtLogger.shared.info("Audio", "Response: is_complete=\(response.is_complete), follow_up=\(response.follow_up_question ?? "nil")")

                    // Mark that user has submitted at least one response - show Done button
                    hasSubmittedResponse = true

                    if response.is_complete {
                        await completeFeedback()
                    } else if let followUp = response.follow_up_question {
                        conversation.append(ConversationMessage(role: "assistant", content: followUp, input_type: nil))
                        await animateQuestionChange(to: followUp)
                    }
                } else {
                    PaydirtLogger.shared.error("Audio", "Empty transcription returned")
                }
            } catch {
                PaydirtLogger.shared.error("Audio", "Transcription failed: \(error)")
            }

            isLoading = false
            titleOpacity = 1.0

            // Cleanup
            try? FileManager.default.removeItem(at: url)
        }
    }

    func completeFeedback() {
        PaydirtLogger.shared.info("Form", "completeFeedback called, conversation count: \(conversation.count)")

        guard conversation.count > 1 else {
            PaydirtLogger.shared.info("Form", "Not enough messages (\(conversation.count)), dismissing without submit")
            onDismiss?()
            return
        }

        Task {
            do {
                PaydirtLogger.shared.info("Form", "Submitting response for form \(formId)")
                try await apiClient.submitResponse(
                    formId: formId,
                    userId: userId,
                    conversation: conversation,
                    metadata: metadata
                )
                PaydirtLogger.shared.info("Form", "Feedback submitted successfully")
            } catch {
                PaydirtLogger.shared.error("Form", "Failed to submit: \(error)")
            }

            onCompletion?(conversation)
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
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

            // Overlay matching DifferentSDK
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
                theme: PaydirtTheme(),
                onCompletion: { _ in },
                onDismiss: {}
            )
        }
        .previewDisplayName("Form View")
    }
}
#endif
