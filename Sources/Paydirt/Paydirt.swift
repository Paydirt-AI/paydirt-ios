//
// Paydirt.swift
// Voice AI cancellation forms for subscription apps
//

import SwiftUI
import RevenueCat

/// Main interface for Paydirt SDK
/// Configure with API key, then present feedback forms
public final class Paydirt: NSObject {
    public static let shared = Paydirt()

    private var apiKey: String?
    private var baseURL: String = "https://api.paydirt.ai"
    private var revenueCatEnabled = false
    private var cancellationFormId: String?
    private var currentUserId: String?

    private override init() {
        super.init()
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
        PaydirtLogger.shared.info("SDK", "Paydirt SDK v1.2.1 configured")
    }

    /// Enable automatic RevenueCat integration
    /// SDK will listen for subscription cancellation events and show appropriate form
    /// - Parameter cancellationFormId: Optional form ID to use (defaults to fetching cancellation type)
    public func enableRevenueCatIntegration(cancellationFormId: String? = nil) {
        guard apiKey != nil else {
            PaydirtLogger.shared.error("SDK", "Must configure SDK before enabling RevenueCat")
            return
        }

        self.cancellationFormId = cancellationFormId
        revenueCatEnabled = true

        // Add self as delegate to RevenueCat
        Purchases.shared.delegate = self

        PaydirtLogger.shared.info("SDK", "RevenueCat integration enabled")
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
    ) -> some View {
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
    ) -> some View {
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

    /// Internal method to present cancellation form when RevenueCat detects cancellation
    internal func presentCancellationFormOnWindow() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            PaydirtLogger.shared.error("SDK", "Could not find root view controller")
            return
        }

        let hostingController = UIHostingController(
            rootView: showCancellationForm(
                userId: currentUserId,
                metadata: ["source": "revenuecat_cancellation"],
                onCompletion: { completed in
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

// MARK: - RevenueCat Delegate
extension Paydirt: PurchasesDelegate {
    public func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        // Check if user has cancelled subscription
        // We detect cancellation by looking at expiration intent or management URL changes

        guard revenueCatEnabled else { return }

        // Get the app user ID
        self.currentUserId = customerInfo.originalAppUserId

        // Check for active subscriptions that are set to expire (cancelled)
        for entitlement in customerInfo.entitlements.active.values {
            if let expirationDate = entitlement.expirationDate,
               entitlement.willRenew == false,
               expirationDate > Date() {
                // User has cancelled but still has active subscription
                PaydirtLogger.shared.info("RevenueCat", "Detected subscription cancellation")

                // Present cancellation form
                DispatchQueue.main.async {
                    self.presentCancellationFormOnWindow()
                }

                // Only show once per cancellation
                break
            }
        }
    }
}

