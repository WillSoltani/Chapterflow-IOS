import AuthKit
import CoreKit
import DesignSystem
import Persistence
import SwiftUI

/// A privacy-safe storage bootstrap failure. The raw error is intentionally not
/// retained, reflected into UI state, logged, or exposed to accessibility APIs.
public struct AppBootstrapStorageFailure: Equatable, Sendable {
    public static let supportCode = "CF-BOOT-STORAGE-001"

    public init() {}

    public var supportCode: String { Self.supportCode }
}

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
        let authService = AuthService(config: config.value)
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
    private let validatedConfig: ValidatedAppConfig?
    private var attempt: Task<Void, Never>?
    private var attemptGeneration: UInt = 0

    public convenience init(
        config: AppConfig,
        buildConfiguration: AppBuildConfiguration
    ) {
        self.init(
            config: config,
            buildConfiguration: buildConfiguration,
            diagnostics: NoopAppConfigurationDiagnosticsRecorder(),
            persistenceLoader: DefaultAppPersistenceLoader(),
            graphFactory: LiveAppGraphFactory()
        )
    }

    init(
        config: AppConfig,
        buildConfiguration: AppBuildConfiguration,
        diagnostics: any AppConfigurationDiagnosticsRecording,
        persistenceLoader: any AppPersistenceLoading,
        graphFactory: any AppGraphFactory
    ) {
        self.buildConfiguration = buildConfiguration
        self.diagnostics = diagnostics
        self.persistenceLoader = persistenceLoader
        self.graphFactory = graphFactory

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
        case .storageUnavailable, .sessionConfigurationFailed:
            state = .preparing
            beginAttempt()
        case .preparing, .ready, .invalidConfiguration:
            break
        }
    }

    /// Cancels the owned attempt when the launch root leaves the hierarchy.
    public func cancel() {
        guard attempt != nil else { return }
        attemptGeneration &+= 1
        attempt?.cancel()
        attempt = nil
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
        } else {
            guard attempt == nil else { return }
        }

        attemptGeneration &+= 1
        let generation = attemptGeneration
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
            } catch is CancellationError {
                self?.finishCancellation(generation: generation)
            } catch {
                self?.finishStorageFailure(generation: generation)
            }
        }
    }

    private func finishStorageLoad(
        _ persistence: AppPersistenceResources,
        config: ValidatedAppConfig,
        generation: UInt
    ) {
        guard generation == attemptGeneration else { return }

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
            attempt = nil
            state = .ready(config: config, model: model)
        } catch {
            attempt = nil
            state = .sessionConfigurationFailed(AppBootstrapSessionFailure())
        }
    }

    private func finishStorageFailure(generation: UInt) {
        guard generation == attemptGeneration else { return }
        attempt = nil
        state = .storageUnavailable(AppBootstrapStorageFailure())
    }

    private func finishCancellation(generation: UInt) {
        guard generation == attemptGeneration else { return }
        attempt = nil
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
        switch bootstrap.state {
        case .preparing:
            BootstrapPreparingView()
                .task {
                    bootstrap.start()
                    await bootstrap.waitForCurrentAttempt()
                }
                .onDisappear { bootstrap.cancel() }

        case .ready(let validated, let model):
            AppRootView(model: model)
                .environment(\.appConfig, validated.value)

        case .invalidConfiguration(let diagnostic):
            InvalidDevelopmentConfigurationView(diagnostic: diagnostic)

        case .storageUnavailable(let failure):
            BootstrapFailureView(
                kind: .storage,
                supportCode: failure.supportCode,
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
