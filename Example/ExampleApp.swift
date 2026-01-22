import SwiftUI
import Paydirt

@main
struct ExampleApp: App {
    init() {
        // Configure Paydirt SDK with Design Test App
        Paydirt.shared.configure(apiKey: "pk_live_FkAeyJbbdrg1WfG6x1gYm3rF2NL21UVf")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var showCancellationForm = false
    @State private var showCustomForm = false
    @State private var lastResult: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Color(red: 168/255, green: 153/255, blue: 104/255))

                    Text("Paydirt SDK Test")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Test voice AI feedback forms")
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)

                Spacer()

                // Test buttons
                VStack(spacing: 16) {
                    Button(action: {
                        showCancellationForm = true
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("Show Cancellation Form")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(red: 168/255, green: 153/255, blue: 104/255))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    Button(action: {
                        showCustomForm = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.pencil")
                            Text("Show Custom Form")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 24)

                // Result display
                if let result = lastResult {
                    Text(result)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal, 24)
                }

                Spacer()

                // Footer
                VStack(spacing: 4) {
                    Text("paydirt.ai")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Configure API key in ExampleApp.swift")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showCancellationForm) {
            // Show cancellation form using SDK
            Paydirt.shared.showCancellationForm(
                userId: "test-user-123",
                metadata: ["source": "example_app"],
                onCompletion: { completed in
                    showCancellationForm = false
                    lastResult = completed ? "Form completed" : "Form dismissed"
                }
            )
        }
        .sheet(isPresented: $showCustomForm) {
            // Show specific form by ID (Cancel Form from Design Test App)
            Paydirt.shared.showForm(
                formId: "b8cad88c-b813-471f-9279-352590a3303b",
                userId: "test-user-123",
                metadata: ["source": "example_app"],
                onCompletion: { completed in
                    showCustomForm = false
                    lastResult = completed ? "Form completed" : "Form dismissed"
                }
            )
        }
    }
}

#Preview {
    ContentView()
}
