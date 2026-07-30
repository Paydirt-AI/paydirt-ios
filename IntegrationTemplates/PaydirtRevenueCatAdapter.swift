import Foundation
import Paydirt
import RevenueCat
import UIKit

/// Copy this file into a RevenueCat host app. The coding agent should call
/// `start` after both RevenueCat and Paydirt are configured.
final class PaydirtRevenueCatAdapter: NSObject, PurchasesDelegate {
    static let shared = PaydirtRevenueCatAdapter()

    private weak var originalDelegate: PurchasesDelegate?
    private var cancellationFormId: String?
    private var trialCancellationFormId: String?
    private var foregroundObserver: NSObjectProtocol?

    func start(
        cancellationFormId: String,
        trialCancellationFormId: String
    ) {
        self.cancellationFormId = cancellationFormId
        self.trialCancellationFormId = trialCancellationFormId
        originalDelegate = Purchases.shared.delegate
        Purchases.shared.delegate = self

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

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        originalDelegate?.purchases?(purchases, receivedUpdated: customerInfo)
        handle(customerInfo)
    }

    private func refresh() {
        Task {
            guard let customerInfo = try? await Purchases.shared.customerInfo() else { return }
            handle(customerInfo)
        }
    }

    private func handle(_ customerInfo: CustomerInfo) {
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

        guard let entitlement = cancelled.first else { return }

        Task {
            let product = await Purchases.shared.products([entitlement.productIdentifier]).first
            let isTrial = entitlement.periodType == .trial
            let expirationKey = entitlement.expirationDate.map {
                String(Int($0.timeIntervalSince1970))
            } ?? "unknown"

            var details: [String: Any] = [
                "store": String(describing: entitlement.store),
                "is_sandbox": entitlement.isSandbox,
                "ownership_type": String(describing: entitlement.ownershipType),
            ]
            if let value = entitlement.latestPurchaseDate {
                details["latest_purchase_date"] = ISO8601DateFormatter().string(from: value)
            }
            if let value = entitlement.originalPurchaseDate {
                details["original_purchase_date"] = ISO8601DateFormatter().string(from: value)
            }
            if !cancelled.dropFirst().isEmpty {
                details["other_cancelled_product_ids"] = cancelled.dropFirst().map(\.productIdentifier)
            }

            Paydirt.handleSubscriptionCancellation(
                PaydirtSubscriptionCancellation(
                    provider: .revenueCat,
                    productId: entitlement.productIdentifier,
                    entitlementId: entitlement.identifier,
                    userId: customerInfo.originalAppUserId,
                    isTrial: isTrial,
                    periodType: Self.periodTypeName(entitlement.periodType),
                    localizedPrice: product?.localizedPriceString,
                    catalogPrice: product.map { NSDecimalNumber(decimal: $0.price).doubleValue },
                    currencyCode: product?.currencyCode,
                    billingPeriod: product?.subscriptionPeriod.map(Self.billingPeriod),
                    expirationDate: entitlement.expirationDate,
                    cancellationDetectedAt: entitlement.unsubscribeDetectedAt,
                    deduplicationId: "revenuecat_\(entitlement.productIdentifier)_\(expirationKey)",
                    additionalMetadata: details
                ),
                cancellationFormId: cancellationFormId,
                trialCancellationFormId: trialCancellationFormId
            )
        }
    }

    private static func periodTypeName(_ type: PeriodType) -> String {
        switch type {
        case .trial: return "Trial"
        case .intro: return "Intro"
        case .normal: return "Normal"
        case .prepaid: return "Prepaid"
        @unknown default: return "Unknown"
        }
    }

    private static func billingPeriod(_ period: SubscriptionPeriod) -> String {
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
