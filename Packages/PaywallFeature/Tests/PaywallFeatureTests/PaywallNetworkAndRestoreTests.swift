import Foundation
import Models
import Networking
import StoreKit
import Testing
@testable import PaywallFeature

@Suite("Paywall network and restore outcomes")
@MainActor
struct PaywallNetworkAndRestoreTests {
    @Test("product loading recognizes StoreKit's wrapped network error")
    func loadProductsWrappedStoreKitNetworkError() async {
        let service = StubStoreKitService(loadFailure: .storeKitNetwork)
        let model = PaywallModel(storeKitService: service, apiClient: MockAPIClient())

        await model.loadProducts()

        #expect(model.productAvailability == .networkUnavailable)
        #expect(model.productAvailability.canRetry)
        #expect(model.errorMessage == nil)
    }

    @Test("billing copy recognizes StoreKit's wrapped network error")
    func billingCopyForWrappedStoreKitNetworkError() {
        let error = StoreKitError.networkError(URLError(.timedOut))

        #expect(
            PaywallModel.safeBillingErrorMessage(for: error)
                == "We couldn't connect to the store. Check your connection and try again."
        )
    }

    @Test("restore with no authoritative entitlement reports no purchases")
    func restoreWithoutAuthoritativeEntitlement() async throws {
        let client = MockAPIClient()
        let response = EntitlementResponse(
            entitlement: Entitlement(
                plan: .free,
                proStatus: nil,
                proSource: nil,
                freeBookSlots: 2,
                unlockedBookIds: [],
                unlockedBooksCount: 0,
                remainingFreeStarts: 1,
                currentPeriodEnd: nil,
                cancelAtPeriodEnd: nil,
                licenseKey: nil,
                licenseExpiresAt: nil
            ),
            paywall: nil
        )
        try await client.setStub(response, for: "/book/me/entitlements")
        let model = PaywallModel(
            storeKitService: StubStoreKitService(),
            apiClient: client
        )

        await model.restorePurchases()

        let message = "No previous purchases were found for this ChapterFlow account."
        #expect(model.entitlementResolution == .resolvedFree)
        #expect(model.purchaseState == .failed(message))
        #expect(model.errorMessage == message)
    }
}
