import Foundation
import Paydirt
import StoreKit
import SuperwallKit

/// Copy this file into a Superwall 4.10+ host app. Superwall's customer-info
/// stream supplies will-renew and trial state without requiring RevenueCat.
final class PaydirtSuperwallAdapter {
    static let shared = PaydirtSuperwallAdapter()

    private var observationTask: Task<Void, Never>?
    private var cancellationFormId: String?
    private var trialCancellationFormId: String?

    func start(
        cancellationFormId: String,
        trialCancellationFormId: String
    ) {
        self.cancellationFormId = cancellationFormId
        self.trialCancellationFormId = trialCancellationFormId
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            guard let self else { return }
            await handle(await Superwall.shared.getCustomerInfo())
            for await customerInfo in Superwall.shared.customerInfoStream {
                guard !Task.isCancelled else { return }
                await handle(customerInfo)
            }
        }
    }

    private func handle(_ customerInfo: CustomerInfo) async {
        let cancelled = customerInfo.subscriptions
            .filter { subscription in
                guard let expirationDate = subscription.expirationDate else { return false }
                return subscription.isActive
                    && !subscription.isRevoked
                    && !subscription.willRenew
                    && expirationDate > Date()
            }
            .sorted { $0.purchaseDate > $1.purchaseDate }

        guard let subscription = cancelled.first else { return }

        let products = try? await StoreKit.Product.products(for: [subscription.productId])
        let product = products?.first
        let isTrial = subscription.offerType == .trial
        let expirationKey = subscription.expirationDate.map {
            String(Int($0.timeIntervalSince1970))
        } ?? "unknown"

        var details: [String: Any] = [
            "transaction_id": subscription.transactionId,
            "store": String(describing: subscription.store),
            "is_in_grace_period": subscription.isInGracePeriod,
            "is_in_billing_retry_period": subscription.isInBillingRetryPeriod,
        ]
        if let value = subscription.subscriptionGroupId {
            details["subscription_group_id"] = value
        }
        if cancelled.count > 1 {
            details["other_cancelled_product_ids"] = cancelled.dropFirst().map(\.productId)
        }

        Paydirt.handleSubscriptionCancellation(
            PaydirtSubscriptionCancellation(
                provider: .superwall,
                productId: subscription.productId,
                entitlementId: subscription.subscriptionGroupId,
                userId: customerInfo.userId,
                isTrial: isTrial,
                periodType: isTrial ? "Trial" : "Normal",
                localizedPrice: product?.displayPrice,
                catalogPrice: product.map { NSDecimalNumber(decimal: $0.price).doubleValue },
                billingPeriod: product?.subscription.map {
                    Self.billingPeriod($0.subscriptionPeriod)
                },
                expirationDate: subscription.expirationDate,
                deduplicationId: "superwall_\(subscription.transactionId)_\(expirationKey)",
                additionalMetadata: details
            ),
            cancellationFormId: cancellationFormId,
            trialCancellationFormId: trialCancellationFormId
        )
    }

    private static func billingPeriod(_ period: StoreKit.Product.SubscriptionPeriod) -> String {
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        return "\(period.value) \(unit)"
    }
}
