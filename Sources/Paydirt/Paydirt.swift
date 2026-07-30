//
// Paydirt.swift
// Voice AI cancellation forms for subscription apps
//

import SwiftUI

/// A single question or answer captured by Paydirt.
public struct PaydirtFeedbackMessage {
    public let role: String
    public let content: String
    public let inputType: String?

    public init(role: String, content: String, inputType: String? = nil) {
        self.role = role
        self.content = content
        self.inputType = inputType
    }
}

/// The locally durable result produced when a user finishes a feedback form.
///
/// `responseId` is generated before delivery and remains stable across retries,
/// so it can be used to correlate Paydirt, Slack, webhook, and agent workflows.
public struct PaydirtSubmissionResult {
    public let responseId: String
    public let formId: String
    public let userId: String?
    public let messages: [PaydirtFeedbackMessage]
    public let metadata: [String: Any]?

    public init(
        responseId: String,
        formId: String,
        userId: String?,
        messages: [PaydirtFeedbackMessage],
        metadata: [String: Any]?
    ) {
        self.responseId = responseId
        self.formId = formId
        self.userId = userId
        self.messages = messages
        self.metadata = metadata
    }
}

/// The subscription system which detected a cancellation.
public enum PaydirtSubscriptionProvider: String {
    case storeKit = "storekit"
    case revenueCat = "revenuecat"
    case superwall = "superwall"
    case custom = "custom"
}

/// A provider-independent cancellation event.
///
/// RevenueCat, StoreKit, Superwall, or app-owned billing code can all create
/// this value. Paydirt uses it to select the trial or paid cancellation form,
/// prevent duplicate presentation, and attach consistent Slack metadata.
public struct PaydirtSubscriptionCancellation {
    public let provider: PaydirtSubscriptionProvider
    public let productId: String
    public let entitlementId: String?
    public let userId: String?
    public let isTrial: Bool
    public let periodType: String
    public let localizedPrice: String?
    public let catalogPrice: Double?
    public let currencyCode: String?
    public let billingPeriod: String?
    public let expirationDate: Date?
    public let cancellationDetectedAt: Date?
    public let deduplicationId: String?
    public let additionalMetadata: [String: Any]

    public init(
        provider: PaydirtSubscriptionProvider,
        productId: String,
        entitlementId: String? = nil,
        userId: String? = nil,
        isTrial: Bool,
        periodType: String? = nil,
        localizedPrice: String? = nil,
        catalogPrice: Double? = nil,
        currencyCode: String? = nil,
        billingPeriod: String? = nil,
        expirationDate: Date? = nil,
        cancellationDetectedAt: Date? = nil,
        deduplicationId: String? = nil,
        additionalMetadata: [String: Any] = [:]
    ) {
        self.provider = provider
        self.productId = productId
        self.entitlementId = entitlementId
        self.userId = userId
        self.isTrial = isTrial
        self.periodType = periodType ?? (isTrial ? "Trial" : "Normal")
        self.localizedPrice = localizedPrice
        self.catalogPrice = catalogPrice
        self.currencyCode = currencyCode
        self.billingPeriod = billingPeriod
        self.expirationDate = expirationDate
        self.cancellationDetectedAt = cancellationDetectedAt
        self.deduplicationId = deduplicationId
        self.additionalMetadata = additionalMetadata
    }
}

/// Main interface for Paydirt SDK
/// Configure with API key, then present feedback forms
public final class Paydirt: NSObject {
    public static let shared = Paydirt()

    private var apiKey: String?
    private var baseURL: String = "https://api.paydirt.ai"
    private var currentUserId: String?
    private var theme: PaydirtTheme = .automatic
    internal var storeKitCancellationMonitor: PaydirtStoreKitCancellationMonitor?

    private override init() {
        super.init()
    }

    // MARK: - Convenience Static API (for one-line setup)

    /// Configure the SDK with your Paydirt API key (static convenience API)
    public static func configure(
        apiKey: String,
        baseURL: String? = nil,
        theme: PaydirtTheme? = nil
    ) {
        shared.configure(apiKey: apiKey, baseURL: baseURL, theme: theme)
    }

    /// Update Paydirt's appearance without reconfiguring the SDK.
    public static func setTheme(_ theme: PaydirtTheme) {
        shared.setTheme(theme)
    }

    /// Set the current user ID (static convenience API)
    public static func setUserId(_ userId: String?) {
        shared.setUserId(userId)
    }

    /// Set the log level (static convenience API)
    public static func setLogLevel(_ level: PaydirtLogLevel) {
        shared.setLogLevel(level)
    }

    /// Pre-fetch forms for faster startup (static convenience API)
    public static func prefetchForms(formIds: [String]? = nil, types: [String]? = nil) {
        shared.prefetchForms(formIds: formIds, types: types)
    }

    /// Return a feedback form view by ID (static convenience API)
    public static func showForm(
        formId: String,
        userId: String? = nil,
        metadata: [String: Any]? = nil,
        onSubmission: ((PaydirtSubmissionResult) -> Void)? = nil,
        onCompletion: @escaping (Bool) -> Void = { _ in }
    ) -> AnyView {
        shared.showForm(
            formId: formId,
            userId: userId,
            metadata: metadata,
            onSubmission: onSubmission,
            onCompletion: onCompletion
        )
    }

    /// Return a cancellation form view (static convenience API)
    public static func showCancellationForm(
        userId: String? = nil,
        metadata: [String: Any]? = nil,
        onSubmission: ((PaydirtSubmissionResult) -> Void)? = nil,
        onCompletion: @escaping (Bool) -> Void = { _ in }
    ) -> AnyView {
        shared.showCancellationForm(
            userId: userId,
            metadata: metadata,
            onSubmission: onSubmission,
            onCompletion: onCompletion
        )
    }

    /// Present a feedback form directly (static convenience API)
    public static func presentForm(
        formId: String,
        userId: String? = nil,
        metadata: [String: Any]? = nil,
        onSubmission: ((PaydirtSubmissionResult) -> Void)? = nil,
        onCompletion: @escaping (Bool) -> Void = { _ in }
    ) {
        shared.presentForm(
            formId: formId,
            userId: userId,
            metadata: metadata,
            onSubmission: onSubmission,
            onCompletion: onCompletion
        )
    }

    /// Route a cancellation from any billing provider into the correct form.
    public static func handleSubscriptionCancellation(
        _ cancellation: PaydirtSubscriptionCancellation,
        cancellationFormId: String? = nil,
        trialCancellationFormId: String? = nil
    ) {
        shared.handleSubscriptionCancellation(
            cancellation,
            cancellationFormId: cancellationFormId,
            trialCancellationFormId: trialCancellationFormId
        )
    }

    // MARK: - Cancellation Form Spam Prevention

    /// Returns a UserDefaults key for tracking if cancellation form was shown
    /// - Parameters:
    ///   - userId: The user ID
    ///   - entitlementId: The entitlement identifier
    /// - Returns: A unique key for this user/entitlement combination
    private func cancellationFormKey(userId: String, entitlementId: String) -> String {
        return "paydirt_cancellation_shown_\(userId)_\(entitlementId)"
    }

    /// Check if the cancellation form has already been shown for this user/entitlement
    /// - Parameters:
    ///   - userId: The user ID
    ///   - entitlementId: The entitlement identifier
    /// - Returns: True if form was already shown
    private func hasCancellationFormBeenShown(userId: String, entitlementId: String) -> Bool {
        let key = cancellationFormKey(userId: userId, entitlementId: entitlementId)
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Mark the cancellation form as shown for this user/entitlement
    /// - Parameters:
    ///   - userId: The user ID
    ///   - entitlementId: The entitlement identifier
    private func markCancellationFormShown(userId: String, entitlementId: String) {
        let key = cancellationFormKey(userId: userId, entitlementId: entitlementId)
        UserDefaults.standard.set(true, forKey: key)
        PaydirtLogger.shared.debug("SDK", "Marked cancellation form as shown for \(entitlementId)")
    }

    /// Clear the cancellation form shown flag (called when user resubscribes)
    /// - Parameters:
    ///   - userId: The user ID
    ///   - entitlementId: The entitlement identifier
    private func clearCancellationFormShown(userId: String, entitlementId: String) {
        let key = cancellationFormKey(userId: userId, entitlementId: entitlementId)
        UserDefaults.standard.removeObject(forKey: key)
        PaydirtLogger.shared.debug("SDK", "Cleared cancellation form shown flag for \(entitlementId)")
    }

    /// Configure the SDK with your Paydirt API key
    /// - Parameters:
    ///   - apiKey: Your Paydirt API key (starts with pk_live_)
    ///   - baseURL: Optional custom API URL (for testing)
    public func configure(
        apiKey: String,
        baseURL: String? = nil,
        theme: PaydirtTheme? = nil
    ) {
        self.apiKey = apiKey
        if let baseURL = baseURL {
            self.baseURL = baseURL
        }
        if let theme = theme {
            self.theme = theme
        }
        PaydirtLogger.shared.info("SDK", "Paydirt SDK v2.0.0 configured")

        // Retry any pending submissions from previous sessions
        let apiClient = PaydirtAPIClient(apiKey: apiKey, baseURL: self.baseURL)
        Task {
            await PendingSubmissionStore.shared.retryPending(using: apiClient)
        }
    }

    /// Set the current user ID for tracking
    /// - Parameter userId: User identifier (e.g., RevenueCat user ID)
    public func setUserId(_ userId: String?) {
        self.currentUserId = userId
    }

    /// Set the log level for debugging
    public func setLogLevel(_ level: PaydirtLogLevel) {
        PaydirtLogger.shared.setLogLevel(level)
    }

    /// Update the colors used by subsequently presented Paydirt forms.
    public func setTheme(_ theme: PaydirtTheme) {
        self.theme = theme
    }

    /// Pre-fetch forms to enable instant display when shown later
    /// Call this during app startup or SDK configuration for best UX
    /// - Parameters:
    ///   - formIds: Optional array of form IDs to prefetch
    ///   - types: Optional array of form types to prefetch (e.g., ["cancellation", "feature_request"])
    public func prefetchForms(formIds: [String]? = nil, types: [String]? = nil) {
        guard let apiKey = apiKey else {
            PaydirtLogger.shared.warning("SDK", "Cannot prefetch forms - SDK not configured")
            return
        }

        let client = PaydirtAPIClient(apiKey: apiKey, baseURL: baseURL)

        Task {
            // Prefetch by form ID
            if let formIds = formIds {
                for formId in formIds {
                    do {
                        if let form = try await client.getForm(formId: formId) {
                            await FormCache.shared.set(form: form)
                            PaydirtLogger.shared.info("SDK", "Prefetched form: \(formId)")
                        }
                    } catch {
                        PaydirtLogger.shared.warning("SDK", "Failed to prefetch form \(formId): \(error.localizedDescription)")
                    }
                }
            }

            // Prefetch by form type
            if let types = types {
                for type in types {
                    do {
                        if let form = try await client.getForm(type: type) {
                            await FormCache.shared.set(form: form)
                            PaydirtLogger.shared.info("SDK", "Prefetched form type: \(type)")
                        }
                    } catch {
                        PaydirtLogger.shared.warning("SDK", "Failed to prefetch form type \(type): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Present a feedback form by form ID
    /// - Parameters:
    ///   - formId: The form ID from your Paydirt dashboard
    ///   - userId: User identifier (e.g., RevenueCat user ID)
    ///   - metadata: Optional metadata to include with responses
    ///   - onCompletion: Called when form is completed or dismissed
    /// - Returns: SwiftUI View to present
    public func showForm(
        formId: String,
        userId: String? = nil,
        metadata: [String: Any]? = nil,
        onSubmission: ((PaydirtSubmissionResult) -> Void)? = nil,
        onCompletion: @escaping (Bool) -> Void = { _ in }
    ) -> AnyView {
        guard let apiKey = apiKey else {
            PaydirtLogger.shared.error("SDK", "API key not configured")
            return AnyView(PaydirtErrorView(message: "SDK not configured", theme: theme, onDismiss: {}))
        }

        return AnyView(PaydirtFormContainer(
            formId: formId,
            userId: userId ?? currentUserId,
            metadata: metadata,
            apiKey: apiKey,
            baseURL: baseURL,
            theme: theme,
            onSubmission: onSubmission,
            onCompletion: onCompletion
        ))
    }

    /// Convenience method to show cancellation form
    /// Fetches the form with type "cancellation" automatically
    public func showCancellationForm(
        userId: String? = nil,
        metadata: [String: Any]? = nil,
        onSubmission: ((PaydirtSubmissionResult) -> Void)? = nil,
        onCompletion: @escaping (Bool) -> Void = { _ in }
    ) -> AnyView {
        guard let apiKey = apiKey else {
            return AnyView(PaydirtErrorView(message: "SDK not configured", theme: theme, onDismiss: {}))
        }

        return AnyView(PaydirtCancellationContainer(
            userId: userId ?? currentUserId,
            metadata: metadata,
            apiKey: apiKey,
            baseURL: baseURL,
            theme: theme,
            onSubmission: onSubmission,
            onCompletion: onCompletion
        ))
    }

    /// Present a feedback form directly (handles presentation correctly)
    /// - Parameters:
    ///   - formId: The form ID from your Paydirt dashboard
    ///   - userId: User identifier (e.g., RevenueCat user ID)
    ///   - metadata: Optional metadata to include with responses
    ///   - onCompletion: Called when form is completed or dismissed
    public func presentForm(
        formId: String,
        userId: String? = nil,
        metadata: [String: Any]? = nil,
        onSubmission: ((PaydirtSubmissionResult) -> Void)? = nil,
        onCompletion: @escaping (Bool) -> Void = { _ in }
    ) {
        guard let rootViewController = resolveRootViewController() else {
            PaydirtLogger.shared.error("SDK", "Could not find root view controller")
            return
        }

        var hostingController: UIHostingController<AnyView>!
        hostingController = UIHostingController(
            rootView: showForm(
                formId: formId,
                userId: userId,
                metadata: metadata,
                onSubmission: onSubmission,
                onCompletion: { completed in
                    hostingController.dismiss(animated: true)
                    onCompletion(completed)
                }
            )
        )

        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = .clear

        presentFromRoot(hostingController, rootViewController: rootViewController)
    }

    /// Internal method retained for source compatibility with existing manual integrations.
    internal func presentCancellationFormOnWindow() {
        guard let rootViewController = resolveRootViewController() else {
            PaydirtLogger.shared.error("SDK", "Could not find root view controller")
            return
        }

        var hostingController: UIHostingController<AnyView>!
        hostingController = UIHostingController(
            rootView: showCancellationForm(
                userId: currentUserId,
                metadata: ["source": "manual_cancellation"],
                onCompletion: { completed in
                    hostingController.dismiss(animated: true)
                    PaydirtLogger.shared.info("SDK", "Cancellation form completed: \(completed)")
                }
            )
        )

        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = .clear

        presentFromRoot(hostingController, rootViewController: rootViewController)
    }

    private func presentFromRoot(
        _ controller: UIViewController,
        rootViewController: UIViewController
    ) {
        let topController = topViewController(from: rootViewController)
        topController.present(controller, animated: true)
    }

    private func topViewController(from root: UIViewController) -> UIViewController {
        var controller = root
        while let presented = controller.presentedViewController {
            controller = presented
        }
        return controller
    }

    private func resolveRootViewController() -> UIViewController? {
        let activeScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first { $0.activationState == .foregroundActive }

        guard let window = activeScene?.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }

        return window.rootViewController
    }

    internal func presentCancellationFormOnWindowWithFormId(
        _ formId: String,
        userId: String? = nil,
        metadata: [String: Any] = ["source": "subscription_cancellation"]
    ) {
        guard let rootViewController = resolveRootViewController() else {
            PaydirtLogger.shared.error("SDK", "Could not find root view controller")
            return
        }

        var hostingController: UIHostingController<AnyView>!
        hostingController = UIHostingController(
            rootView: showForm(
                formId: formId,
                userId: userId ?? currentUserId,
                metadata: metadata,
                onCompletion: { completed in
                    hostingController.dismiss(animated: true)
                    PaydirtLogger.shared.info("SDK", "Cancellation form completed: \(completed)")
                }
            )
        )

        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = .clear
        presentFromRoot(hostingController, rootViewController: rootViewController)
    }

    /// Route a provider cancellation into the trial or paid cancellation form.
    public func handleSubscriptionCancellation(
        _ cancellation: PaydirtSubscriptionCancellation,
        cancellationFormId: String? = nil,
        trialCancellationFormId: String? = nil
    ) {
        guard apiKey != nil else {
            PaydirtLogger.shared.error("SDK", "Must configure SDK before handling subscription cancellation")
            return
        }

        let userId = cancellation.userId ?? currentUserId ?? "anonymous"
        let expirationKey = cancellation.expirationDate.map {
            String(Int($0.timeIntervalSince1970))
        } ?? "unknown"
        let cancellationKey = cancellation.deduplicationId
            ?? "\(cancellation.provider.rawValue)_\(cancellation.productId)_\(expirationKey)"

        guard !hasCancellationFormBeenShown(userId: userId, entitlementId: cancellationKey) else {
            PaydirtLogger.shared.debug("Subscription", "Cancellation form already shown for \(cancellation.productId)")
            return
        }

        // Claim before asynchronous form lookup so simultaneous provider updates
        // cannot present duplicate forms. Release the claim when no form exists.
        markCancellationFormShown(userId: userId, entitlementId: cancellationKey)

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let formType = cancellation.isTrial ? "trial_expiration" : "cancellation"
            let preferredFormId = cancellation.isTrial
                ? trialCancellationFormId
                : cancellationFormId
            let formId = await self.resolveCancellationFormId(preferredFormId, type: formType)

            guard let formId = formId else {
                self.clearCancellationFormShown(userId: userId, entitlementId: cancellationKey)
                PaydirtLogger.shared.warning("Subscription", "No enabled \(formType) form is available")
                return
            }

            self.presentCancellationFormOnWindowWithFormId(
                formId,
                userId: cancellation.userId,
                metadata: self.subscriptionMetadata(for: cancellation)
            )
        }
    }

    private func resolveCancellationFormId(_ preferredId: String?, type: String) async -> String? {
        if let preferredId = preferredId { return preferredId }
        guard let apiKey = apiKey else { return nil }
        let client = PaydirtAPIClient(apiKey: apiKey, baseURL: baseURL)
        return try? await client.getForm(type: type)?.id
    }

    private func subscriptionMetadata(
        for cancellation: PaydirtSubscriptionCancellation
    ) -> [String: Any] {
        let isoFormatter = ISO8601DateFormatter()
        var subscription = cancellation.additionalMetadata
        subscription.merge([
            "provider": cancellation.provider.rawValue,
            "feedback_type": cancellation.isTrial ? "trial_cancellation" : "subscription_cancellation",
            "product_id": cancellation.productId,
            "period_type": cancellation.periodType,
            "will_renew": false,
        ]) { _, requiredValue in requiredValue }

        if let value = cancellation.entitlementId {
            subscription["entitlement_id"] = value
        }
        if let value = cancellation.userId ?? currentUserId {
            subscription["app_user_id"] = value
        }
        if let value = cancellation.localizedPrice {
            subscription["localized_price"] = value
        }
        if let value = cancellation.catalogPrice {
            subscription["catalog_price"] = value
        }
        if let value = cancellation.currencyCode {
            subscription["currency_code"] = value
        }
        if let value = cancellation.billingPeriod {
            subscription["billing_period"] = value
        }
        if let value = cancellation.expirationDate {
            subscription["expiration_date"] = isoFormatter.string(from: value)
        }
        if let value = cancellation.cancellationDetectedAt {
            subscription["cancellation_detected_at"] = isoFormatter.string(from: value)
        }

        return [
            "source": "\(cancellation.provider.rawValue)_cancellation",
            "subscription": subscription,
        ]
    }
}
