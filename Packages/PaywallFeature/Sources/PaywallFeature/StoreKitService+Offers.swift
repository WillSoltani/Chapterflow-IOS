import CoreKit
import StoreKit

extension StoreKitService {
    public func introOfferEligibleProductIDs() async -> Set<String> {
        let ids = config.allProductIDs
        guard !ids.isEmpty else { return [] }
        let products = (try? await Product.products(for: ids)) ?? []
        var eligible = Set<String>()
        for product in products {
            guard let subscription = product.subscription else { continue }
            if await subscription.isEligibleForIntroOffer {
                eligible.insert(product.id)
            }
        }
        return eligible
    }

    public func winBackDisplayInfo() async -> WinBackDisplayInfo? {
        let ids = config.allProductIDs
        guard !ids.isEmpty else { return nil }
        let products = (try? await Product.products(for: ids)) ?? []
        await authorizeTokenlessSubscriptionHistory(in: products)

        for product in products {
            guard let subscription = product.subscription else { continue }
            let availableOffers = subscription.winBackOffers
            guard !availableOffers.isEmpty else { continue }

            let statuses = (try? await product.subscription?.status) ?? []
            var eligibleOfferIDs: [String] = []
            for status in statuses {
                guard case .verified(let transaction) = status.transaction,
                      accountContext.ownsTransaction(
                        id: transaction.id,
                        appAccountToken: transaction.appAccountToken
                      ),
                      case .verified(let renewalInfo) = status.renewalInfo else { continue }
                eligibleOfferIDs.append(contentsOf: renewalInfo.eligibleWinBackOfferIDs)
            }

            guard let bestID = eligibleOfferIDs.first,
                  let offer = availableOffers.first(where: { $0.id == bestID })
            else { continue }

            return WinBackDisplayInfo(product: product, offer: offer)
        }
        return nil
    }

    public func purchaseWithWinBack(
        productID: String,
        offerID: String
    ) async throws -> PurchaseResult {
        guard config.allProductIDs.contains(productID) else {
            log.warning("Win-back purchase rejected because the product is outside the configured catalog")
            throw StoreKitServiceError.productNotConfigured
        }
        let products = (try? await Product.products(for: [productID])) ?? []
        guard let product = products.first(where: { $0.id == productID }),
              let offer = product.subscription?.winBackOffers.first(where: { $0.id == offerID })
        else { throw StoreKitServiceError.noProductsFound }

        var options = try accountBoundPurchaseOptions()
        options.insert(.winBackOffer(offer))
        let result = try await product.purchase(options: options)
        switch result {
        case .success(let verificationResult):
            switch verificationResult {
            case .unverified(_, let error):
                log.warning("Win-back purchase returned unverified transaction — not granting Pro")
                throw StoreKitServiceError.unverified(error)
            case .verified:
                return try await purchaseResult(for: handleVerifiedResult(verificationResult))
            }
        case .pending:
            log.info("Win-back purchase is pending (Ask to Buy or SCA)")
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            return .userCancelled
        }
    }

    /// Revalidates tokenless status history after a new app/account session.
    /// A same-account reverse map on the backend is still mandatory; first
    /// claims and cross-account claims remain rejected there.
    func authorizeTokenlessSubscriptionHistory(in products: [Product]) async {
        for product in products {
            guard let statuses = try? await product.subscription?.status else { continue }
            for status in statuses {
                guard case .verified(let transaction) = status.transaction,
                      transaction.appAccountToken == nil,
                      !accountContext.ownsTransaction(
                        id: transaction.id,
                        appAccountToken: nil
                      ) else { continue }
                do {
                    _ = try await handleVerifiedResult(
                        status.transaction,
                        broadcastsTerminalRejection: false,
                        broadcastsEntitlementChange: false
                    )
                } catch {
                    log.warning(
                        "Tokenless subscription history authorization failed: \(Self.safeErrorCode(error))"
                    )
                }
            }
        }
    }
}
