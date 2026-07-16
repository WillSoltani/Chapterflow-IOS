import AuthKit
import CoreKit
import DesignSystem
import Persistence
import SwiftUI

/// A privacy-safe required-session bootstrap failure.
public struct AppBootstrapSessionFailure: Equatable, Sendable {
    public static let supportCode = "CF-BOOT-SESSION-001"

    public init() {}

    public var supportCode: String { Self.supportCode }
}

/// Closed launch state. Exactly one configured graph is published only after
/// configuration validation, required storage, and required session setup pass.
@MainActor
public enum AppBootstrapState {
    case preparing
    case waitingForProtectedData(AppBootstrapStorageFailure)
    case ready(config: ValidatedAppConfig, model: AppModel)
    case invalidConfiguration(AppConfigurationDiagnosticRecord)
    case storageUnavailable(AppBootstrapStorageFailure)
    case sessionConfigurationFailed(AppBootstrapSessionFailure)
}

@MainActor
protocol AppGraphFactory {
    func makeConfiguredGraph(
        config: ValidatedAppConfig,
        persistence: AppPersistenceResources
    ) throws -> AppModel
}

@MainActor
struct LiveAppGraphFactory: AppGraphFactory {
    func makeConfiguredGraph(
        config: ValidatedAppConfig,
        persistence: AppPersistenceResources
    ) throws -> AppModel {
        // Configure the minimal session boundary before constructing services
        // such as reachability that start process-long observation in init.
        let authService: AuthService
        #if DEBUG
        if AppModel.isHermeticDeferredAuthUITest() {
            // The deferred-auth UI flow must never persist synthetic tokens to
            // Keychain. AuthService and SessionManager share this process-local
            // mirror while retaining the normal signed-out restoration path.
            authService = AuthService(
                config: config.value,
                tokenStore: InMemoryTokenStore()
            )
        } else {
            authService = AuthService(config: config.value)
        }
        #else
        authService = AuthService(config: config.value)
        #endif
        let session = SessionManager(authService: authService)
        try session.configure()

        let model = AppModel(
            config: config,
            persistence: persistence,
            authService: authService,
            session: session
        )
        model.activateRequiredServices()
        return model
    }
}

/// Owns the one live bootstrap attempt and prevents stale or duplicate attempts
/// from publishing an application graph.
@Observable
@MainActor
public final class AppBootstrapCoordinator {
    public private(set) var state: AppBootstrapState

    private let buildConfiguration: AppBuildConfiguration
    private let diagnostics: any AppConfigurationDiagnosticsRecording
    private let persistenceLoader: any AppPersistenceLoading
    private let graphFactory: any AppGraphFactory
    private let protectedDataAvailability: any ProtectedDataAvailabilityProviding
    private let phaseRecorder: any AppBootstrapPhaseRecording
    private let validatedConfig: ValidatedAppConfig?
    private var attempt: Task<Void, Never>?
    private var protectedDataWait: Task<Void, Never>?
    private var attemptGeneration: UInt = 0
    private var didRecordFirstLaunchView = false

    public convenience init(
        config: AppConfig,
        buildConfiguration: AppBuildConfiguration
    ) {
        self.init(
            config: config,
            buildConfiguration: buildConfiguration,
            diagnostics: NoopAppConfigurationDiagnosticsRecorder(),
            persistenceLoader: DefaultAppPersistenceLoader(),
            graphFactory: LiveAppGraphFactory(),
            protectedDataAvailability: SystemProtectedDataAvailabilityProvider(),
            phaseRecorder: SignpostAppBootstrapPhaseRecorder()
        )
    }

    init(
        config: AppConfig,
        buildConfiguration: AppBuildConfiguration,
        diagnostics: any AppConfigurationDiagnosticsRecording,
        persistenceLoader: any AppPersistenceLoading,
        graphFactory: any AppGraphFactory,
        protectedDataAvailability: any ProtectedDataAvailabilityProviding = SystemProtectedDataAvailabilityProvider(),
        phaseRecorder: any AppBootstrapPhaseRecording = NoopAppBootstrapPhaseRecorder()
    ) {
        self.buildConfiguration = buildConfiguration
        self.diagnostics = diagnostics
        self.persistenceLoader = persistenceLoader
        self.graphFactory = graphFactory
        self.protectedDataAvailability = protectedDataAvailability
        self.phaseRecorder = phaseRecorder
        _ = try? phaseRecorder.record(.bootstrapStarted)

        switch config.validate() {
        case .valid(let validated):
            validatedConfig = validated
            state = .preparing

        case .invalid(let issues):
            validatedConfig = nil
            let record = AppConfigurationDiagnosticRecord(
                status: .invalid,
                buildConfiguration: buildConfiguration,
                issues: issues,
                liveServicesConstructed: false
            )
            _ = try? diagnostics.record(record)
            state = .invalidConfiguration(record)
        }

        if case .invalidConfiguration = state {
            recordPhase(.invalidConfigurationFailed)
        }
    }

    isolated deinit {
        attempt?.cancel()
        protectedDataWait?.cancel()
    }

    /// Records the first available launch surface once, independently of which
    /// closed bootstrap state owns that frame.
    func markFirstLaunchViewAvailable() {
        guard !didRecordFirstLaunchView else { return }
        didRecordFirstLaunchView = true
        recordPhase(.firstLaunchViewAvailable)
    }

    /// Starts the initial attempt. Repeated starts while preparing, ready, or in
    /// a terminal state never create another task or graph.
    public func start() {
        guard case .preparing = state, attempt == nil else { return }
        beginAttempt()
    }

    /// Retries only recoverable bootstrap failures. The state changes to
    /// preparing synchronously so repeated taps cannot overlap attempts.
    public func retry() {
        switch state {
        case .storageUnavailable(let failure) where failure.isRetryMeaningful:
            state = .preparing
            beginAttempt()
        case .sessionConfigurationFailed:
            state = .preparing
            beginAttempt()
        case .preparing, .waitingForProtectedData, .ready,
             .invalidConfiguration, .storageUnavailable:
            break
        }
    }

    /// Cancels the owned attempt when the launch root leaves the hierarchy.
    public func cancel() {
        guard attempt != nil || protectedDataWait != nil else { return }
        attemptGeneration &+= 1
        attempt?.cancel()
        protectedDataWait?.cancel()
        attempt = nil
        protectedDataWait = nil
        if case .waitingForProtectedData = state {
            state = .preparing
        }
    }

    /// Awaitable test/view-lifetime hook for the currently owned attempt.
    func waitForCurrentAttempt() async {
        await attempt?.value
    }

    /// Atomically supersedes an active attempt. Generation checks guarantee a
    /// loader that ignores cancellation still cannot publish stale results.
    func restartActiveAttempt() {
        guard validatedConfig != nil else { return }
        state = .preparing
        beginAttempt(replacingCurrent: true)
    }

    private func beginAttempt(replacingCurrent: Bool = false) {
        guard let validatedConfig else { return }
        if replacingCurrent {
            attempt?.cancel()
            protectedDataWait?.cancel()
            attempt = nil
            protectedDataWait = nil
        } else {
            guard attempt == nil, protectedDataWait == nil else { return }
        }

        attemptGeneration &+= 1
        let generation = attemptGeneration
        guard protectedDataAvailability.isAvailable else {
            waitForProtectedData(generation: generation)
            return
        }

        state = .preparing
        recordPhase(.persistenceOpenStarted)
        let loader = persistenceLoader
        attempt = Task { @MainActor [weak self, loader] in
            do {
                let persistence = try await loader.load()
                try Task.checkCancellation()
                self?.finishStorageLoad(
                    persistence,
                    config: validatedConfig,
                    generation: generation
                )
            } catch let failure as AppPersistenceLoadFailure {
                self?.finishStorageFailure(failure, generation: generation)
            } catch is CancellationError {
                if Task.isCancelled {
                    self?.finishCancellation(generation: generation)
                } else {
                    self?.finishStorageFailure(nil, generation: generation)
                }
            } catch {
                self?.finishStorageFailure(nil, generation: generation)
            }
        }
    }

    private func finishStorageLoad(
        _ persistence: AppPersistenceResources,
        config: ValidatedAppConfig,
        generation: UInt
    ) {
        guard generation == attemptGeneration else { return }
        recordPhase(.persistenceOpenCompleted)
        recordPhase(.requiredSessionSetupStarted)

        do {
            let model = try graphFactory.makeConfiguredGraph(
                config: config,
                persistence: persistence
            )
            let record = AppConfigurationDiagnosticRecord(
                status: .valid,
                buildConfiguration: buildConfiguration,
                issues: [],
                liveServicesConstructed: true
            )
            _ = try? diagnostics.record(record)
            recordPhase(.requiredSessionSetupCompleted)
            attempt = nil
            state = .ready(config: config, model: model)
            recordPhase(.readyPublished)
        } catch {
            attempt = nil
            state = .sessionConfigurationFailed(AppBootstrapSessionFailure())
            recordPhase(.requiredSessionSetupFailed)
        }
    }

    private func finishStorageFailure(
        _ failure: AppPersistenceLoadFailure?,
        generation: UInt
    ) {
        guard generation == attemptGeneration else { return }

        if !protectedDataAvailability.isAvailable {
            attempt = nil
            waitForProtectedData(generation: generation)
            return
        }

        let category: AppBootstrapStorageFailureCategory
        let phase: AppBootstrapPhase
        switch failure {
        case .persistentStoreOpenOrMigration:
            category = .persistentStoreOpenOrMigration
            phase = .persistentStoreOpenOrMigrationFailed
        case .requiredFileStore:
            category = .requiredFileStore
            phase = .requiredFileStoreFailed
        case nil:
            category = .unavailable
            phase = .storageUnavailableFailed
        }
        attempt = nil
        state = .storageUnavailable(AppBootstrapStorageFailure(category: category))
        recordPhase(phase)
    }

    private func finishCancellation(generation: UInt) {
        guard generation == attemptGeneration else { return }
        attempt = nil
    }

    private func waitForProtectedData(generation: UInt) {
        guard generation == attemptGeneration, protectedDataWait == nil else { return }
        state = .waitingForProtectedData(
            AppBootstrapStorageFailure(category: .protectedDataUnavailable)
        )
        recordPhase(.protectedDataWaiting)

        let availability = protectedDataAvailability
        protectedDataWait = Task { @MainActor [weak self, availability] in
            await availability.waitUntilAvailable()
            guard !Task.isCancelled else { return }
            self?.protectedDataBecameAvailable(generation: generation)
        }
    }

    private func protectedDataBecameAvailable(generation: UInt) {
        guard generation == attemptGeneration,
              case .waitingForProtectedData = state,
              protectedDataAvailability.isAvailable else { return }
        protectedDataWait = nil
        state = .preparing
        recordPhase(.protectedDataBecameAvailable)
        beginAttempt()
    }

    private func recordPhase(_ phase: AppBootstrapPhase) {
        _ = try? phaseRecorder.record(phase)
    }
}

/// Root switch between a lightweight first frame, one configured application
/// graph, and dedicated actionable failure surfaces.
public struct ConfiguredAppRootView: View {
    private let bootstrap: AppBootstrapCoordinator

    public init(bootstrap: AppBootstrapCoordinator) {
        self.bootstrap = bootstrap
    }

    public var body: some View {
        ZStack {
            switch bootstrap.state {
            case .preparing:
                BootstrapPreparingView()

            case .waitingForProtectedData(let failure):
                ProtectedDataWaitingView(supportCode: failure.supportCode.rawValue)

            case .ready(let validated, let model):
                AppRootView(model: model)
                    .environment(\.appConfig, validated.value)

            case .invalidConfiguration(let diagnostic):
                InvalidDevelopmentConfigurationView(diagnostic: diagnostic)

            case .storageUnavailable(let failure):
                BootstrapFailureView(
                    kind: .storage,
                    supportCode: failure.supportCode.rawValue,
                    onRetry: bootstrap.retry
                )

            case .sessionConfigurationFailed(let failure):
                BootstrapFailureView(
                    kind: .session,
                    supportCode: failure.supportCode,
                    onRetry: bootstrap.retry
                )
            }
        }
        .task {
            bootstrap.markFirstLaunchViewAvailable()
            bootstrap.start()
            await bootstrap.waitForCurrentAttempt()
        }
        .onDisappear { bootstrap.cancel() }
    }
}

struct InvalidDevelopmentConfigurationView: View {
    let diagnostic: AppConfigurationDiagnosticRecord

    var body: some View {
        ZStack {
            Color.cfGroupedBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: .cfSpacing24) {
                    header
                    issueSummary
                    recoveryGuidance
                    supportCode
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, .cfSpacing20)
                .padding(.vertical, .cfSpacing32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("invalid-development-configuration")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Image(systemName: "gear.badge.xmark")
                .font(.largeTitle)
                .foregroundStyle(Color.cfAccent)
                .accessibilityHidden(true)

            Text(heading)
                .font(.cfTitle1)
                .foregroundStyle(Color.cfLabel)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("invalid-config-heading")

            Text(summary)
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .accessibilityIdentifier("invalid-config-summary")
        }
        .accessibilityElement(children: .contain)
    }

    private var issueSummary: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Text("Configuration issues")
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)
                .accessibilityAddTraits(.isHeader)

            ForEach(diagnostic.issues, id: \.self) { issue in
                Label {
                    Text(issue.safeSummary)
                        .font(.cfBody)
                        .foregroundStyle(Color.cfLabel)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Color.cfAccent)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("invalid-config-issue-\(issue.field.rawValue)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.cfSpacing16)
        .background(
            Color.cfSecondaryBackground,
            in: RoundedRectangle(cornerRadius: .cfRadius16, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    private var recoveryGuidance: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Text(guidanceHeading)
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)
                .accessibilityAddTraits(.isHeader)

            Text(guidance)
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("invalid-config-guidance")
    }

    private var isDebugBuild: Bool {
        diagnostic.buildConfiguration == .debug
    }

    private var heading: String {
        isDebugBuild ? "ChapterFlow Needs Setup" : "ChapterFlow Can't Start"
    }

    private var summary: String {
        if isDebugBuild {
            return "Required development services aren't configured. No network, account, analytics, StoreKit, or entitlement services were started."
        }
        return "This build is missing required configuration. No account or product services were started."
    }

    private var guidanceHeading: String {
        isDebugBuild ? "Local setup" : "Next step"
    }

    private var guidance: String {
        if isDebugBuild {
            return "Copy Secrets.example.xcconfig to Secrets.xcconfig, replace every example API and Cognito value with your authorized development configuration, then rebuild the app."
        }
        return "Contact ChapterFlow support and include the support code below."
    }

    private var supportCode: some View {
        Text("Support code: \(diagnostic.supportCode)")
            .font(.cfFootnote.monospaced())
            .foregroundStyle(Color.cfSecondaryLabel)
            .textSelection(.enabled)
            .accessibilityIdentifier("invalid-config-support-code")
    }
}

private extension AppConfigurationIssue {
    var safeSummary: String {
        "\(field.displayName): \(category.displayName)"
    }
}

private extension AppConfigurationField {
    var displayName: String {
        switch self {
        case .apiBaseURL:
            "API base URL"
        case .cognitoRegion:
            "Cognito region"
        case .cognitoUserPoolID:
            "Cognito user pool"
        case .cognitoClientID:
            "Cognito client"
        case .cognitoDomain:
            "Cognito domain"
        }
    }
}

private extension AppConfigurationIssueCategory {
    var displayName: String {
        switch self {
        case .missing:
            "missing"
        case .empty:
            "empty"
        case .unexpanded:
            "build setting not expanded"
        case .templateValue:
            "example value"
        case .placeholder:
            "placeholder value"
        case .malformed:
            "invalid format"
        case .insecureTransport:
            "secure HTTPS required"
        case .regionMismatch:
            "region does not match"
        }
    }
}

#if DEBUG
#Preview("Invalid development configuration — light") {
    InvalidDevelopmentConfigurationView(diagnostic: .preview)
}

#Preview("Invalid development configuration — dark · AX5") {
    InvalidDevelopmentConfigurationView(diagnostic: .preview)
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}

private extension AppConfigurationDiagnosticRecord {
    static let preview = AppConfigurationDiagnosticRecord(
        status: .invalid,
        buildConfiguration: .debug,
        issues: [
            AppConfigurationIssue(field: .apiBaseURL, category: .templateValue),
            AppConfigurationIssue(field: .cognitoUserPoolID, category: .placeholder),
        ],
        liveServicesConstructed: false
    )
}
#endif
