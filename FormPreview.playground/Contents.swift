import SwiftUI
import PlaygroundSupport

// MARK: - Form Preview (matches DifferentSDK exactly)
struct FormPreview: View {
    @State private var feedbackText = ""
    @State private var showVoiceHint = true
    @State private var isRecording = false
    @State private var currentQuestion = "Why did you cancel your subscription?"

    var body: some View {
        VStack(spacing: 20) {
            // Dynamic question title
            Text(currentQuestion)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(.black)
                .multilineTextAlignment(.center)

            // Text input area
            textInputArea

            // Action buttons
            actionButtons
        }
        .padding(30)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding(.horizontal, 20)
    }

    private var textInputArea: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white)
                .frame(height: 200)
                .cornerRadius(8)

            if feedbackText.isEmpty {
                Text("Please tell us your feedback...")
                    .font(.body)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }

            TextField("", text: $feedbackText, axis: .vertical)
                .font(.body)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
        }
        .frame(height: 200)
    }

    private var actionButtons: some View {
        ZStack {
            if isRecording {
                listeningControls
            } else {
                defaultControls
            }

            // Audio popup hint
            if showVoiceHint && !isRecording {
                audioPopup
            }
        }
    }

    private var listeningControls: some View {
        HStack {
            // Cancel button
            Button(action: { isRecording = false }) {
                Image(systemName: "xmark")
                    .foregroundColor(.black)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(Color.white)
                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    .clipShape(Circle())
            }

            Spacer()

            Text("Listening...")
                .font(.callout)
                .foregroundColor(.gray)

            Spacer()

            // Complete recording button
            Button(action: { isRecording = false }) {
                Image(systemName: "checkmark")
                    .foregroundColor(.white)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(Color.black)
                    .clipShape(Circle())
            }
        }
    }

    private var defaultControls: some View {
        HStack {
            // Done button - always visible (matches DifferentSDK)
            Button(action: {}) {
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

            Spacer()

            HStack(spacing: 8) {
                // Microphone button
                Button(action: {
                    isRecording = true
                    showVoiceHint = false
                }) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.gray)
                        .font(.callout)
                        .frame(width: 40, height: 40)
                        .background(Color.white)
                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        .clipShape(Circle())
                }

                // Send button - always visible, disabled when empty (matches DifferentSDK)
                Button(action: {}) {
                    Image(systemName: "arrow.up")
                        .foregroundColor(.white)
                        .font(.callout)
                        .frame(width: 40, height: 40)
                        .background(!feedbackText.isEmpty ? Color.black : Color.gray.opacity(0.5))
                        .clipShape(Circle())
                }
                .disabled(feedbackText.isEmpty)
            }
        }
    }

    private var audioPopup: some View {
        HStack {
            Spacer()
            Text("Say it with audio!")
                .font(.caption)
                .foregroundColor(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .offset(x: -15, y: -45)
            Spacer().frame(width: 40)
        }
    }
}

// Set up the live view
let hostView = UIHostingController(rootView:
    ZStack {
        // Semi-transparent overlay (matches DifferentSDK)
        Color.black.opacity(0.4)
            .ignoresSafeArea()
        FormPreview()
    }
    .frame(width: 390, height: 700)
)

PlaygroundPage.current.liveView = hostView
