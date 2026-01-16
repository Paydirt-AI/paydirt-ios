import SwiftUI

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var showForm = true

    var body: some View {
        ZStack {
            Color.gray.opacity(0.3)
                .ignoresSafeArea()

            if showForm {
                // Mock of PaydirtFormView for design iteration
                MockFormView()
            }
        }
    }
}

// MARK: - Mock Form View (copy of PaydirtFormView for preview)
struct MockFormView: View {
    @State private var feedbackText = ""
    @State private var isRecording = false

    // Theme colors (matching PaydirtTheme defaults)
    let primaryColor = Color(red: 168/255, green: 153/255, blue: 104/255) // Gold
    let backgroundColor = Color.white
    let textColor = Color.black
    let secondaryTextColor = Color.gray

    var body: some View {
        VStack(spacing: 20) {
            // Question
            Text("Why did you cancel your subscription?")
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)

            // Text input area
            textInputArea

            // Action buttons
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

            TextEditor(text: $feedbackText)
                .font(.body)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)

            if feedbackText.isEmpty {
                Text("Share your feedback...")
                    .font(.body)
                    .foregroundColor(secondaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 200)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    private var actionButtons: some View {
        HStack {
            Button(action: {}) {
                Text("Done")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(textColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gray.opacity(0.3))
                    )
            }

            Spacer()

            HStack(spacing: 8) {
                // CURRENT MIC BUTTON - This is what we want to redesign
                Button(action: {}) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(secondaryTextColor)
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Color.gray.opacity(0.3)))
                }

                // Send button
                Button(action: {}) {
                    Image(systemName: "arrow.up")
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(feedbackText.isEmpty ? Color.gray.opacity(0.5) : primaryColor)
                        .clipShape(Circle())
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()
        MockFormView()
    }
}
