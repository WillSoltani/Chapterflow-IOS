import Foundation

/// Privacy-safe readiness of services whose construction depends on local app
/// configuration. These booleans describe readiness only; they never carry a
/// URL, identifier, credential, token, or error payload.
public struct AppSubsystemReadiness: Equatable, Sendable {
    public let networking: Bool
    public let authentication: Bool
    public let storeKit: Bool
    public let crashReporting: Bool
    public let appStoreDestination: Bool

    public init(
        networking: Bool,
        authentication: Bool,
        storeKit: Bool,
        crashReporting: Bool,
        appStoreDestination: Bool
    ) {
        self.networking = networking
        self.authentication = authentication
        self.storeKit = storeKit
        self.crashReporting = crashReporting
        self.appStoreDestination = appStoreDestination
    }
}

/// Result of attempting the one-per-emitter validated-configuration diagnostic.
public enum AppConfigurationDiagnosticEmission: Equatable, Sendable {
    case emitted
    case duplicateSuppressed
    case invalidConfiguration
}

/// Explicit access boundary for diagnostics that must not be exposed to App
/// Store production users. The default is fail-closed.
public enum InternalDiagnosticsAccess: Equatable, Sendable {
    case disabled
    case internalBuild
    case testFlight

    /// Resolves access without retaining or reporting the receipt URL. A
    /// sandbox receipt is treated as TestFlight/StoreKit-test distribution;
    /// nonproduction environments are internal; unknown and App Store
    /// production fail closed.
    public static func resolve(
        environment: AppEnvironment,
        appStoreReceiptURL: URL?
    ) -> InternalDiagnosticsAccess {
        if appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return .testFlight
        }
        switch environment {
        case .development, .staging:
            return .internalBuild
        case .production, .unknown:
            return .disabled
        }
    }

    fileprivate var permitsStoreKitDiagnostics: Bool {
        switch self {
        case .disabled:
            false
        case .internalBuild, .testFlight:
            true
        }
    }
}

/// Coarse server-verification health derived from a real verification attempt.
/// `notChecked` is the required initial state: configuration validation must
/// never trigger an eager backend probe.
public enum StoreKitVerificationEndpointHealth: String, Equatable, Sendable {
    case notChecked = "not_checked"
    case healthy
    case unavailable
}

/// StoreKit diagnostics for an internal or TestFlight diagnostics surface.
/// Product identifiers are nonsecret release-manifest values and make a
/// missing App Store product actionable. Transaction and account data are not
/// representable.
public struct StoreKitDiagnosticsRecord: Equatable, Sendable {
    public let configuredProductIDs: [String]
    public let loadedProductIDs: [String]
    public let verificationEndpointHealth: StoreKitVerificationEndpointHealth

    public var configuredProductCount: Int { configuredProductIDs.count }
    public var loadedProductCount: Int { loadedProductIDs.count }

    public init(
        configuredProductIDs: [String],
        loadedProductIDs: [String],
        verificationEndpointHealth: StoreKitVerificationEndpointHealth
    ) {
        self.configuredProductIDs = Array(Set(configuredProductIDs)).sorted()
        self.loadedProductIDs = Array(Set(loadedProductIDs)).sorted()
        self.verificationEndpointHealth = verificationEndpointHealth
    }
}

/// Minimal boundary PaywallFeature can depend on without knowing which
/// diagnostics actor retains the internal/TestFlight record.
public protocol StoreKitDiagnosticsRecording: Sendable {
    @discardableResult
    func recordStoreKitDiagnostics(_ record: StoreKitDiagnosticsRecord) async -> Bool
}

/// Serializes release diagnostics so repeated lifecycle callbacks cannot emit
/// duplicate configuration events or expose internal StoreKit status in an App
/// Store build.
///
/// Retain one instance for the app process. Invalid configuration does not
/// consume the one-shot, allowing a corrected injected configuration in tests
/// or internal tooling to be recorded later.
public actor AppConfigurationDiagnosticsEmitter: StoreKitDiagnosticsRecording {
    private let analytics: any AnalyticsClient
    private var internalAccess: InternalDiagnosticsAccess
    private var didEmitValidatedConfiguration = false
    private var storeKitRecord: StoreKitDiagnosticsRecord?

    public init(
        analytics: any AnalyticsClient,
        internalAccess: InternalDiagnosticsAccess = .disabled
    ) {
        self.analytics = analytics
        self.internalAccess = internalAccess
    }

    /// Emits exactly one allowlisted event after `AppConfig` validation succeeds.
    /// No service or network operation is started by this method.
    @discardableResult
    public func emitValidatedConfiguration(
        _ config: AppConfig,
        readiness: AppSubsystemReadiness
    ) -> AppConfigurationDiagnosticEmission {
        guard case .valid = config.validate() else {
            return .invalidConfiguration
        }
        guard !didEmitValidatedConfiguration else {
            return .duplicateSuppressed
        }

        didEmitValidatedConfiguration = true
        analytics.track(.appConfigurationValidated(
            environment: config.environment,
            bundleIdentifier: config.bundleIdentifier,
            version: config.marketingVersion,
            readiness: readiness
        ))
        return .emitted
    }

    /// Stores the latest redacted StoreKit health snapshot for an internal or
    /// TestFlight diagnostics surface. Recording is rejected until validated
    /// configuration has been emitted, and it never performs a backend call.
    @discardableResult
    public func recordStoreKitDiagnostics(_ record: StoreKitDiagnosticsRecord) async -> Bool {
        guard didEmitValidatedConfiguration,
              internalAccess.permitsStoreKitDiagnostics else {
            return false
        }
        storeKitRecord = record
        return true
    }

    /// Applies a distribution decision made from a verified StoreKit app
    /// transaction. Disabling access immediately clears any retained internal
    /// record so production users cannot inherit a prior diagnostic snapshot.
    public func updateInternalAccess(_ access: InternalDiagnosticsAccess) {
        internalAccess = access
        if access == .disabled {
            storeKitRecord = nil
        }
    }

    /// Returns no record in App Store production mode.
    public func latestStoreKitDiagnostics() -> StoreKitDiagnosticsRecord? {
        guard internalAccess.permitsStoreKitDiagnostics else { return nil }
        return storeKitRecord
    }
}
