import Testing
import Foundation
import CoreKit
import Networking
import Models
@testable import PaywallFeature

@Suite("StoreKitConfig")
struct StoreKitConfigTests {

    @Test("allProductIDs excludes empty strings")
    func allProductIDsExcludesEmpty() {
        let config = StoreKitConfig(
            monthlyProductID: "com.cf.monthly",
            annualProductID: "com.cf.annual",
            annualUpfrontProductID: ""
        )
        #expect(config.allProductIDs == ["com.cf.monthly", "com.cf.annual"])
    }

    @Test("unsupported upfront product is never added to the purchase catalog")
    func allProductIDsExcludesUnsupportedUpfrontProduct() {
        let config = StoreKitConfig(
            monthlyProductID: "com.cf.monthly",
            annualProductID: "com.cf.annual",
            annualUpfrontProductID: "com.cf.annual.upfront"
        )
        #expect(config.allProductIDs == ["com.cf.monthly", "com.cf.annual"])
        #expect(!config.isValid)
        #expect(config.validationIssues.contains(.unsupportedAnnualUpfrontProduct))
    }

    @Test("empty required IDs make configuration invalid")
    func emptyRequiredIDsInvalid() {
        let config = StoreKitConfig(
            monthlyProductID: "",
            annualProductID: "",
            annualUpfrontProductID: ""
        )
        #expect(config.allProductIDs.isEmpty)
        #expect(!config.isValid)
        #expect(config.validationIssues.contains(.missingMonthlyProduct))
        #expect(config.validationIssues.contains(.missingAnnualProduct))
    }

    @Test("valid configuration accepts an optional empty upfront ID")
    func validRequiredIDs() {
        let config = StoreKitConfig(
            monthlyProductID: "com.cf.monthly",
            annualProductID: "com.cf.annual"
        )
        #expect(config.isValid)
        #expect(config.validationIssues.isEmpty)
    }

    @Test("malformed and duplicate IDs are rejected")
    func malformedAndDuplicateIDs() {
        let malformed = StoreKitConfig(
            monthlyProductID: "monthly product",
            annualProductID: "com.cf.annual"
        )
        let duplicate = StoreKitConfig(
            monthlyProductID: "com.cf.shared",
            annualProductID: "com.cf.shared"
        )
        #expect(malformed.validationIssues.contains(.malformedProductID))
        #expect(duplicate.validationIssues.contains(.duplicateProductID))
    }

    @Test("from AppConfig reads storeKit product IDs")
    func fromAppConfig() {
        let appConfig = AppConfig(
            apiBaseURL: "https://api.example.com",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "pool",
            cognitoClientID: "client",
            storeKitMonthlyProductID: "com.example.monthly",
            storeKitAnnualProductID: "com.example.annual",
            storeKitAnnualUpfrontProductID: "com.example.upfront"
        )
        let config = StoreKitConfig.from(appConfig)
        #expect(config.monthlyProductID == "com.example.monthly")
        #expect(config.annualProductID == "com.example.annual")
        #expect(config.annualUpfrontProductID == "com.example.upfront")
        #expect(config.validationIssues.contains(.unsupportedAnnualUpfrontProduct))
    }
}

@Suite("StoreKitServiceError")
struct StoreKitServiceErrorTests {

    @Test("invalidConfiguration has a localizedDescription")
    func invalidConfigurationDescription() {
        let error = StoreKitServiceError.invalidConfiguration
        #expect(!(error.errorDescription ?? "").isEmpty)
    }

    @Test("noProductsFound has a localizedDescription")
    func noProductsFoundDescription() {
        let error = StoreKitServiceError.noProductsFound
        #expect(!(error.errorDescription ?? "").isEmpty)
    }

    @Test("productNotConfigured has a localizedDescription")
    func productNotConfiguredDescription() {
        let error = StoreKitServiceError.productNotConfigured
        #expect(!(error.errorDescription ?? "").isEmpty)
    }

    @Test("unverified has a localizedDescription")
    func unverifiedDescription() {
        struct SomeError: Error {}
        let error = StoreKitServiceError.unverified(SomeError())
        #expect(!(error.errorDescription ?? "").isEmpty)
    }

    @Test(
        "account and terminal safety errors have localized descriptions",
        arguments: [
            StoreKitServiceError.accountBindingUnavailable,
            .accountBindingMismatch,
            .accountChangedDuringVerification,
            .unsupportedOwnership,
            .transactionNotActive,
            .processedWithoutActiveEntitlement,
        ]
    )
    func accountSafetyDescription(_ error: StoreKitServiceError) {
        #expect(!(error.errorDescription ?? "").isEmpty)
    }
}

@Suite("Live entitlement repository")
struct LiveEntitlementRepositoryTests {
    @Test("Apple verify decodes the compact additive success contract")
    func verifyAppleTransactionDecodesCompactFixture() async throws {
        let client = MockAPIClient()
        let fixtureData = try appleVerificationFixture()
        let fixtureText = try #require(
            String(bytes: fixtureData, encoding: .utf8)
        )
        #expect(fixtureText.contains("futureTopLevelField"))
        #expect(fixtureText.contains("futureEntitlementField"))
        await client.setStub(
            .success(fixtureData),
            for: "/book/me/billing/apple/verify"
        )
        let repository = LiveEntitlementRepository(client: client)

        let response = try await repository.verifyAppleTransaction(
            "header.payload.signature"
        )

        #expect(response.authoritativeProIsActive)
        #expect(response.confirmsAuthoritativelyProcessed)
        #expect(response.transactionState == "active")
        #expect(response.entitlement.proSource == "apple")
        #expect(
            response.entitlement.currentPeriodEnd
                == "2026-08-11T12:00:00.000Z"
        )
        let endpoint = try #require(await client.recordedEndpoints.first)
        #expect(endpoint.path == "/book/me/billing/apple/verify")
        let body = try #require(endpoint.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        #expect(json == ["transactionJWS": "header.payload.signature"])
    }
}

@Suite("StoreKit transaction catalog guard")
struct StoreKitTransactionCatalogGuardTests {
    private let config = StoreKitConfig(
        monthlyProductID: "com.cf.monthly",
        annualProductID: "com.cf.annual"
    )

    @Test("out-of-catalog transaction is never posted or finished")
    func outOfCatalogTransactionIsIgnored() async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        let service = StoreKitService(apiClient: apiClient, config: config)

        let processed = try await service.processVerifiedTransaction(
            transactionID: 1,
            productID: "com.other.app.subscription",
            appAccountToken: nil,
            jwsRepresentation: "sensitive-transaction-jws",
            finish: { await finishRecorder.record() }
        )

        #expect(processed == .ignored)
        #expect(await apiClient.recordedEndpoints.isEmpty)
        #expect(!(await finishRecorder.didFinish))
    }

    @Test("audited backend fixture decodes, finishes, and broadcasts to every observer")
    func configuredTransactionIsProcessed() async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        let fixtureData = try appleVerificationFixture()
        let decoded = try JSONDecoder.chapterFlow.decode(
            ApplePurchaseVerificationResponse.self,
            from: fixtureData
        )
        #expect(decoded.authoritativeProIsActive)
        #expect(decoded.entitlement.currentPeriodEnd == "2026-08-11T12:00:00.000Z")
        #expect(decoded.entitlement.cancelAtPeriodEnd == false)

        await apiClient.setStub(
            .success(fixtureData),
            for: "/book/me/billing/apple/verify"
        )
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)
        let entitlementServiceStream = await service.entitlementChanges()
        let paywallModelStream = await service.entitlementChanges()

        let processed = try await service.processVerifiedTransaction(
            transactionID: 2,
            productID: "com.cf.monthly",
            appAccountToken: accountToken,
            jwsRepresentation: "test-transaction-jws",
            finish: { await finishRecorder.record() }
        )

        let endpoints = await apiClient.recordedEndpoints
        #expect(processed == .activeProcessed(proSource: "apple"))
        #expect(endpoints.map(\.path) == ["/book/me/billing/apple/verify"])
        #expect(await finishRecorder.finishCount == 1)
        #expect(await receivesEvent(in: entitlementServiceStream))
        #expect(await receivesEvent(in: paywallModelStream))
    }

    @Test("server error stays mapped and never finishes or broadcasts")
    func verificationErrorDoesNotFinish() async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        await apiClient.setStub(
            .failure(.server(code: "apple_verify_failed", message: "Rejected", requestId: "req-42")),
            for: "/book/me/billing/apple/verify"
        )
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)
        let stream = await service.entitlementChanges()

        do {
            _ = try await service.processVerifiedTransaction(
                transactionID: 3,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
            Issue.record("Expected the backend error to be preserved")
        } catch let AppError.server(code, _, requestId) {
            #expect(code == "apple_verify_failed")
            #expect(requestId == "req-42")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await finishRecorder.finishCount == 0)
        #expect(!(await receivesEvent(in: stream)))
    }

    @Test("non-authoritative 2xx acknowledgement fails closed")
    func invalidAcknowledgementDoesNotFinish() async throws {
        let apiClient = MockAPIClient()
        let finishRecorder = TransactionFinishRecorder()
        let response = """
        {
          "ok": false,
          "entitlement": {
            "plan": "PRO",
            "proStatus": "active",
            "proSource": "apple",
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
                transactionID: 4,
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

@Suite("StoreKit transaction processing safety")
struct StoreKitTransactionProcessingSafetyTests {
    private let config = StoreKitConfig(
        monthlyProductID: "com.cf.monthly",
        annualProductID: "com.cf.annual"
    )

    @Test("concurrent delivery of one transaction verifies and finishes once")
    func concurrentDuplicateTransactionIsCoalesced() async throws {
        let apiClient = GatedVerificationAPIClient(
            responseData: try appleVerificationFixture()
        )
        let finishRecorder = TransactionFinishRecorder()
        let service = StoreKitService(apiClient: apiClient, config: config)
        let accountToken = try activateStoreKitTestAccount(service)
        let entitlementStream = await service.entitlementChanges()
        var requestIterator = apiClient.requestStarted.makeAsyncIterator()

        let firstProcessing = Task {
            try await service.processVerifiedTransaction(
                transactionID: 42,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
        }
        try #require(await requestIterator.next() != nil)

        let duplicateProcessing = Task {
            try await service.processVerifiedTransaction(
                transactionID: 42,
                productID: "com.cf.monthly",
                appAccountToken: accountToken,
                jwsRepresentation: "test-transaction-jws",
                finish: { await finishRecorder.record() }
            )
        }

        var participantCount = 0
        for _ in 0..<1_000 {
            participantCount = await service.transactionProcessingParticipantCount(
                for: 42
            )
            if participantCount == 2 { break }
            await Task.yield()
        }
        try #require(participantCount == 2)

        await apiClient.releaseRequests()
        let firstResult = try await firstProcessing.value
        let duplicateResult = try await duplicateProcessing.value

        #expect(firstResult == .activeProcessed(proSource: "apple"))
        #expect(duplicateResult == .activeProcessed(proSource: "apple"))
        #expect(await apiClient.sendCount == 1)
        #expect(await finishRecorder.finishCount == 1)
        #expect(await receivesEvent(in: entitlementStream))
    }

    @Test("unverified current entitlement becomes an explicit failure")
    func unverifiedCurrentEntitlementFailsClosed() {
        let failure = StoreKitTransactionVerification.currentEntitlementError(
            underlyingError: TransactionVerificationTestError()
        )
        guard case .unverified = failure else {
            Issue.record("Expected an unverified StoreKit failure")
            return
        }
    }

    @Test("transaction listener does not retain its owner and is cancelled on deinit")
    func listenerLifetimeFollowsServiceLifetime() async throws {
        let lifecycleProbe = ListenerLifecycleProbe()
        let listenerTaskFactory: StoreKitTransactionListenerTaskFactory = { handler in
            Task {
                await lifecycleProbe.recordStarted()
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch is CancellationError {
                    await lifecycleProbe.recordCancelled()
                } catch {
                    Issue.record("Unexpected listener error: \(error)")
                }
                withExtendedLifetime(handler) {}
            }
        }

        var service: StoreKitService? = StoreKitService(
            apiClient: MockAPIClient(),
            config: config,
            listenerTaskFactory: listenerTaskFactory
        )
        try #require(await receivesEvent(in: lifecycleProbe.started, timeout: .seconds(1)))
        weak let weakService = service

        service = nil

        #expect(weakService == nil)
        #expect(await receivesEvent(in: lifecycleProbe.cancelled, timeout: .seconds(1)))
    }
}

@Suite("StoreKit diagnostics")
struct StoreKitDiagnosticsTests {
    @Test("invalid product configuration records a redacted unavailable product set")
    func invalidConfigurationRecord() async {
        let recorder = DiagnosticsRecorderSpy()
        let service = StoreKitService(
            apiClient: MockAPIClient(),
            config: StoreKitConfig(monthlyProductID: "", annualProductID: ""),
            diagnosticsRecorder: recorder
        )

        await #expect(throws: StoreKitServiceError.self) {
            try await service.loadProducts()
        }

        let record = await recorder.latestRecord()
        #expect(record?.configuredProductCount == 0)
        #expect(record?.loadedProductCount == 0)
        #expect(record?.configuredProductIDs.isEmpty == true)
        #expect(record?.loadedProductIDs.isEmpty == true)
        #expect(record?.verificationEndpointHealth == .notChecked)
    }

    @Test("verification health classification is conservative and cancellation-safe")
    func verificationHealthClassification() {
        #expect(StoreKitService.verificationEndpointHealth(after: AppError.offline) == .unavailable)
        #expect(StoreKitService.verificationEndpointHealth(after: AppError.verifierUnavailable) == .unavailable)
        #expect(StoreKitService.verificationEndpointHealth(after: AppError.notFound) == .unavailable)
        #expect(StoreKitService.verificationEndpointHealth(
            after: AppError.server(code: "temporary", message: "", requestId: nil)
        ) == .unavailable)
        #expect(StoreKitService.verificationEndpointHealth(
            after: AppError.decoding(DiagnosticsTestError())
        ) == .unavailable)
        #expect(StoreKitService.verificationEndpointHealth(after: AppError.rateLimited(retryAfter: nil)) == .healthy)
        #expect(StoreKitService.verificationEndpointHealth(after: AppError.forbidden) == .healthy)
        #expect(StoreKitService.verificationEndpointHealth(after: AppError.invalidInput("")) == .healthy)
        #expect(StoreKitService.verificationEndpointHealth(after: AppError.unauthenticated) == nil)
        #expect(StoreKitService.verificationEndpointHealth(after: AppError.reauthRequired) == nil)
        #expect(StoreKitService.verificationEndpointHealth(after: CancellationError()) == nil)
        #expect(StoreKitService.verificationEndpointHealth(after: DiagnosticsTestError()) == .unavailable)
    }

    @Test("server log codes are collapsed instead of exposing backend values")
    func serverLogCodeIsRedacted() {
        let sensitiveCode = "account_user@example.com_transaction_123"
        let code = StoreKitService.safeErrorCode(
            AppError.server(
                code: sensitiveCode,
                message: "sensitive message",
                requestId: "sensitive request"
            )
        )

        #expect(code == "server")
        #expect(!code.contains(sensitiveCode))
    }
}

private struct DiagnosticsTestError: Error {}

private actor DiagnosticsRecorderSpy: StoreKitDiagnosticsRecording {
    private var records: [StoreKitDiagnosticsRecord] = []

    func recordStoreKitDiagnostics(_ record: StoreKitDiagnosticsRecord) async -> Bool {
        records.append(record)
        return true
    }

    func latestRecord() -> StoreKitDiagnosticsRecord? {
        records.last
    }
}

actor TransactionFinishRecorder {
    private(set) var finishCount = 0
    private(set) var didFinish = false

    func record() {
        finishCount += 1
        didFinish = true
    }
}

actor GatedVerificationAPIClient: APIClientProtocol {
    nonisolated let requestStarted: AsyncStream<Void>

    private let requestStartedContinuation: AsyncStream<Void>.Continuation
    private let responseData: Data
    private var pendingRequests: [CheckedContinuation<Void, Never>] = []
    private(set) var sendCount = 0

    init(responseData: Data) {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        requestStarted = stream
        requestStartedContinuation = continuation
        self.responseData = responseData
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint
    ) async throws -> Response {
        sendCount += 1
        requestStartedContinuation.yield(())
        await withCheckedContinuation { continuation in
            pendingRequests.append(continuation)
        }
        return try JSONDecoder.chapterFlow.decode(Response.self, from: responseData)
    }

    func releaseRequests() {
        let requests = pendingRequests
        pendingRequests.removeAll()
        for request in requests {
            request.resume()
        }
    }
}

private actor ListenerLifecycleProbe {
    nonisolated let started: AsyncStream<Void>
    nonisolated let cancelled: AsyncStream<Void>

    private let startedContinuation: AsyncStream<Void>.Continuation
    private let cancelledContinuation: AsyncStream<Void>.Continuation

    init() {
        (started, startedContinuation) = AsyncStream<Void>.makeStream()
        (cancelled, cancelledContinuation) = AsyncStream<Void>.makeStream()
    }

    func recordStarted() {
        startedContinuation.yield(())
    }

    func recordCancelled() {
        cancelledContinuation.yield(())
    }
}

private struct TransactionVerificationTestError: Error {}

private enum ContractFixtureError: Error {
    case missingAppleVerificationFixture
}

func appleVerificationFixture() throws -> Data {
    guard let url = Bundle.module.url(
        forResource: "apple_verify_success",
        withExtension: "json",
        subdirectory: "Fixtures"
    ) else {
        throw ContractFixtureError.missingAppleVerificationFixture
    }
    return try Data(contentsOf: url)
}

func receivesEvent(
    in stream: AsyncStream<Void>,
    timeout: Duration = .milliseconds(100)
) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next() != nil
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return false
        }
        let received = await group.next() ?? false
        group.cancelAll()
        return received
    }
}
