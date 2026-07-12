import Foundation
import CoreKit
import Networking
import Testing
@testable import PaywallFeature

@Suite("StoreKit authoritative processing")
struct StoreKitAuthoritativeProcessingTests {
    private let config = StoreKitConfig(
        monthlyProductID: "com.cf.monthly",
        annualProductID: "com.cf.annual"
    )

    @Test(
        "processed active transaction preserves the authoritative Pro source",
        arguments: ["admin", "license", "gift_code", "flow_points", "future_source"]
    )
    func processedActivePreservesAuthoritativeSource(
        _ proSource: String
    ) async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        let response = """
        {
          "ok": true,
          "processed": true,
          "transactionState": "active",
          "entitlement": {
            "plan": "PRO",
            "proStatus": "active",
            "proSource": "\(proSource)",
            "currentPeriodEnd": null,
            "cancelAtPeriodEnd": false
          }
        }
        """
        await apiClient.setStub(
            .success(Data(response.utf8)),
            for: "/book/me/billing/apple/verify"
        )
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)
        let stream = await service.entitlementChanges()

        let result = try await service.processVerifiedTransaction(
            transactionID: 5,
            productID: "com.cf.monthly",
            appAccountToken: accountToken,
            jwsRepresentation: "test-transaction-jws",
            finish: { await finishRecorder.record() }
        )

        #expect(result == .activeProcessed(proSource: proSource))
        #expect(await apiClient.recordedEndpoints.count == 1)
        #expect(await finishRecorder.finishCount == 1)
        #expect(await receivesEvent(in: stream))
    }

    @Test("processed active transaction without active Pro finishes but never grants")
    func processedActiveWithoutProFinishesWithoutGrant() async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        let response = """
        {
          "ok": true,
          "processed": true,
          "transactionState": "active",
          "entitlement": {
            "plan": "FREE",
            "proStatus": null,
            "proSource": null,
            "currentPeriodEnd": null,
            "cancelAtPeriodEnd": null
          }
        }
        """
        await apiClient.setStub(
            .success(Data(response.utf8)),
            for: "/book/me/billing/apple/verify"
        )
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)
        let stream = await service.entitlementChanges()

        do {
            _ = try await service.processVerifiedTransaction(
                transactionID: 6,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
            Issue.record("Expected processed transaction without active Pro to fail")
        } catch StoreKitServiceError.processedWithoutActiveEntitlement {
            // The acknowledgement is finishable, but cannot become a local grant.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await apiClient.recordedEndpoints.count == 1)
        #expect(await finishRecorder.finishCount == 1)
        #expect(await receivesEvent(in: stream))
    }

    @Test("unknown processed transaction state remains unfinished")
    func unknownProcessedStateDoesNotFinish() async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        let response = """
        {
          "ok": true,
          "processed": true,
          "transactionState": "future_state",
          "entitlement": {
            "plan": "PRO",
            "proStatus": "active",
            "proSource": "admin",
            "currentPeriodEnd": null,
            "cancelAtPeriodEnd": false
          }
        }
        """
        await apiClient.setStub(
            .success(Data(response.utf8)),
            for: "/book/me/billing/apple/verify"
        )
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)
        let stream = await service.entitlementChanges()

        await #expect(throws: AppError.self) {
            try await service.processVerifiedTransaction(
                transactionID: 7,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
        }

        #expect(await finishRecorder.finishCount == 0)
        #expect(!(await receivesEvent(in: stream)))
    }
}
