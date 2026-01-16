import SwiftUI
import PlaygroundSupport

// Theme colors (matching PaydirtTheme defaults)
let primaryColor = Color(red: 168/255, green: 153/255, blue: 104/255) // Gold
let backgroundColor = Color.white
let textColor = Color.black
let secondaryTextColor = Color.gray

// MARK: - Mock Form View for Design Preview
struct MockFormView: View {
    @State private var feedbackText = ""
    @State private var showVoiceHint = true
    @State private var isRecording = false

    var body: some View {
        VStack(spacing: 20) {
            // Question - now bolder
            Text("Why did you cancel your subscription?")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)

            // Text input area - no border
            textInputArea

            // Action buttons - new voice-first design
            actionButtons
        }
        .padding(30)
        .background(backgroundColor)
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding(.horizontal, 20)
    }

    private var textInputArea: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(backgroundColor)
                .frame(height: 200)
                .cornerRadius(8)

            if feedbackText.isEmpty {
                Text("Share your feedback...")
                    .font(.body)
                    .foregroundColor(secondaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
            }
        }
        .frame(height: 200)
        // No border - removed
    }

    private var actionButtons: some View {
        Group {
            if isRecording {
                recordingControls
            } else {
                defaultControls
            }
        }
    }

    private var recordingControls: some View {
        HStack {
            Text("Listening...")
                .font(.subheadline)
                .foregroundColor(secondaryTextColor)

            Spacer()

            Button(action: { isRecording = false }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
                    .background(Color.black)
                    .clipShape(Circle())
            }
        }
    }

    private var defaultControls: some View {
        HStack {
            // "Use voice →" hint (left aligned, like "Listening...")
            if showVoiceHint && feedbackText.isEmpty {
                Text("Use voice →")
                    .font(.subheadline)
                    .foregroundColor(secondaryTextColor)
            }

            Spacer()

            HStack(spacing: 12) {
                // Large mic button
                Button(action: {
                    isRecording = true
                    showVoiceHint = false
                }) {
                    Image(systemName: "mic")
                        .font(.system(size: 28))
                        .foregroundColor(secondaryTextColor)
                        .frame(width: 80, height: 80)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }

                // Send button - only shows when text is entered
                if !feedbackText.isEmpty {
                    Button(action: {}) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(primaryColor)
                            .clipShape(Circle())
                    }
                }
            }
        }
    }
}

// Set up the live view
let hostView = UIHostingController(rootView:
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()
        MockFormView()
    }
    .frame(width: 390, height: 700)
)

PlaygroundPage.current.liveView = hostView
