//
// PaydirtContainerViews.swift
// Container views for presenting forms
// Matches DifferentSDK presentation style exactly
//

import SwiftUI

/// Container for specific form ID
/// Gracefully handles disabled forms by dismissing without showing any UI
struct PaydirtFormContainer: View {
    let formId: String
    let userId: String?
    let metadata: [String: Any]?
    let apiKey: String
    let baseURL: String
    let theme: PaydirtTheme
    let onCompletion: (Bool) -> Void

    @State private var form: PaydirtForm?
    @State private var loading = true
    @State private var error: String?
    @State private var isPresented = true
    @State private var shouldDismiss = false
    @State private var viewModel: PaydirtFormViewModel?

    var body: some View {
        ZStack {
            if !shouldDismiss {
                // Background overlay - matches DifferentSDK exactly
                // Semi-transparent so you can see app behind
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Tap outside to submit and dismiss (after first response)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel?.completeFeedback()
                    }

                VStack(spacing: 20) {
                    if loading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else if let error = error {
                        PaydirtErrorView(message: error, onDismiss: dismiss)
                    } else if let form = form, let vm = viewModel {
                        PaydirtFormView(
                            viewModel: vm,
                            theme: theme,
                            onCompletion: onCompletion,
                            onDismiss: dismiss
                        )
                    }
                }
            }
        }
        .opacity(isPresented ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isPresented)
        .task {
            await loadForm()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // Auto-submit when app goes to background
            viewModel?.completeFeedback()
        }
    }

    private func loadForm() async {
        let client = PaydirtAPIClient(apiKey: apiKey, baseURL: baseURL)
        do {
            let loadedForm = try await client.getForm(formId: formId)
            if let loadedForm = loadedForm {
                form = loadedForm
                // Create ViewModel after form loads
                await MainActor.run {
                    viewModel = PaydirtFormViewModel(
                        form: loadedForm,
                        userId: userId,
                        metadata: metadata,
                        apiClient: client
                    )
                }
            } else {
                // Form is disabled or not found - gracefully dismiss without showing error
                PaydirtLogger.shared.info("SDK", "Form is disabled or not found, dismissing silently")
                shouldDismiss = true
                onCompletion(false)
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isPresented = false
        }
    }
}

/// Container for cancellation form (fetches by type)
/// Gracefully handles disabled forms by dismissing without showing any UI
struct PaydirtCancellationContainer: View {
    let userId: String?
    let metadata: [String: Any]?
    let apiKey: String
    let baseURL: String
    let theme: PaydirtTheme
    let onCompletion: (Bool) -> Void

    @State private var form: PaydirtForm?
    @State private var loading = true
    @State private var error: String?
    @State private var isPresented = true
    @State private var shouldDismiss = false
    @State private var viewModel: PaydirtFormViewModel?

    var body: some View {
        ZStack {
            if !shouldDismiss {
                // Background overlay - matches DifferentSDK exactly
                // Semi-transparent so you can see app behind
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Tap outside to submit and dismiss (after first response)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel?.completeFeedback()
                    }

                VStack(spacing: 20) {
                    if loading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else if let error = error {
                        PaydirtErrorView(message: error, onDismiss: dismiss)
                    } else if let form = form, let vm = viewModel {
                        PaydirtFormView(
                            viewModel: vm,
                            theme: theme,
                            onCompletion: onCompletion,
                            onDismiss: dismiss
                        )
                    }
                }
            }
        }
        .opacity(isPresented ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isPresented)
        .task {
            await loadForm()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // Auto-submit when app goes to background
            viewModel?.completeFeedback()
        }
    }

    private func loadForm() async {
        let client = PaydirtAPIClient(apiKey: apiKey, baseURL: baseURL)
        do {
            let loadedForm = try await client.getForm(type: "cancellation")
            if let loadedForm = loadedForm {
                form = loadedForm
                // Create ViewModel after form loads
                await MainActor.run {
                    viewModel = PaydirtFormViewModel(
                        form: loadedForm,
                        userId: userId,
                        metadata: metadata,
                        apiClient: client
                    )
                }
            } else {
                // Cancellation form is disabled or not found - gracefully dismiss
                PaydirtLogger.shared.info("SDK", "Cancellation form is disabled or not found, dismissing silently")
                shouldDismiss = true
                onCompletion(false)
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isPresented = false
        }
    }
}

/// Error view for SDK issues - matches DifferentSDK ErrorScreen
struct PaydirtErrorView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Error icon
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)

            // Error title
            Text("Configuration Required")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.black)

            // Error description
            Text(message)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Dismiss button
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            }) {
                Text("OK")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.black)
                    .cornerRadius(8)
            }
        }
        .padding(30)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding(.horizontal, 40)
    }
}
