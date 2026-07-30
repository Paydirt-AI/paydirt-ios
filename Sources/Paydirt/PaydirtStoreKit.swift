import Foundation
import StoreKit
#if canImport(UIKit)
import UIKit

/// Native StoreKit 2 cancellation detection for apps which do not use a
/// third-party subscription manager.
public extension Paydirt {
    static func enableStoreKitIntegration(
        productIds: [String],
        cancellationFormId: String? = nil,
        trialCancellationFormId: String? = nil,
        userId: String? = nil
    ) {
        shared.enableStoreKitIntegration(
            productIds: productIds,
            cancellationFormId: cancellationFormId,
            trialCancellationFormId: trialCancellationFormId,
            userId: userId
        )
    }

    func enableStoreKitIntegration(
        productIds: [String],
        cancellationFormId: String? = nil,
        trialCancellationFormId: String? = nil,
        userId: String? = nil
    ) {
        let uniqueProductIds = Array(Set(productIds)).sorted()
        guard !uniqueProductIds.isEmpty else {
            PaydirtLogger.shared.warning("StoreKit", "At least one subscription product ID is required")
            return
        }

        storeKitCancellationMonitor = PaydirtStoreKitCancellationMonitor(
            paydirt: self,
            productIds: uniqueProductIds,
            cancellationFormId: cancellationFormId,
            trialCancellationFormId: trialCancellationFormId,
            userId: userId
        )
        storeKitCancellationMonitor?.start()
        PaydirtLogger.shared.info("StoreKit", "Native StoreKit cancellation detection enabled")
    }
}

internal final class PaydirtStoreKitCancellationMonitor {
    private weak var paydirt: Paydirt?
    private let productIds: [String]
    private let cancellationFormId: String?
    private let trialCancellationFormId: String?
    private let userId: String?
    private var foregroundObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?

    init(
        paydirt: Paydirt,
        productIds: [String],
        cancellationFormId: String?,
        trialCancellationFormId: String?,
        userId: String?
    ) {
        self.paydirt = paydirt
        self.productIds = productIds
        self.cancellationFormId = cancellationFormId
        self.trialCancellationFormId = trialCancellationFormId
        self.userId = userId
    }

    deinit {
        refreshTask?.cancel()
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    func start() {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshSubscriptionStatus()
        }
    }

    private func refreshSubscriptionStatus() async {
        do {
            let products = try await Product.products(for: productIds)
            for product in products {
                guard !Task.isCancelled, let subscription = product.subscription else { continue }

                for status in try await subscription.status {
                    guard
                        case .verified(let transaction) = status.transaction,
                        case .verified(let renewalInfo) = status.renewalInfo,
                        let expirationDate = transaction.expirationDate,
                        expirationDate > Date(),
                        !renewalInfo.willAutoRenew
                    else {
                        continue
                    }

                    let usedIntroOffer = transaction.offerType == .introductory
                    let isFreeTrial = usedIntroOffer
                        && subscription.introductoryOffer?.paymentMode == .freeTrial
                    let expirationKey = String(Int(expirationDate.timeIntervalSince1970))
                    let billingPeriod = Self.billingPeriod(subscription.subscriptionPeriod)

                    let cancellation = PaydirtSubscriptionCancellation(
                        provider: .storeKit,
                        productId: transaction.productID,
                        entitlementId: subscription.subscriptionGroupID,
                        userId: userId,
                        isTrial: isFreeTrial,
                        periodType: isFreeTrial ? "Trial" : (usedIntroOffer ? "Intro" : "Normal"),
                        localizedPrice: product.displayPrice,
                        catalogPrice: NSDecimalNumber(decimal: product.price).doubleValue,
                        billingPeriod: billingPeriod,
                        expirationDate: expirationDate,
                        deduplicationId: "storekit_\(transaction.originalID)_\(expirationKey)",
                        additionalMetadata: [
                            "transaction_id": String(transaction.id),
                            "original_transaction_id": String(transaction.originalID),
                            "subscription_group_id": subscription.subscriptionGroupID,
                            "store": "app_store",
                        ]
                    )

                    paydirt?.handleSubscriptionCancellation(
                        cancellation,
                        cancellationFormId: cancellationFormId,
                        trialCancellationFormId: trialCancellationFormId
                    )
                }
            }
        } catch {
            PaydirtLogger.shared.warning("StoreKit", "Could not refresh subscription status")
        }
    }

    private static func billingPeriod(_ period: Product.SubscriptionPeriod) -> String {
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
#else
internal final class PaydirtStoreKitCancellationMonitor {}
#endif
