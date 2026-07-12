import Foundation
import Testing
@testable import CoreKit

@Suite("App configuration diagnostics")
struct AppConfigurationDiagnosticsTests {
    @Test("validated configuration emits exactly once with only allowlisted properties")
    func emitsExactlyOnce() async throws {
        let analytics = StreamingAnalyticsClient()
        let emitter = AppConfigurationDiagnosticsEmitter(analytics: analytics)
        let config = validConfig()
        let readiness = AppSubsystemReadiness(
            networking: true,
            authentication: true,
            storeKit: false,
            crashReporting: false,
            appStoreDestination: false
        )

        let first = await emitter.emitValidatedConfiguration(config, readiness: readiness)
        let second = await emitter.emitValidatedConfiguration(config, readiness: readiness)

        #expect(first == .emitted)
        #expect(second == .duplicateSuppressed)
        let events = await analytics.capturedEvents()
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.name == "app_configuration_validated")
        #expect(event.properties == [
            "environment": "development",
            "bundleId": "com.chapterflow.ios.dev",
            "version": "1.2.3",
            "networkingReady": "true",
            "authenticationReady": "true",
            "storeKitReady": "false",
            "crashReportingReady": "false",
            "appStoreDestinationReady": "false"
        ])

        let encodedProperties = event.properties.values.joined(separator: " ")
        #expect(!encodedProperties.contains(config.apiBaseURL))
        #expect(!encodedProperties.contains(config.cognitoUserPoolID))
        #expect(!encodedProperties.contains(config.cognitoClientID))
        #expect(!encodedProperties.contains(config.sentryDSN))
        #expect(!encodedProperties.contains(config.storeKitMonthlyProductID))
        #expect(!encodedProperties.contains(config.storeKitAnnualProductID))
    }

    @Test("invalid configuration is not emitted and does not consume the one-shot")
    func invalidConfigurationDoesNotConsumeEmission() async {
        let analytics = StreamingAnalyticsClient()
        let emitter = AppConfigurationDiagnosticsEmitter(analytics: analytics)
        let readiness = readySubsystems()
        let invalid = AppConfig(
            apiBaseURL: "",
            cognitoRegion: "",
            cognitoUserPoolID: "",
            cognitoClientID: ""
        )

        let rejected = await emitter.emitValidatedConfiguration(invalid, readiness: readiness)
        let accepted = await emitter.emitValidatedConfiguration(validConfig(), readiness: readiness)
        let events = await analytics.capturedEvents()

        #expect(rejected == .invalidConfiguration)
        #expect(accepted == .emitted)
        #expect(events.count == 1)
    }

    @Test("StoreKit diagnostics cannot be recorded before configuration validation")
    func storeKitDiagnosticsRequireValidation() async {
        let emitter = AppConfigurationDiagnosticsEmitter(
            analytics: NoopAnalyticsClient(),
            internalAccess: .internalBuild
        )
        let record = StoreKitDiagnosticsRecord(
            configuredProductIDs: ["com.chapterflow.pro.monthly", "com.chapterflow.pro.annual"],
            loadedProductIDs: [],
            verificationEndpointHealth: .notChecked
        )

        let recorded = await emitter.recordStoreKitDiagnostics(record)

        #expect(!recorded)
        #expect(await emitter.latestStoreKitDiagnostics() == nil)
    }

    @Test("StoreKit diagnostics stay unavailable when internal access is disabled")
    func storeKitDiagnosticsFailClosed() async {
        let emitter = AppConfigurationDiagnosticsEmitter(analytics: NoopAnalyticsClient())
        _ = await emitter.emitValidatedConfiguration(validConfig(), readiness: readySubsystems())
        let record = StoreKitDiagnosticsRecord(
            configuredProductIDs: ["com.chapterflow.pro.monthly", "com.chapterflow.pro.annual"],
            loadedProductIDs: ["com.chapterflow.pro.monthly", "com.chapterflow.pro.annual"],
            verificationEndpointHealth: .healthy
        )

        let recorded = await emitter.recordStoreKitDiagnostics(record)

        #expect(!recorded)
        #expect(await emitter.latestStoreKitDiagnostics() == nil)
    }

    @Test("verified distribution access can enable and then clear diagnostics")
    func distributionAccessUpdate() async {
        let emitter = AppConfigurationDiagnosticsEmitter(analytics: NoopAnalyticsClient())
        _ = await emitter.emitValidatedConfiguration(validConfig(), readiness: readySubsystems())
        let record = StoreKitDiagnosticsRecord(
            configuredProductIDs: ["com.chapterflow.pro.monthly", "com.chapterflow.pro.annual"],
            loadedProductIDs: ["com.chapterflow.pro.monthly"],
            verificationEndpointHealth: .healthy
        )

        await emitter.updateInternalAccess(.testFlight)
        #expect(await emitter.recordStoreKitDiagnostics(record))
        #expect(await emitter.latestStoreKitDiagnostics() == record)

        await emitter.updateInternalAccess(.disabled)
        #expect(await emitter.latestStoreKitDiagnostics() == nil)
    }

    @Test(
        "StoreKit diagnostics are available only in internal and TestFlight distributions",
        arguments: [InternalDiagnosticsAccess.internalBuild, .testFlight]
    )
    func storeKitDiagnosticsAreDistributionGated(access: InternalDiagnosticsAccess) async {
        let emitter = AppConfigurationDiagnosticsEmitter(
            analytics: NoopAnalyticsClient(),
            internalAccess: access
        )
        let recorder: any StoreKitDiagnosticsRecording = emitter
        _ = await emitter.emitValidatedConfiguration(validConfig(), readiness: readySubsystems())
        let record = StoreKitDiagnosticsRecord(
            configuredProductIDs: ["com.chapterflow.pro.monthly", "com.chapterflow.pro.annual"],
            loadedProductIDs: ["com.chapterflow.pro.monthly"],
            verificationEndpointHealth: .unavailable
        )

        let recorded = await recorder.recordStoreKitDiagnostics(record)

        #expect(recorded)
        #expect(await emitter.latestStoreKitDiagnostics() == record)
    }

    @Test("StoreKit diagnostics normalize product identifiers deterministically")
    func storeKitDiagnosticsNormalizeProductIDs() {
        let record = StoreKitDiagnosticsRecord(
            configuredProductIDs: ["b", "a", "a"],
            loadedProductIDs: ["b", "b"],
            verificationEndpointHealth: .notChecked
        )

        #expect(record.configuredProductIDs == ["a", "b"])
        #expect(record.loadedProductIDs == ["b"])
        #expect(record.configuredProductCount == 2)
        #expect(record.loadedProductCount == 1)
    }

    @Test(
        "diagnostics access resolves from environment and receipt without exposing receipt data",
        arguments: [
            (AppEnvironment.development, nil, InternalDiagnosticsAccess.internalBuild),
            (.staging, nil, .internalBuild),
            (.production, nil, .disabled),
            (.unknown, nil, .disabled),
            (.production, URL(fileURLWithPath: "/receipt/sandboxReceipt"), .testFlight)
        ]
    )
    func resolvesDiagnosticsAccess(
        environment: AppEnvironment,
        receiptURL: URL?,
        expected: InternalDiagnosticsAccess
    ) {
        #expect(InternalDiagnosticsAccess.resolve(
            environment: environment,
            appStoreReceiptURL: receiptURL
        ) == expected)
    }

    private func validConfig() -> AppConfig {
        AppConfig(
            apiBaseURL: "https://api.chapterflow.ca",
            cognitoRegion: "ca-central-1",
            cognitoUserPoolID: "ca-central-1_Abc123",
            cognitoClientID: "clientid1234567890",
            cognitoDomain: "auth.chapterflow.ca",
            sentryDSN: "https://publickey@o123.ingest.sentry.io/456",
            storeKitMonthlyProductID: "com.chapterflow.dev.monthly",
            storeKitAnnualProductID: "com.chapterflow.dev.annual",
            environment: .development,
            bundleIdentifier: "com.chapterflow.ios.dev",
            sentryPolicy: .enabled,
            buildConfiguration: "Debug",
            buildCommitSHA: "abc1234",
            marketingVersion: "1.2.3",
            buildNumber: "42"
        )
    }

    private func readySubsystems() -> AppSubsystemReadiness {
        AppSubsystemReadiness(
            networking: true,
            authentication: true,
            storeKit: true,
            crashReporting: true,
            appStoreDestination: true
        )
    }
}

/// A parallel-safe, fully Sendable analytics test double. `AsyncStream` gives
/// synchronous `track` a deterministic capture channel with no shared globals.
private struct StreamingAnalyticsClient: AnalyticsClient {
    private let stream: AsyncStream<AnalyticsEvent>
    private let continuation: AsyncStream<AnalyticsEvent>.Continuation

    init() {
        let channel = AsyncStream.makeStream(of: AnalyticsEvent.self)
        stream = channel.stream
        continuation = channel.continuation
    }

    func track(_ event: AnalyticsEvent) {
        continuation.yield(event)
    }

    func beacon(_ name: String, properties: [String: String]) {}
    func flush() async {}

    func capturedEvents() async -> [AnalyticsEvent] {
        continuation.finish()
        var events: [AnalyticsEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }
}
