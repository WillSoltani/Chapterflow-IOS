import SwiftUI
import CoreKit
import DesignSystem

/// The only supported boundary between untyped build configuration and the
/// application's service graph.
///
/// `AppRootView` (and therefore `AppModel`) is constructed only for a validated
/// configuration. Invalid archives fail closed without starting auth,
/// analytics, StoreKit, crash reporting, or backend requests.
public struct ConfiguredAppRootView: View {
    private let route: AppBootstrapRoute

    public init(config: AppConfig) {
        self.route = AppBootstrapRoute(state: config.validate())
    }

    public init(state: AppConfigurationState) {
        self.route = AppBootstrapRoute(state: state)
    }

    public var body: some View {
        switch route {
        case .validating:
            ProgressView("Validating ChapterFlow")
                .accessibilityLabel("Validating ChapterFlow configuration")

        case .application(let config):
            AppRootView(config: config)
                .environment(\.appConfig, config)

        case .configurationFailure(let config, let issues):
            AppConfigurationFailureView(config: config, issues: issues)
        }
    }
}

enum AppBootstrapRoute: Equatable, Sendable {
    case validating
    case application(AppConfig)
    case configurationFailure(config: AppConfig, issues: [ConfigurationIssue])

    init(state: AppConfigurationState) {
        switch state {
        case .unvalidated:
            self = .validating
        case .valid(let config, _):
            self = .application(config)
        case .invalid(let config, let issues):
            self = .configurationFailure(config: config, issues: issues)
        }
    }
}

enum ConfigurationIssueVisibility {
    static func visibleCodes(
        environment: AppEnvironment,
        issues: [ConfigurationIssue]
    ) -> [String] {
        switch environment {
        case .development, .staging:
            return issues.map(\.code).sorted()
        case .production, .unknown:
            return []
        }
    }
}

private struct AppConfigurationFailureView: View {
    let config: AppConfig
    let issues: [ConfigurationIssue]

    @Environment(\.openURL) private var openURL

    private var supportURL: URL? { config.supportURLValue }

    private var internalIssueCodes: [String] {
        ConfigurationIssueVisibility.visibleCodes(
            environment: config.environment,
            issues: issues
        )
    }

    var body: some View {
        ZStack {
            Color.cfGroupedBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: .cfSpacing20) {
                    CFEmptyState(
                        systemImage: "gear.badge.xmark",
                        title: "ChapterFlow Can't Start",
                        description: "This version has an invalid app configuration. Your data has not been changed.",
                        actionLabel: supportURL == nil ? nil : "Contact Support"
                    ) {
                        guard let supportURL else { return }
                        openURL(supportURL)
                    }

                    Text("Support code: CF-CFG-001")
                        .font(.cfFootnote.monospaced())
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .textSelection(.enabled)

                    if !internalIssueCodes.isEmpty {
                        VStack(alignment: .leading, spacing: .cfSpacing8) {
                            Text("Internal diagnostics")
                                .font(.cfHeadline)
                                .foregroundStyle(Color.cfLabel)

                            ForEach(internalIssueCodes, id: \.self) { code in
                                Text(code)
                                    .font(.cfCaption.monospaced())
                                    .foregroundStyle(Color.cfSecondaryLabel)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.cfSpacing16)
                        .background(
                            Color.cfSecondaryBackground,
                            in: RoundedRectangle(cornerRadius: .cfRadius16)
                        )
                    }
                }
                .padding(.horizontal, .cfSpacing20)
                .padding(.vertical, .cfSpacing32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("app-configuration-failure")
    }
}

#Preview("Configuration failure — internal") {
    ConfiguredAppRootView(state: .invalid(
        config: AppConfig(
            apiBaseURL: "",
            cognitoRegion: "",
            cognitoUserPoolID: "",
            cognitoClientID: "",
            environment: .development
        ),
        issues: [
            ConfigurationIssue(field: .apiBaseURL, reason: .missing),
            ConfigurationIssue(field: .cognitoClientID, reason: .missing)
        ]
    ))
}

#Preview("Configuration failure — production · dark · AX5") {
    ConfiguredAppRootView(state: .invalid(
        config: AppConfig(
            apiBaseURL: "https://api.example.invalid",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_example",
            cognitoClientID: "example",
            environment: .production
        ),
        issues: [ConfigurationIssue(field: .appStoreID, reason: .missing)]
    ))
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility5)
}
