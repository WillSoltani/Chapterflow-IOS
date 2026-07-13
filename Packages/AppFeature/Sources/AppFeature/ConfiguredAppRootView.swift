import CoreKit
import DesignSystem
import SwiftUI

/// One-time result of validating configuration and, only when valid, building
/// the application's live service graph.
@MainActor
struct AppGraphBootstrap<Graph> {
    enum Route {
        case application(config: ValidatedAppConfig, graph: Graph)
        case configurationFailure(AppConfigurationDiagnosticRecord)
    }

    let route: Route

    init(
        config: AppConfig,
        buildConfiguration: AppBuildConfiguration,
        diagnostics: any AppConfigurationDiagnosticsRecording,
        makeGraph: (ValidatedAppConfig) -> Graph
    ) {
        switch config.validate() {
        case .valid(let validated):
            let graph = makeGraph(validated)
            let record = AppConfigurationDiagnosticRecord(
                status: .valid,
                buildConfiguration: buildConfiguration,
                issues: [],
                liveServicesConstructed: true
            )
            _ = try? diagnostics.record(record)
            route = .application(config: validated, graph: graph)

        case .invalid(let issues):
            let record = AppConfigurationDiagnosticRecord(
                status: .invalid,
                buildConfiguration: buildConfiguration,
                issues: issues,
                liveServicesConstructed: false
            )
            _ = try? diagnostics.record(record)
            route = .configurationFailure(record)
        }
    }
}

/// Stored bootstrap value created once by `ChapterFlowApp.init()`.
/// SwiftUI receives the already-resolved value and cannot re-run the graph
/// factory during view initialization or body evaluation.
@MainActor
public struct AppBootstrap {
    let resolution: AppGraphBootstrap<AppModel>

    public init(config: AppConfig, buildConfiguration: AppBuildConfiguration) {
        resolution = AppGraphBootstrap(
            config: config,
            buildConfiguration: buildConfiguration,
            diagnostics: NoopAppConfigurationDiagnosticsRecorder(),
            makeGraph: AppModel.init(config:)
        )
    }
}

/// Root switch between the prebuilt live application and the dedicated invalid
/// development-configuration surface.
public struct ConfiguredAppRootView: View {
    private let bootstrap: AppBootstrap

    public init(bootstrap: AppBootstrap) {
        self.bootstrap = bootstrap
    }

    public var body: some View {
        switch bootstrap.resolution.route {
        case .application(let validated, let model):
            AppRootView(model: model)
                .environment(\.appConfig, validated.value)

        case .configurationFailure(let diagnostic):
            InvalidDevelopmentConfigurationView(diagnostic: diagnostic)
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
