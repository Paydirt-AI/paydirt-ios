import SwiftUI

@available(iOS 15.0, *)
struct PaydirtSetupCheckView: View {
    private enum TestKind: String, CaseIterable {
        case feature
        case trial
        case subscription

        var title: String {
            switch self {
            case .feature: return "Suggest a Feature"
            case .trial: return "Trial Cancellation"
            case .subscription: return "Subscription Cancellation"
            }
        }

        var icon: String {
            switch self {
            case .feature: return "lightbulb"
            case .trial: return "clock.arrow.circlepath"
            case .subscription: return "creditcard"
            }
        }
    }

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

    let featureFormId: String
    let trialCancellationFormId: String
    let subscriptionCancellationFormId: String
    let requiresSlackDelivery: Bool
    let completionKey: String?
    let apiKey: String
    let baseURL: String
    let theme: PaydirtTheme
    let onClose: () -> Void

    @State private var states: [TestKind: TestState] = [:]
    @State private var responseIds: [TestKind: String] = [:]

    private var allVerified: Bool {
        TestKind.allCases.allSatisfy {
            states[$0] == .delivered || (!requiresSlackDelivery && states[$0] == .received)
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
                        title: "Suggest a Feature",
                        subtitle: requiresSlackDelivery
                            ? "Routes to #paydirt-suggest-a-feature"
                            : "Verifies receipt by Paydirt",
                        tests: [.feature]
                    )
                    testSection(
                        title: "Why users cancel",
                        subtitle: requiresSlackDelivery
                            ? "Both route to #paydirt-cancellations with distinct labels"
                            : "Verifies the two distinct cancellation paths",
                        tests: [.trial, .subscription]
                    )

                    if allVerified {
                        Label(requiresSlackDelivery ? "3 of 3 tests delivered" : "3 of 3 tests received", systemImage: "checkmark.seal.fill")
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
        .onChange(of: allVerified) { verified in
            if verified, let completionKey {
                UserDefaults.standard.set(true, forKey: completionKey)
            }
        }
    }

    private var completionMessage: String {
        if allVerified {
            return requiresSlackDelivery
                ? "All three responses reached their Slack destinations."
                : "All three responses were received by Paydirt."
        }
        return requiresSlackDelivery
            ? "Submit each test yourself. Paydirt will verify the server and Slack delivery."
            : "Submit each test yourself. Paydirt will verify that the server received it."
    }

    @ViewBuilder
    private func testSection(title: String, subtitle: String, tests: [TestKind]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            ForEach(tests, id: \.self) { kind in
                Button { run(kind) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind.icon)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.title).foregroundStyle(.primary)
                            Text((states[kind] ?? .notTested).label)
                                .font(.caption)
                                .foregroundStyle((states[kind] ?? .notTested).color)
                        }
                        Spacer()
                        let verified = states[kind] == .delivered || (!requiresSlackDelivery && states[kind] == .received)
                        Image(systemName: verified ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(verified ? .green : .secondary)
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(states[kind] == .saved || states[kind] == .received || states[kind] == .delivered)
            }
        }
    }

    private func run(_ kind: TestKind) {
        if states[kind] == .retrying, let responseId = responseIds[kind] {
            states[kind] = .received
            Task { await verifyDelivery(responseId: responseId, kind: kind) }
            return
        }

        let formId: String
        let feedbackType: String
        switch kind {
        case .feature:
            formId = featureFormId
            feedbackType = "feature_request"
        case .trial:
            formId = trialCancellationFormId
            feedbackType = "trial_cancellation"
        case .subscription:
            formId = subscriptionCancellationFormId
            feedbackType = "subscription_cancellation"
        }

        Paydirt.presentForm(
            formId: formId,
            metadata: [
                "paydirt_install_test": true,
                "feedback_type": feedbackType,
                "source": "setup_check",
            ],
            onSubmission: { result in
                responseIds[kind] = result.responseId
                states[kind] = .saved
                Task { await verifyDelivery(responseId: result.responseId, kind: kind) }
            }
        )
    }

    @MainActor
    private func verifyDelivery(responseId: String, kind: TestKind) async {
        let client = PaydirtAPIClient(apiKey: apiKey, baseURL: baseURL)
        for _ in 0..<20 {
            do {
                if let status = try await client.getDeliveryStatus(responseId: responseId) {
                    states[kind] = status.slackDelivered ? .delivered : .received
                    if status.slackDelivered || (!requiresSlackDelivery && status.completed) { return }
                }
            } catch {
                PaydirtLogger.shared.warning("Setup", "Delivery verification retrying: \(error.localizedDescription)")
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        states[kind] = .retrying
    }
}
