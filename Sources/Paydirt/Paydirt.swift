//
// Paydirt.swift
// Voice AI cancellation forms for subscription apps
//

import SwiftUI

#if canImport(RevenueCat)
import RevenueCat
#endif

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

// MARK: - RevenueCat Delegate Wrapper Class
// This wrapper preserves the host app's existing RevenueCat delegate while
// allowing Paydirt to also receive callbacks. When RevenueCat sends updates,
// this wrapper forwards to both the original delegate and Paydirt.
#if canImport(RevenueCat)
private class PaydirtPurchasesDelegate: NSObject, PurchasesDelegate {
    weak var originalDelegate: PurchasesDelegate?
    weak var paydirt: Paydirt?

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        // Forward to original delegate first (host app's delegate)
        originalDelegate?.purchases?(purchases, receivedUpdated: customerInfo)

        // Then let Paydirt handle it
        paydirt?.handleCustomerInfoUpdate(customerInfo)
    }
}
#endif

/// Main interface for Paydirt SDK
/// Configure with API key, then present feedback forms
public final class Paydirt: NSObject {
    public static let shared = Paydirt()

    private var apiKey: String?
    private var baseURL: String = "https://api.paydirt.ai"
    private var revenueCatEnabled = false
    private var cancellationFormId: String?
    private var trialCancellationFormId: String?
    private var currentUserId: String?
    private var theme: PaydirtTheme = .automatic

    // Strong reference to prevent delegate wrapper from being deallocated
    #if canImport(RevenueCat)
    private var delegateWrapper: PaydirtPurchasesDelegate?
    private var revenueCatForegroundObserver: NSObjectProtocol?
    #endif

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

    #if canImport(RevenueCat)
    public static func enableRevenueCatIntegration(
        cancellationFormId: String? = nil,
        trialCancellationFormId: String? = nil
    ) {
        shared.enableRevenueCatIntegration(
            cancellationFormId: cancellationFormId,
            trialCancellationFormId: trialCancellationFormId
        )
    }
    #endif

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
        PaydirtLogger.shared.info("SDK", "Paydirt SDK v1.4.0 configured")

        // Retry any pending submissions from previous sessions
        let apiClient = PaydirtAPIClient(apiKey: apiKey, baseURL: self.baseURL)
        Task {
            await PendingSubmissionStore.shared.retryPending(using: apiClient)
        }
    }

    // MARK: - RevenueCat Integration (Optional)

    #if canImport(RevenueCat)
    /// Enable automatic RevenueCat integration
    /// SDK will listen for subscription cancellation events and show appropriate form
    /// - Parameter cancellationFormId: Optional form ID to use (defaults to fetching cancellation type)
    ///
    /// Note: This method preserves any existing RevenueCat delegate. If your app has already
    /// set Purchases.shared.delegate before calling this method, your delegate will continue
    /// to receive callbacks alongside Paydirt.
    public func enableRevenueCatIntegration(
        cancellationFormId: String? = nil,
        trialCancellationFormId: String? = nil
    ) {
        guard apiKey != nil else {
            PaydirtLogger.shared.error("SDK", "Must configure SDK before enabling RevenueCat")
            return
        }

        self.cancellationFormId = cancellationFormId
        self.trialCancellationFormId = trialCancellationFormId
        revenueCatEnabled = true

        // Capture existing delegate before overwriting (delegate forwarding pattern)
        // This ensures the host app's delegate still receives callbacks
        let existingDelegate = Purchases.shared.delegate

        // Create wrapper that forwards to both original delegate and Paydirt
        let wrapper = PaydirtPurchasesDelegate()
        wrapper.originalDelegate = existingDelegate
        wrapper.paydirt = self

        // Store strong reference to prevent deallocation
        self.delegateWrapper = wrapper

        // Set wrapper as the delegate
        Purchases.shared.delegate = wrapper

        if let observer = revenueCatForegroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        revenueCatForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshRevenueCatCustomerInfo()
        }

        // Delegate updates are only received after RevenueCat performs an
        // outbound request. Refresh immediately and whenever the app becomes
        // active so cancellations made outside the app are detected.
        refreshRevenueCatCustomerInfo()

        if existingDelegate != nil {
            PaydirtLogger.shared.info("SDK", "RevenueCat integration enabled (preserving existing delegate)")
        } else {
            PaydirtLogger.shared.info("SDK", "RevenueCat integration enabled")
        }
    }

    private func refreshRevenueCatCustomerInfo() {
        guard revenueCatEnabled else { return }
        Task {
            do {
                let customerInfo = try await Purchases.shared.customerInfo()
                handleCustomerInfoUpdate(customerInfo)
            } catch {
                PaydirtLogger.shared.warning("RevenueCat", "Could not refresh CustomerInfo")
            }
        }
    }
    #endif

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

    /// Internal method to present cancellation form when RevenueCat detects cancellation
    internal func presentCancellationFormOnWindow() {
        guard let rootViewController = resolveRootViewController() else {
            PaydirtLogger.shared.error("SDK", "Could not find root view controller")
            return
        }

        var hostingController: UIHostingController<AnyView>!
        hostingController = UIHostingController(
            rootView: showCancellationForm(
                userId: currentUserId,
                metadata: ["source": "revenuecat_cancellation"],
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

    private func presentCancellationFormOnWindowWithFormId(
        _ formId: String,
        metadata: [String: Any] = ["source": "revenuecat_cancellation"]
    ) {
        guard let rootViewController = resolveRootViewController() else {
            PaydirtLogger.shared.error("SDK", "Could not find root view controller")
            return
        }

        var hostingController: UIHostingController<AnyView>!
        hostingController = UIHostingController(
            rootView: showForm(
                formId: formId,
                userId: currentUserId,
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
}

// MARK: - RevenueCat Delegate Handling
#if canImport(RevenueCat)
extension Paydirt {
    /// Internal method called by PaydirtPurchasesDelegate wrapper when customer info updates
    /// This method handles Paydirt's cancellation detection logic
    internal func handleCustomerInfoUpdate(_ customerInfo: CustomerInfo) {
        guard revenueCatEnabled else { return }

        let userId = customerInfo.originalAppUserId
        self.currentUserId = userId

        let cancelled = customerInfo.entitlements.active.values
            .filter { entitlement in
                guard let expirationDate = entitlement.expirationDate else { return false }
                return !entitlement.willRenew && expirationDate > Date()
            }
            .sorted { lhs, rhs in
                let left = lhs.unsubscribeDetectedAt ?? lhs.expirationDate ?? .distantPast
                let right = rhs.unsubscribeDetectedAt ?? rhs.expirationDate ?? .distantPast
                return left > right
            }

        guard let entitlement = cancelled.first else {
            // Clear legacy per-entitlement flags for subscriptions which renew.
            for renewing in customerInfo.entitlements.active.values where renewing.willRenew {
                clearCancellationFormShown(userId: userId, entitlementId: renewing.identifier)
            }
            return
        }

        let expirationKey = entitlement.expirationDate.map {
            String(Int($0.timeIntervalSince1970))
        } ?? "unknown"
        let cancellationKey = "\(entitlement.identifier)_\(entitlement.productIdentifier)_\(expirationKey)"

        guard !hasCancellationFormBeenShown(userId: userId, entitlementId: cancellationKey) else {
            PaydirtLogger.shared.debug("RevenueCat", "Cancellation form already shown for \(entitlement.productIdentifier)")
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let isTrial = entitlement.periodType == .trial
            let formType = isTrial ? "trial_expiration" : "cancellation"
            let preferredFormId = isTrial ? self.trialCancellationFormId : self.cancellationFormId
            let formId = await self.resolveRevenueCatFormId(preferredFormId, type: formType)

            guard let formId = formId else {
                PaydirtLogger.shared.warning("RevenueCat", "No enabled \(formType) form is available")
                return
            }

            let metadata = await self.revenueCatMetadata(
                customerInfo: customerInfo,
                entitlement: entitlement,
                feedbackType: isTrial ? "trial_cancellation" : "subscription_cancellation",
                otherCancelledProductIds: cancelled.dropFirst().map(\.productIdentifier)
            )

            // Mark immediately before presentation to prevent duplicate delegate
            // callbacks from opening multiple copies of the same cancellation.
            self.markCancellationFormShown(userId: userId, entitlementId: cancellationKey)
            self.presentCancellationFormOnWindowWithFormId(formId, metadata: metadata)
        }
    }

    private func resolveRevenueCatFormId(_ preferredId: String?, type: String) async -> String? {
        if let preferredId = preferredId { return preferredId }
        guard let apiKey = apiKey else { return nil }
        let client = PaydirtAPIClient(apiKey: apiKey, baseURL: baseURL)
        return try? await client.getForm(type: type)?.id
    }

    private func revenueCatMetadata(
        customerInfo: CustomerInfo,
        entitlement: EntitlementInfo,
        feedbackType: String,
        otherCancelledProductIds: [String]
    ) async -> [String: Any] {
        let isoFormatter = ISO8601DateFormatter()
        let product = await Purchases.shared.products([entitlement.productIdentifier]).first

        var revenueCat: [String: Any] = [
            "feedback_type": feedbackType,
            "app_user_id": customerInfo.originalAppUserId,
            "entitlement_id": entitlement.identifier,
            "product_id": entitlement.productIdentifier,
            "period_type": periodTypeName(entitlement.periodType),
            "will_renew": entitlement.willRenew,
            "store": String(describing: entitlement.store),
            "is_sandbox": entitlement.isSandbox,
            "ownership_type": String(describing: entitlement.ownershipType),
        ]

        if !otherCancelledProductIds.isEmpty {
            revenueCat["other_cancelled_product_ids"] = otherCancelledProductIds
        }
        if let date = entitlement.latestPurchaseDate {
            revenueCat["latest_purchase_date"] = isoFormatter.string(from: date)
        }
        if let date = entitlement.originalPurchaseDate {
            revenueCat["original_purchase_date"] = isoFormatter.string(from: date)
        }
        if let date = entitlement.expirationDate {
            revenueCat["expiration_date"] = isoFormatter.string(from: date)
        }
        if let date = entitlement.unsubscribeDetectedAt {
            revenueCat["unsubscribe_detected_at"] = isoFormatter.string(from: date)
        }
        if let date = entitlement.billingIssueDetectedAt {
            revenueCat["billing_issue_detected_at"] = isoFormatter.string(from: date)
        }
        if let planIdentifier = entitlement.productPlanIdentifier {
            revenueCat["product_plan_id"] = planIdentifier
        }
        if let product = product {
            revenueCat["catalog_price"] = NSDecimalNumber(decimal: product.price).doubleValue
            revenueCat["localized_price"] = product.localizedPriceString
            if let currencyCode = product.currencyCode {
                revenueCat["currency_code"] = currencyCode
            }
            if let period = product.subscriptionPeriod {
                revenueCat["billing_period"] = "\(period.value) \(periodUnitName(period.unit))"
            }
        }

        return [
            "source": "revenuecat_cancellation",
            "revenuecat": revenueCat,
        ]
    }

    private func periodTypeName(_ type: PeriodType) -> String {
        switch type {
        case .trial: return "Trial"
        case .intro: return "Intro"
        case .normal: return "Normal"
        case .prepaid: return "Prepaid"
        @unknown default: return "Unknown"
        }
    }

    private func periodUnitName(_ unit: SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "period"
        }
    }
}
#endif
