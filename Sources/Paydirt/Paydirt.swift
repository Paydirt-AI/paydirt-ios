//
// Paydirt.swift
// Voice AI cancellation forms for subscription apps
//

import SwiftUI

#if canImport(RevenueCat)
import RevenueCat
#endif

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
    private var currentUserId: String?

    // Strong reference to prevent delegate wrapper from being deallocated
    #if canImport(RevenueCat)
    private var delegateWrapper: PaydirtPurchasesDelegate?
    #endif

    private override init() {
        super.init()
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
        baseURL: String? = nil
    ) {
        self.apiKey = apiKey
        if let baseURL = baseURL {
            self.baseURL = baseURL
        }
        PaydirtLogger.shared.info("SDK", "Paydirt SDK v1.2.3 configured")

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
    public func enableRevenueCatIntegration(cancellationFormId: String? = nil) {
        guard apiKey != nil else {
            PaydirtLogger.shared.error("SDK", "Must configure SDK before enabling RevenueCat")
            return
        }

        self.cancellationFormId = cancellationFormId
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

        if existingDelegate != nil {
            PaydirtLogger.shared.info("SDK", "RevenueCat integration enabled (preserving existing delegate)")
        } else {
            PaydirtLogger.shared.info("SDK", "RevenueCat integration enabled")
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
        onCompletion: @escaping (Bool) -> Void = { _ in }
    ) -> AnyView {
        guard let apiKey = apiKey else {
            PaydirtLogger.shared.error("SDK", "API key not configured")
            return AnyView(PaydirtErrorView(message: "SDK not configured", onDismiss: {}))
        }

        return AnyView(PaydirtFormContainer(
            formId: formId,
            userId: userId ?? currentUserId,
            metadata: metadata,
            apiKey: apiKey,
            baseURL: baseURL,
            onCompletion: onCompletion
        ))
    }

    /// Convenience method to show cancellation form
    /// Fetches the form with type "cancellation" automatically
    public func showCancellationForm(
        userId: String? = nil,
        metadata: [String: Any]? = nil,
        onCompletion: @escaping (Bool) -> Void = { _ in }
    ) -> AnyView {
        guard let apiKey = apiKey else {
            return AnyView(PaydirtErrorView(message: "SDK not configured", onDismiss: {}))
        }

        return AnyView(PaydirtCancellationContainer(
            userId: userId ?? currentUserId,
            metadata: metadata,
            apiKey: apiKey,
            baseURL: baseURL,
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
        onCompletion: @escaping (Bool) -> Void = { _ in }
    ) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            PaydirtLogger.shared.error("SDK", "Could not find root view controller")
            return
        }

        var hostingController: UIHostingController<AnyView>!
        hostingController = UIHostingController(
            rootView: showForm(
                formId: formId,
                userId: userId,
                metadata: metadata,
                onCompletion: { completed in
                    hostingController.dismiss(animated: true)
                    onCompletion(completed)
                }
            )
        )

        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = .clear

        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }

        topController.present(hostingController, animated: true)
    }

    /// Internal method to present cancellation form when RevenueCat detects cancellation
    internal func presentCancellationFormOnWindow() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
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

        // Find the top-most presented controller
        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }

        topController.present(hostingController, animated: true)
    }
}

// MARK: - RevenueCat Delegate Handling
#if canImport(RevenueCat)
extension Paydirt {
    /// Internal method called by PaydirtPurchasesDelegate wrapper when customer info updates
    /// This method handles Paydirt's cancellation detection logic
    internal func handleCustomerInfoUpdate(_ customerInfo: CustomerInfo) {
        // Check if user has cancelled subscription
        // We detect cancellation by looking at expiration intent or management URL changes

        guard revenueCatEnabled else { return }

        // Get the app user ID
        let userId = customerInfo.originalAppUserId
        self.currentUserId = userId

        // Check for active subscriptions
        for entitlement in customerInfo.entitlements.active.values {
            let entitlementId = entitlement.identifier

            // Check if user has resubscribed (willRenew is true)
            // If so, clear the shown flag so we can show form again if they cancel later
            if entitlement.willRenew == true {
                clearCancellationFormShown(userId: userId, entitlementId: entitlementId)
                continue
            }

            // Check for cancelled subscription that hasn't expired yet
            if let expirationDate = entitlement.expirationDate,
               entitlement.willRenew == false,
               expirationDate > Date() {

                // Check if we've already shown the form for this cancellation
                if hasCancellationFormBeenShown(userId: userId, entitlementId: entitlementId) {
                    PaydirtLogger.shared.debug("RevenueCat", "Cancellation form already shown for \(entitlementId)")
                    continue
                }

                // User has cancelled but still has active subscription - show form
                PaydirtLogger.shared.info("RevenueCat", "Detected subscription cancellation")

                // Mark as shown BEFORE presenting to prevent race conditions
                markCancellationFormShown(userId: userId, entitlementId: entitlementId)

                // Present cancellation form
                DispatchQueue.main.async {
                    self.presentCancellationFormOnWindow()
                }

                // Only show once per delegate callback (still break to avoid showing multiple forms)
                break
            }
        }
    }
}
#endif
