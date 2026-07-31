import Foundation
import Paydirt
import SwiftUI
import UIKit

/// Compile-time contract for the installation paths coding agents generate.
/// These functions are never executed by CI; a successful build proves that
/// current public snippets remain compatible with the SDK and provider pins.
enum PaydirtIntegrationSmoke {
    static func configure() {
        Paydirt.configure(apiKey: "pk_live_fixture", theme: .automatic)
        Paydirt.setUserId("fixture-user")
        Paydirt.setLogLevel(.warning)
        Paydirt.prefetchForms(
            formIds: ["feedback-form-id"],
            types: ["cancellation", "trial_expiration"]
        )
    }

    static func manualSwiftUIFeedback() -> AnyView {
        Paydirt.showForm(
            formId: "feedback-form-id",
            metadata: ["source": "settings"]
        ) { result in
            _ = result.responseId
            _ = result.messages
        }
    }

    static func manualUIKitFeedback() {
        Paydirt.presentForm(
            formId: "feedback-form-id",
            metadata: ["source": "settings"]
        ) { result in
            _ = result.formId
        }
    }

    static func nativeStoreKitCancellation() {
        Paydirt.enableStoreKitIntegration(
            productIds: ["com.example.pro.monthly"],
            cancellationFormId: "paid-cancellation-form-id",
            trialCancellationFormId: "trial-cancellation-form-id",
            userId: "fixture-user"
        )
    }

    static func customBillingCancellation(isTrial: Bool) {
        Paydirt.handleSubscriptionCancellation(
            PaydirtSubscriptionCancellation(
                provider: .custom,
                productId: "com.example.pro.monthly",
                entitlementId: "pro",
                userId: "fixture-user",
                isTrial: isTrial,
                localizedPrice: "$9.99/month",
                catalogPrice: 9.99,
                currencyCode: "USD",
                billingPeriod: "1 month",
                deduplicationId: "fixture-cancellation",
                additionalMetadata: ["source": "account_screen"]
            ),
            cancellationFormId: "paid-cancellation-form-id",
            trialCancellationFormId: "trial-cancellation-form-id"
        )
    }

    static func thirdPartyProviderAdapters() {
        Paydirt.shared.enableRevenueCatIntegration(
            cancellationFormId: "paid-cancellation-form-id",
            trialCancellationFormId: "trial-cancellation-form-id"
        )
        PaydirtSuperwallAdapter.shared.start(
            cancellationFormId: "paid-cancellation-form-id",
            trialCancellationFormId: "trial-cancellation-form-id"
        )
    }
}
