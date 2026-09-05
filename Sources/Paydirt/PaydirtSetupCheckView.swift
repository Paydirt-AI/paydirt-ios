import SwiftUI

/// One requested form to verify. Presentation checks do not prove a billing-provider trigger.
public struct PaydirtSetupCheckForm: Identifiable {
    public let formId: String
    public let title: String
    public let feedbackType: String
    public var id: String { formId }

    public init(formId: String, title: String, feedbackType: String) {
        self.formId = formId
        self.title = title
        self.feedbackType = feedbackType
    }
}

@available(iOS 15.0, *)
struct PaydirtSetupCheckView: View {
    private enum TestState: Equatable {
        case notTested
        case saved
        case received
        case delivered
        case retrying

        var label: String {
            switch self {
            case .notTested: return "Not tested"
            case .saved: return "Saved on device"
            case .received: return "Received by Paydirt"
            case .delivered: return "Delivered to Slack"
            case .retrying: return "Delivery retrying"
            }
        }

        var color: Color {
            switch self {
            case .delivered: return .green
            case .retrying: return .orange
            case .notTested: return .secondary
            case .saved, .received: return .blue
            }
        }
    }

    let forms: [PaydirtSetupCheckForm]
    let requiresSlackDelivery: Bool
    let completionKey: String?
    let apiKey: String
    let baseURL: String
    let theme: PaydirtTheme
    let onClose: () -> Void

    @State private var states: [String: TestState] = [:]
    @State private var responseIds: [String: String] = [:]

    private var allVerified: Bool {
        !forms.isEmpty && forms.allSatisfy {
            states[$0.id] == .delivered || (!requiresSlackDelivery && states[$0.id] == .received)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(allVerified ? "Paydirt setup complete" : "Test Paydirt")
                                .font(.title2.bold())
                            Text(completionMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    testSection(
                        title: "Requested forms",
                        subtitle: requiresSlackDelivery
                            ? "Verifies completed feedback in your selected Slack channels"
                            : "Verifies completed feedback received by Paydirt",
                        tests: forms
                    )
                    Text("These checks verify forms and delivery. Verify real subscription triggers separately in your billing sandbox.")
                        .font(.caption).foregroundStyle(.secondary)

                    if allVerified {
                        Label(requiresSlackDelivery ? "\(forms.count) of \(forms.count) tests delivered" : "\(forms.count) of \(forms.count) tests received", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: 560, maxHeight: 690)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(20)
        }
        .task {
            guard let completionKey else { return }
            for form in forms {
                let key = "\(completionKey).response.\(form.id)"
                if let responseId = UserDefaults.standard.string(forKey: key) {
                    responseIds[form.id] = responseId
                    states[form.id] = .saved
                    Task { await verifyDelivery(responseId: responseId, kind: form) }
                }
            }
        }
        .onChange(of: allVerified) { verified in
            if verified, let completionKey {
                UserDefaults.standard.set(true, forKey: completionKey)
            }
        }
    }

    private var completionMessage: String {
        if allVerified {
            return requiresSlackDelivery
                ? "All requested responses reached their Slack destinations."
                : "All requested responses were received by Paydirt."
        }
        return requiresSlackDelivery
            ? "Complete each requested form. Paydirt will verify the server and Slack delivery."
            : "Complete each requested form. Paydirt will verify that the server received it."
    }

    @ViewBuilder
    private func testSection(title: String, subtitle: String, tests: [PaydirtSetupCheckForm]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            ForEach(tests) { kind in
                Button { run(kind) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checklist")
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.title).foregroundStyle(.primary)
                            Text((states[kind.id] ?? .notTested).label)
                                .font(.caption)
                                .foregroundStyle((states[kind.id] ?? .notTested).color)
                        }
                        Spacer()
                        let verified = states[kind.id] == .delivered || (!requiresSlackDelivery && states[kind.id] == .received)
                        Image(systemName: verified ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(verified ? .green : .secondary)
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(states[kind.id] == .saved || states[kind.id] == .received || states[kind.id] == .delivered)
            }
        }
    }

    private func run(_ kind: PaydirtSetupCheckForm) {
        if states[kind.id] == .retrying, let responseId = responseIds[kind.id] {
            states[kind.id] = .received
            Task { await verifyDelivery(responseId: responseId, kind: kind) }
            return
        }

        Paydirt.presentForm(
            formId: kind.formId,
            metadata: [
                "paydirt_install_test": true,
                "feedback_type": kind.feedbackType,
                "source": "setup_check",
            ],
            onSubmission: { result in
                responseIds[kind.id] = result.responseId
                if let completionKey {
                    UserDefaults.standard.set(result.responseId, forKey: "\(completionKey).response.\(kind.id)")
                }
                states[kind.id] = .saved
                Task { await verifyDelivery(responseId: result.responseId, kind: kind) }
            }
        )
    }

    @MainActor
    private func verifyDelivery(responseId: String, kind: PaydirtSetupCheckForm) async {
        let client = PaydirtAPIClient(apiKey: apiKey, baseURL: baseURL)
        for _ in 0..<20 {
            do {
                if let status = try await client.getDeliveryStatus(responseId: responseId) {
                    states[kind.id] = status.slackDelivered && status.completed ? .delivered : (status.completed ? .received : .saved)
                    if status.completed && (status.slackDelivered || !requiresSlackDelivery) { return }
                }
            } catch {
                PaydirtLogger.shared.warning("Setup", "Delivery verification retrying: \(error.localizedDescription)")
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        states[kind.id] = .retrying
    }
}
