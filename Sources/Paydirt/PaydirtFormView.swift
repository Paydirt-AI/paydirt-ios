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
            // Question
            Text(viewModel.currentQuestion)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(theme.textColor)
                .multilineTextAlignment(.center)
                .opacity(viewModel.titleOpacity)
                .animation(.easeInOut(duration: 0.3), value: viewModel.titleOpacity)

            // Text input area
            textInputArea

            // Action buttons
            actionButtons
        }
        .padding(30)
        .background(theme.backgroundColor)
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
            Button("Settings") { viewModel.openSettings() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enable microphone access in Settings to use voice feedback.")
        }
    }

    private var textInputArea: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(theme.backgroundColor)
                .frame(height: 200)
                .cornerRadius(8)

            TextEditor(text: $viewModel.feedbackText)
                .font(.body)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .disabled(viewModel.isLoading)

            if viewModel.feedbackText.isEmpty {
                Text("Share your feedback...")
                    .font(.body)
                    .foregroundColor(theme.secondaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }

            if viewModel.isLoading {
                Rectangle()
                    .fill(theme.backgroundColor)
                    .frame(height: 200)
                    .cornerRadius(8)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    )
            }
        }
        .frame(height: 200)
    }

    private var actionButtons: some View {
        Group {
            if viewModel.isRecording {
                recordingControls
            } else {
                defaultControls
            }
        }
        .opacity(viewModel.isLoading ? 0 : 1)
        .disabled(viewModel.isLoading)
    }

    private var recordingControls: some View {
        HStack {
            Text("Listening...")
                .font(.subheadline)
                .foregroundColor(theme.secondaryTextColor)

            Spacer()

            Button(action: viewModel.stopAndProcessRecording) {
                Image(systemName: "checkmark")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
                    .background(Color.black)
                    .clipShape(Circle())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap outside checkmark to cancel
            viewModel.cancelRecording()
        }
    }

    private var defaultControls: some View {
        HStack {
            // "Use voice →" hint (left aligned, like "Listening...")
            if viewModel.showVoiceHint && viewModel.feedbackText.isEmpty {
                Text("Use voice →")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryTextColor)
            }

            Spacer()

            HStack(spacing: 12) {
                // Mic button - large, light gray fill, outline icon
                Button(action: viewModel.startRecording) {
                    Image(systemName: "mic")
                        .font(.system(size: 28))
                        .foregroundColor(theme.secondaryTextColor)
                        .frame(width: 80, height: 80)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }

                // Send button - only shows when text is entered
                if !viewModel.feedbackText.isEmpty {
                    Button(action: viewModel.processTextFeedback) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(theme.primaryColor)
                            .clipShape(Circle())
                    }
                }
            }
        }
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
        conversation.append(ConversationMessage(role: "assistant", content: form.prompt))

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
        conversation.append(ConversationMessage(role: "user", content: feedback))

        isLoading = true
        titleOpacity = 0.3

        Task {
            do {
                let response = try await apiClient.sendMessage(
                    formId: formId,
                    message: feedback,
                    conversationHistory: conversation
                )

                if response.is_complete {
                    await completeFeedback()
                } else if let followUp = response.follow_up_question {
                    conversation.append(ConversationMessage(role: "assistant", content: followUp))
                    await animateQuestionChange(to: followUp)
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

        guard let url = recordingURL else { return }

        isLoading = true
        titleOpacity = 0.3

        Task {
            do {
                // Read audio data
                let audioData = try Data(contentsOf: url)

                // Transcribe via Paydirt API (which uses OpenAI Whisper)
                let transcription = try await apiClient.transcribeAudio(audioData: audioData)

                if !transcription.isEmpty {
                    // Add to conversation
                    conversation.append(ConversationMessage(role: "user", content: transcription))

                    // Get follow-up
                    let response = try await apiClient.sendMessage(
                        formId: formId,
                        message: transcription,
                        conversationHistory: conversation
                    )

                    if response.is_complete {
                        await completeFeedback()
                    } else if let followUp = response.follow_up_question {
                        conversation.append(ConversationMessage(role: "assistant", content: followUp))
                        await animateQuestionChange(to: followUp)
                    }
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
        guard conversation.count > 1 else {
            onDismiss?()
            return
        }

        Task {
            do {
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

        return PaydirtFormView(
            viewModel: viewModel,
            theme: PaydirtTheme(),
            onCompletion: { _ in },
            onDismiss: {}
        )
        .previewDisplayName("Form View")
    }
}
#endif
