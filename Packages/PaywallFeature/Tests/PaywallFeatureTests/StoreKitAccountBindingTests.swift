import Foundation
import CoreKit
import Networking
import StoreKit
import Testing
@testable import PaywallFeature

@Suite("StoreKit account binding")
struct StoreKitAccountBindingTests {
    private let config = StoreKitConfig(
        monthlyProductID: "com.cf.monthly",
        annualProductID: "com.cf.annual"
    )

    @Test("Cognito UUID becomes the exact opaque StoreKit token")
    func validSubjectCreatesBinding() throws {
        let expectedToken = try storeKitTestAccountToken()
        let binding = try #require(
            StoreKitAccountBinding(authenticatedSubject: storeKitTestAccountSubject)
        )

        #expect(binding.token == expectedToken)
        #expect(binding.purchaseOption == .appAccountToken(expectedToken))
    }

    @Test(
        "non-UUID subjects fail closed",
        arguments: ["", "user-123", "not/a/uuid"]
    )
    func invalidSubjectHasNoBinding(_ subject: String) {
        #expect(StoreKitAccountBinding(authenticatedSubject: subject) == nil)
    }

    @Test("backend account-binding codes map to allowlisted user guidance")
    func backendAccountErrorsHaveSafeCopy() {
        let signInCodes = [
            "account_token_required",
            "account_token_malformed",
            "account_identifier_unsupported",
        ]
        let otherAccountCodes = [
            "account_token_mismatch",
            "transaction_already_claimed",
        ]

        for code in signInCodes {
            #expect(
                PaywallModel.safeAppleVerificationMessage(for: code)
                    == "Please sign in again before managing purchases."
            )
        }
        for code in otherAccountCodes {
            let message = PaywallModel.safeAppleVerificationMessage(for: code)
            #expect(message.contains("another ChapterFlow account"))
            #expect(!message.contains(code))
        }
        let unknownMessage = PaywallModel.safeAppleVerificationMessage(
            for: "sensitive_user_transaction_value"
        )
        #expect(!unknownMessage.contains("sensitive"))
    }

    @Test("local transaction ownership is scoped and legacy IDs require backend authorization")
    func accountContextScopesTransactionOwnership() throws {
        let context = StoreKitAccountContext()
        let firstToken = try storeKitTestAccountToken()
        let secondSubject = "00000000-0000-4000-8000-000000000222"
        let secondToken = try #require(UUID(uuidString: secondSubject))

        #expect(!context.ownsTransaction(id: 200, appAccountToken: firstToken))
        #expect(context.activate(authenticatedSubject: storeKitTestAccountSubject))
        #expect(context.ownsTransaction(id: 200, appAccountToken: firstToken))
        #expect(!context.ownsTransaction(id: 200, appAccountToken: secondToken))
        #expect(!context.ownsTransaction(id: 200, appAccountToken: nil))

        let firstBinding = try #require(context.currentBinding())
        context.authorizeLegacyTransaction(200, for: firstBinding)
        #expect(context.ownsTransaction(id: 200, appAccountToken: nil))

        #expect(context.activate(authenticatedSubject: secondSubject))
        #expect(!context.ownsTransaction(id: 200, appAccountToken: nil))
        #expect(context.ownsTransaction(id: 200, appAccountToken: secondToken))

        #expect(context.activate(authenticatedSubject: storeKitTestAccountSubject))
        let returningBinding = try #require(context.currentBinding())
        #expect(returningBinding.token == firstBinding.token)
        #expect(returningBinding.sessionGeneration != firstBinding.sessionGeneration)

        context.deactivate()
        #expect(!context.ownsTransaction(id: 200, appAccountToken: firstToken))
    }

    @Test("every app-initiated purchase option set contains the account token")
    func purchaseOptionsRequireActiveBinding() async throws {
        let service = StoreKitService(apiClient: MockAPIClient(), config: config)

        await #expect(throws: StoreKitServiceError.self) {
            try await service.accountBoundPurchaseOptions()
        }

        let token = try activateStoreKitTestAccount(service)
        let options = try await service.accountBoundPurchaseOptions()
        #expect(options == [.appAccountToken(token)])

        service.deactivateAccount()
        await #expect(throws: StoreKitServiceError.self) {
            try await service.accountBoundPurchaseOptions()
        }
    }

    @Test("transaction without an active account is retained and never posted")
    func missingActiveAccountFailsBeforeBackend() async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        let service = StoreKitService(apiClient: apiClient, config: config)

        await #expect(throws: StoreKitServiceError.self) {
            try await service.processVerifiedTransaction(
                transactionID: 101,
                productID: "com.cf.monthly",
                appAccountToken: try storeKitTestAccountToken(),
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
        }

        #expect(await apiClient.recordedEndpoints.isEmpty)
        #expect(await finishRecorder.finishCount == 0)
    }

    @Test("mismatched transaction account is retained and never posted")
    func mismatchedAccountFailsBeforeBackend() async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        let service = StoreKitService(apiClient: apiClient, config: config)
        _ = try activateStoreKitTestAccount(service)
        let otherToken = try #require(
            UUID(uuidString: "00000000-0000-4000-8000-000000000222")
        )

        await #expect(throws: StoreKitServiceError.self) {
            try await service.processVerifiedTransaction(
                transactionID: 102,
                productID: "com.cf.monthly",
                appAccountToken: otherToken,
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
        }

        #expect(await apiClient.recordedEndpoints.isEmpty)
        #expect(await finishRecorder.finishCount == 0)
    }

    @Test("retained transaction succeeds only after its initiating account returns")
    func retainedTransactionCanReplayForInitiatingAccount() async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        await apiClient.setStub(
            .success(try appleVerificationFixture()),
            for: "/book/me/billing/apple/verify"
        )
        let service = StoreKitService(apiClient: apiClient, config: config)
        let initiatingToken = try storeKitTestAccountToken()
        let otherSubject = "00000000-0000-4000-8000-000000000222"
        #expect(service.activateAccount(authenticatedSubject: otherSubject))

        await #expect(throws: StoreKitServiceError.self) {
            try await service.processVerifiedTransaction(
                transactionID: 108,
                productID: "com.cf.monthly",
                appAccountToken: initiatingToken,
                jwsRepresentation: "retained-transaction-jws",
                finish: { await finishRecorder.record() }
            )
        }
        #expect(await apiClient.recordedEndpoints.isEmpty)
        #expect(await finishRecorder.finishCount == 0)

        #expect(service.activateAccount(authenticatedSubject: storeKitTestAccountSubject))
        let result = try await service.processVerifiedTransaction(
            transactionID: 108,
            productID: "com.cf.monthly",
            appAccountToken: initiatingToken,
            jwsRepresentation: "retained-transaction-jws",
            finish: { await finishRecorder.record() }
        )

        #expect(result == .activeProcessed(proSource: "apple"))
        #expect(await apiClient.recordedEndpoints.count == 1)
        #expect(await finishRecorder.finishCount == 1)
    }

    @Test("Family Sharing never becomes a first-party account grant")
    func familySharedTransactionFailsBeforeBackend() async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)

        await #expect(throws: StoreKitServiceError.self) {
            try await service.processVerifiedTransaction(
                transactionID: 103,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                ownershipType: .familyShared,
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
        }

        #expect(await apiClient.recordedEndpoints.isEmpty)
        #expect(await finishRecorder.finishCount == 0)
    }

    @Test("legacy nil token is delegated to the authoritative backend")
    func legacyTransactionCanUseExistingServerClaim() async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        await apiClient.setStub(
            .success(try appleVerificationFixture()),
            for: "/book/me/billing/apple/verify"
        )
        let service = StoreKitService(apiClient: apiClient, config: config)
        _ = try activateStoreKitTestAccount(service)

        let result = try await service.processVerifiedTransaction(
            transactionID: 104,
            productID: "com.cf.monthly",
            appAccountToken: nil,
            jwsRepresentation: "legacy-transaction-jws",
            finish: { await finishRecorder.record() }
        )

        #expect(result == .activeProcessed(proSource: "apple"))
        #expect(await apiClient.recordedEndpoints.count == 1)
        #expect(await finishRecorder.finishCount == 1)
    }

    @Test("account switch during verification finishes safely but never reports a local grant")
    func accountSwitchCannotGrantCurrentUI() async throws {
        let apiClient = GatedVerificationAPIClient(
            responseData: try appleVerificationFixture()
        )
        let finishRecorder = TransactionFinishRecorder()
        let service = StoreKitService(apiClient: apiClient, config: config)
        let firstToken = try activateStoreKitTestAccount(service)
        var requestIterator = apiClient.requestStarted.makeAsyncIterator()

        let processing = Task {
            try await service.processVerifiedTransaction(
                transactionID: 105,
                productID: "com.cf.monthly",
                appAccountToken: firstToken,
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
        }
        try #require(await requestIterator.next() != nil)

        let secondSubject = "00000000-0000-4000-8000-000000000222"
        #expect(service.activateAccount(authenticatedSubject: secondSubject))
        await apiClient.releaseRequests()

        do {
            _ = try await processing.value
            Issue.record("Expected account-change protection")
        } catch let error as StoreKitServiceError {
            guard case .accountChangedDuringVerification = error else {
                Issue.record("Unexpected StoreKit error: \(error)")
                return
            }
        }

        #expect(await apiClient.sendCount == 1)
        #expect(await finishRecorder.finishCount == 1)
    }

    @Test("A to B to A during tokenless verification cannot reuse the original account lease")
    func accountABACannotGrantOrAuthorizeLegacyTransaction() async throws {
        let apiClient = GatedVerificationAPIClient(
            responseData: try appleVerificationFixture()
        )
        let finishRecorder = TransactionFinishRecorder()
        let service = StoreKitService(apiClient: apiClient, config: config)
        #expect(service.activateAccount(authenticatedSubject: storeKitTestAccountSubject))
        var requestIterator = apiClient.requestStarted.makeAsyncIterator()

        let processing = Task {
            try await service.processVerifiedTransaction(
                transactionID: 109,
                productID: "com.cf.monthly",
                appAccountToken: nil,
                jwsRepresentation: "tokenless-aba-transaction-jws",
                finish: { await finishRecorder.record() }
            )
        }
        try #require(await requestIterator.next() != nil)

        #expect(service.activateAccount(
            authenticatedSubject: "00000000-0000-4000-8000-000000000222"
        ))
        #expect(service.activateAccount(authenticatedSubject: storeKitTestAccountSubject))
        await apiClient.releaseRequests()

        do {
            _ = try await processing.value
            Issue.record("Expected account-session lease protection")
        } catch let error as StoreKitServiceError {
            guard case .accountChangedDuringVerification = error else {
                Issue.record("Unexpected StoreKit error: \(error)")
                return
            }
        }

        #expect(await apiClient.sendCount == 1)
        #expect(await finishRecorder.finishCount == 1)
    }

    @Test("authoritative revoked acknowledgement finishes without granting")
    func terminalAcknowledgementFinishesWithoutGrant() async throws {
        let response = """
        {
          "ok": true,
          "processed": true,
          "transactionState": "revoked",
          "entitlement": {
            "plan": "FREE",
            "proStatus": "inactive",
            "currentPeriodEnd": null,
            "cancelAtPeriodEnd": false
          }
        }
        """
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        await apiClient.setStub(
            .success(Data(response.utf8)),
            for: "/book/me/billing/apple/verify"
        )
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)
        let stream = await service.entitlementChanges()

        let result = try await service.processVerifiedTransaction(
            transactionID: 106,
            productID: "com.cf.monthly",
            appAccountToken: accountToken,
            jwsRepresentation: "revoked-transaction-jws",
            finish: { await finishRecorder.record() }
        )

        #expect(result == .terminal)
        #expect(await finishRecorder.finishCount == 1)
        #expect(await receivesEvent(in: stream))
    }

    @Test("legacy success body without processed acknowledgement remains unfinished")
    func legacySuccessBodyFailsClosed() async throws {
        let response = """
        {
          "ok": true,
          "entitlement": {
            "plan": "PRO",
            "proStatus": "active",
            "proSource": "apple",
            "currentPeriodEnd": null,
            "cancelAtPeriodEnd": false
          }
        }
        """
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        await apiClient.setStub(
            .success(Data(response.utf8)),
            for: "/book/me/billing/apple/verify"
        )
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)

        await #expect(throws: AppError.self) {
            try await service.processVerifiedTransaction(
                transactionID: 107,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "legacy-response-jws",
                finish: { await finishRecorder.record() }
            )
        }

        #expect(await finishRecorder.finishCount == 0)
    }
}
