//
// PaydirtContainerViews.swift
// Container views for presenting forms
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
    @State private var shouldDismiss = false  // For graceful handling of disabled forms

    var body: some View {
        ZStack {
            if !shouldDismiss {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                    }

                if loading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if let error = error {
                    PaydirtErrorView(message: error)
                } else if let form = form {
                    PaydirtFormView(
                        viewModel: PaydirtFormViewModel(
                            form: form,
                            userId: userId,
                            metadata: metadata,
                            apiClient: PaydirtAPIClient(apiKey: apiKey, baseURL: baseURL)
                        ),
                        theme: theme,
                        onCompletion: onCompletion,
                        onDismiss: dismiss
                    )
                }
            }
        }
        .opacity(isPresented ? 1 : 0)
        .task {
            await loadForm()
        }
    }

    private func loadForm() async {
        let client = PaydirtAPIClient(apiKey: apiKey, baseURL: baseURL)
        do {
            let loadedForm = try await client.getForm(formId: formId)
            if let loadedForm = loadedForm {
                form = loadedForm
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
    @State private var shouldDismiss = false  // For graceful handling of disabled forms

    var body: some View {
        ZStack {
            if !shouldDismiss {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                    }

                if loading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if let error = error {
                    PaydirtErrorView(message: error)
                } else if let form = form {
                    PaydirtFormView(
                        viewModel: PaydirtFormViewModel(
                            form: form,
                            userId: userId,
                            metadata: metadata,
                            apiClient: PaydirtAPIClient(apiKey: apiKey, baseURL: baseURL)
                        ),
                        theme: theme,
                        onCompletion: onCompletion,
                        onDismiss: dismiss
                    )
                }
            }
        }
        .opacity(isPresented ? 1 : 0)
        .task {
            await loadForm()
        }
    }

    private func loadForm() async {
        let client = PaydirtAPIClient(apiKey: apiKey, baseURL: baseURL)
        do {
            let loadedForm = try await client.getForm(type: "cancellation")
            if let loadedForm = loadedForm {
                form = loadedForm
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

/// Error view for SDK issues
struct PaydirtErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)

            Text("Error")
                .font(.headline)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(30)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding(.horizontal, 40)
    }
}
