import Foundation

public extension AppConfig {
    /// Evaluates every field without performing I/O or exposing configuration values.
    func validate() -> AppConfigurationState {
        let issues = configurationIssues
        guard issues.isEmpty else {
            return .invalid(config: self, issues: issues)
        }
        return .valid(config: self, environment: environment)
    }

    /// Deterministically ordered issues, suitable for equality assertions and CI output.
    var configurationIssues: [ConfigurationIssue] {
        AppConfigValidation.issues(for: self)
    }

    /// Returns an exact Apple product destination only when its ID, scheme, host,
    /// and path all pass the same checks used by configuration validation.
    var exactAppStoreURL: URL? {
        AppConfigValidation.exactAppStoreURL(id: appStoreID, rawURL: appStoreURL)
    }

    /// Returns a support destination only when it is an approved public HTTPS URL.
    var supportURLValue: URL? {
        AppConfigValidation.supportURL(rawValue: supportURL)
    }

    /// Produces diagnostics containing only explicitly allowlisted, nonsecret fields.
    var buildDiagnosticsRecord: BuildDiagnosticsRecord {
        let productIDs = [
            storeKitMonthlyProductID,
            storeKitAnnualProductID,
            storeKitAnnualUpfrontProductID
        ]
        let productCount = Set(productIDs.map(ConfigurationValueInspection.trimmed).filter {
            !$0.isEmpty
        }).count
        let apiHost = URLComponents(string: ConfigurationValueInspection.trimmed(apiBaseURL))?
            .host ?? ""
        return BuildDiagnosticsRecord(
            environment: environment,
            apiHost: apiHost,
            bundleIdentifier: bundleIdentifier,
            marketingVersion: marketingVersion,
            buildNumber: buildNumber,
            buildConfiguration: buildConfiguration,
            buildCommitSHA: buildCommitSHA,
            storeKitProductCount: productCount,
            sentryEnabled: sentryPolicy == .enabled
        )
    }
}

private enum AppConfigValidation {
    private static let appStoreHosts: Set<String> = ["apps.apple.com", "itunes.apple.com"]

    static func issues(for config: AppConfig) -> [ConfigurationIssue] {
        var issues = config.sourceIssues
        validateEnvironment(config.environment, issues: &issues)
        validateAPIURL(config.apiBaseURL, environment: config.environment, issues: &issues)
        let regionIsValid = validateCognitoRegion(config.cognitoRegion, issues: &issues)
        validateCognitoPool(
            config.cognitoUserPoolID,
            region: regionIsValid ? ConfigurationValueInspection.trimmed(config.cognitoRegion) : nil,
            issues: &issues
        )
        validateCognitoClientID(config.cognitoClientID, issues: &issues)
        validateCognitoDomain(config.cognitoDomain, environment: config.environment, issues: &issues)
        validateBundleIdentifier(config, issues: &issues)
        validateAppStore(config, issues: &issues)
        validateSupportURL(config, issues: &issues)
        validateStoreKit(config, issues: &issues)
        validateSentry(config, issues: &issues)
        validateProvenance(config, issues: &issues)
        return uniqued(issues)
    }

    static func exactAppStoreURL(id: String, rawURL: String) -> URL? {
        let appID = ConfigurationValueInspection.trimmed(id)
        let destination = ConfigurationValueInspection.trimmed(rawURL)
        guard ConfigurationValueInspection.issueReason(for: appID, required: true) == nil,
              ConfigurationValueInspection.issueReason(for: destination, required: true) == nil,
              matches(appID, pattern: #"^[1-9][0-9]{5,19}$"#),
              let components = URLComponents(string: destination),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              ["https", "itms-apps"].contains(scheme),
              appStoreHosts.contains(host),
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              appStoreID(in: components) == appID,
              let url = components.url else {
            return nil
        }
        return url
    }

    static func supportURL(rawValue: String) -> URL? {
        let candidate = ConfigurationValueInspection.trimmed(rawValue)
        guard ConfigurationValueInspection.issueReason(for: candidate, required: true) == nil,
              let components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              isPublicHost(host),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let url = components.url else {
            return nil
        }
        return url
    }

    private static func validateEnvironment(
        _ environment: AppEnvironment,
        issues: inout [ConfigurationIssue]
    ) {
        guard environment == .unknown,
              !issues.contains(where: { $0.field == .environment }) else {
            return
        }
        issues.append(ConfigurationIssue(field: .environment, reason: .missing))
    }

    private static func validateAPIURL(
        _ rawValue: String,
        environment: AppEnvironment,
        issues: inout [ConfigurationIssue]
    ) {
        guard inspect(rawValue, field: .apiBaseURL, required: true, issues: &issues) else {
            return
        }
        let candidate = ConfigurationValueInspection.trimmed(rawValue)
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              isValidHostname(host),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            append(.apiBaseURL, .malformed, to: &issues)
            return
        }
        guard environment == .production else { return }
        if scheme != "https" {
            append(.apiBaseURL, .insecure, to: &issues)
        }
        if !isPublicHost(host) {
            append(.apiBaseURL, .disallowedHost, to: &issues)
        }
    }

    @discardableResult
    private static func validateCognitoRegion(
        _ value: String,
        issues: inout [ConfigurationIssue]
    ) -> Bool {
        guard inspect(value, field: .cognitoRegion, required: true, issues: &issues) else {
            return false
        }
        let valid = matches(
            ConfigurationValueInspection.trimmed(value),
            pattern: #"^[a-z]{2}(?:-[a-z0-9]+)+-[0-9]+$"#
        )
        if !valid {
            append(.cognitoRegion, .malformed, to: &issues)
        }
        return valid
    }

    private static func validateCognitoPool(
        _ value: String,
        region: String?,
        issues: inout [ConfigurationIssue]
    ) {
        guard inspect(value, field: .cognitoUserPoolID, required: true, issues: &issues) else {
            return
        }
        let candidate = ConfigurationValueInspection.trimmed(value)
        guard matches(candidate, pattern: #"^[a-z]{2}(?:-[a-z0-9]+)+-[0-9]+_[A-Za-z0-9]+$"#) else {
            append(.cognitoUserPoolID, .malformed, to: &issues)
            return
        }
        if let region, !candidate.hasPrefix("\(region)_") {
            append(.cognitoUserPoolID, .mismatch, to: &issues)
        }
    }

    private static func validateCognitoClientID(
        _ value: String,
        issues: inout [ConfigurationIssue]
    ) {
        guard inspect(value, field: .cognitoClientID, required: true, issues: &issues) else {
            return
        }
        if !matches(
            ConfigurationValueInspection.trimmed(value),
            pattern: #"^[A-Za-z0-9]{10,128}$"#
        ) {
            append(.cognitoClientID, .malformed, to: &issues)
        }
    }

    private static func validateCognitoDomain(
        _ value: String,
        environment: AppEnvironment,
        issues: inout [ConfigurationIssue]
    ) {
        guard inspect(value, field: .cognitoDomain, required: true, issues: &issues) else {
            return
        }
        let candidate = ConfigurationValueInspection.trimmed(value)
        guard !candidate.contains("://"),
              !candidate.contains("/"),
              !candidate.contains("?"),
              !candidate.contains("#"),
              candidate.contains("."),
              isValidHostname(candidate) else {
            append(.cognitoDomain, .malformed, to: &issues)
            return
        }
        if environment == .production, !isPublicHost(candidate) {
            append(.cognitoDomain, .disallowedHost, to: &issues)
        }
    }

    private static func validateBundleIdentifier(
        _ config: AppConfig,
        issues: inout [ConfigurationIssue]
    ) {
        let required = config.environment == .production
        guard inspect(
            config.bundleIdentifier,
            field: .bundleIdentifier,
            required: required,
            issues: &issues
        ) else {
            return
        }
        if config.environment == .production,
           ConfigurationValueInspection.trimmed(config.bundleIdentifier)
           != AppConfig.expectedProductionBundleIdentifier {
            append(.bundleIdentifier, .mismatch, to: &issues)
        }
    }

    private static func validateAppStore(
        _ config: AppConfig,
        issues: inout [ConfigurationIssue]
    ) {
        let hasID = !ConfigurationValueInspection.trimmed(config.appStoreID).isEmpty
        let hasURL = !ConfigurationValueInspection.trimmed(config.appStoreURL).isEmpty
        let required = config.environment == .production || hasID || hasURL
        let usableID = inspect(
            config.appStoreID,
            field: .appStoreID,
            required: required,
            issues: &issues
        )
        let usableURL = inspect(
            config.appStoreURL,
            field: .appStoreURL,
            required: required,
            issues: &issues
        )
        var validID = false
        if usableID {
            validID = matches(
                ConfigurationValueInspection.trimmed(config.appStoreID),
                pattern: #"^[1-9][0-9]{5,19}$"#
            )
            if !validID {
                append(.appStoreID, .malformed, to: &issues)
            }
        }
        guard usableURL else { return }
        let destination = ConfigurationValueInspection.trimmed(config.appStoreURL)
        guard let components = URLComponents(string: destination),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              ["https", "itms-apps"].contains(scheme),
              appStoreHosts.contains(host),
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let destinationID = appStoreID(in: components) else {
            append(.appStoreURL, .malformed, to: &issues)
            return
        }
        if validID, destinationID != ConfigurationValueInspection.trimmed(config.appStoreID) {
            append(.appStoreURL, .mismatch, to: &issues)
        }
    }

    private static func validateSupportURL(
        _ config: AppConfig,
        issues: inout [ConfigurationIssue]
    ) {
        let required = config.environment == .production
        guard inspect(config.supportURL, field: .supportURL, required: required, issues: &issues) else {
            return
        }
        if supportURL(rawValue: config.supportURL) == nil {
            append(.supportURL, .malformed, to: &issues)
        }
    }

    private static func validateStoreKit(
        _ config: AppConfig,
        issues: inout [ConfigurationIssue]
    ) {
        let configured = [
            config.storeKitMonthlyProductID,
            config.storeKitAnnualProductID,
            config.storeKitAnnualUpfrontProductID
        ].contains { !ConfigurationValueInspection.trimmed($0).isEmpty }
        let required = config.environment == .production || configured
        let monthlyValid = validateProductID(
            config.storeKitMonthlyProductID,
            field: .storeKitMonthlyProductID,
            required: required,
            issues: &issues
        )
        let annualValid = validateProductID(
            config.storeKitAnnualProductID,
            field: .storeKitAnnualProductID,
            required: required,
            issues: &issues
        )
        let upfrontValid = validateProductID(
            config.storeKitAnnualUpfrontProductID,
            field: .storeKitAnnualUpfrontProductID,
            required: false,
            issues: &issues
        )
        let monthly = ConfigurationValueInspection.trimmed(config.storeKitMonthlyProductID)
        let annual = ConfigurationValueInspection.trimmed(config.storeKitAnnualProductID)
        let upfront = ConfigurationValueInspection.trimmed(config.storeKitAnnualUpfrontProductID)
        if !upfront.isEmpty {
            append(.storeKitAnnualUpfrontProductID, .unsupported, to: &issues)
        }
        if monthlyValid, annualValid, monthly == annual {
            append(.storeKitAnnualProductID, .duplicate, to: &issues)
        }
        if upfrontValid, !upfront.isEmpty, upfront == monthly || upfront == annual {
            append(.storeKitAnnualUpfrontProductID, .duplicate, to: &issues)
        }
    }

    @discardableResult
    private static func validateProductID(
        _ value: String,
        field: ConfigurationIssue.Field,
        required: Bool,
        issues: inout [ConfigurationIssue]
    ) -> Bool {
        guard inspect(value, field: field, required: required, issues: &issues) else {
            return false
        }
        let valid = matches(
            ConfigurationValueInspection.trimmed(value),
            pattern: #"^[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)+$"#
        )
        if !valid {
            append(field, .malformed, to: &issues)
        }
        return valid
    }

    private static func validateSentry(
        _ config: AppConfig,
        issues: inout [ConfigurationIssue]
    ) {
        switch config.sentryPolicy {
        case .enabled:
            guard inspect(config.sentryDSN, field: .sentryDSN, required: true, issues: &issues) else {
                return
            }
            if !isValidSentryDSN(config.sentryDSN) {
                append(.sentryDSN, .malformed, to: &issues)
            }
        case .disabled:
            validateDisabledSentryDSN(config.sentryDSN, issues: &issues)
        case .unspecified:
            if config.environment == .production,
               !issues.contains(where: { $0.field == .sentryPolicy }) {
                append(.sentryPolicy, .missing, to: &issues)
            }
            validateDisabledSentryDSN(config.sentryDSN, issues: &issues)
        }
    }

    private static func validateDisabledSentryDSN(
        _ value: String,
        issues: inout [ConfigurationIssue]
    ) {
        let candidate = ConfigurationValueInspection.trimmed(value)
        guard !candidate.isEmpty else { return }
        if let reason = ConfigurationValueInspection.issueReason(for: candidate, required: false) {
            append(.sentryDSN, reason, to: &issues)
        } else {
            append(.sentryDSN, .inconsistent, to: &issues)
        }
    }

    private static func validateProvenance(
        _ config: AppConfig,
        issues: inout [ConfigurationIssue]
    ) {
        let required = config.environment == .production
        let configurationValid = inspect(
            config.buildConfiguration,
            field: .buildConfiguration,
            required: required,
            issues: &issues
        )
        let commitValid = inspect(
            config.buildCommitSHA,
            field: .buildCommitSHA,
            required: required,
            issues: &issues
        )
        let versionValid = inspect(
            config.marketingVersion,
            field: .marketingVersion,
            required: required,
            issues: &issues
        )
        let buildValid = inspect(
            config.buildNumber,
            field: .buildNumber,
            required: required,
            issues: &issues
        )
        if configurationValid,
           config.environment == .production,
           ConfigurationValueInspection.trimmed(config.buildConfiguration).lowercased() != "release" {
            append(.buildConfiguration, .mismatch, to: &issues)
        }
        let commitPattern = config.environment == .production
            ? #"^[A-Fa-f0-9]{40}$"#
            : #"^[A-Fa-f0-9]{7,64}$"#
        if commitValid,
           !matches(ConfigurationValueInspection.trimmed(config.buildCommitSHA), pattern: commitPattern) {
            append(.buildCommitSHA, .malformed, to: &issues)
        }
        let versionPattern = config.environment == .production
            ? #"^[0-9]+\.[0-9]+(?:\.[0-9]+)?$"#
            : #"^[0-9]+(?:\.[0-9]+){0,2}$"#
        if versionValid,
           !matches(ConfigurationValueInspection.trimmed(config.marketingVersion), pattern: versionPattern) {
            append(.marketingVersion, .malformed, to: &issues)
        }
        let buildPattern = config.environment == .production
            ? #"^[1-9][0-9]*$"#
            : #"^[0-9]+(?:\.[0-9]+){0,2}$"#
        if buildValid,
           !matches(ConfigurationValueInspection.trimmed(config.buildNumber), pattern: buildPattern) {
            append(.buildNumber, .malformed, to: &issues)
        }
    }

    @discardableResult
    private static func inspect(
        _ value: String,
        field: ConfigurationIssue.Field,
        required: Bool,
        issues: inout [ConfigurationIssue]
    ) -> Bool {
        guard let reason = ConfigurationValueInspection.issueReason(
            for: value,
            required: required
        ) else {
            return !ConfigurationValueInspection.trimmed(value).isEmpty
        }
        append(field, reason, to: &issues)
        return false
    }

    private static func isValidSentryDSN(_ value: String) -> Bool {
        guard let components = URLComponents(
            string: ConfigurationValueInspection.trimmed(value)
        ), components.scheme?.lowercased() == "https",
        let user = components.user, !user.isEmpty,
        components.password == nil,
        let host = components.host, isPublicHost(host),
        components.path.split(separator: "/").last != nil,
        components.query == nil,
        components.fragment == nil else {
            return false
        }
        return true
    }

    private static func appStoreID(in components: URLComponents) -> String? {
        guard let segment = components.path.split(separator: "/").last,
              segment.hasPrefix("id") else {
            return nil
        }
        let suffix = segment.dropFirst(2)
        guard matches(String(suffix), pattern: #"^[1-9][0-9]{5,19}$"#) else { return nil }
        return String(suffix)
    }

    private static func isPublicHost(_ host: String) -> Bool {
        let candidate = host.lowercased()
        guard isValidHostname(candidate),
              candidate.contains("."),
              !matches(candidate, pattern: #"^[0-9.]+$"#),
              !candidate.contains(":"),
              !candidate.hasSuffix(".local"),
              !candidate.hasSuffix(".localhost"),
              !candidate.hasSuffix(".test"),
              !candidate.hasSuffix(".example"),
              !candidate.hasSuffix(".invalid") else {
            return false
        }
        return true
    }

    private static func isValidHostname(_ host: String) -> Bool {
        let candidate = host.lowercased()
        guard !candidate.isEmpty, candidate.count <= 253 else { return false }
        return candidate.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            guard !label.isEmpty, label.count <= 63,
                  let first = label.first, first.isLetter || first.isNumber,
                  let last = label.last, last.isLetter || last.isNumber else {
                return false
            }
            return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func append(
        _ field: ConfigurationIssue.Field,
        _ reason: ConfigurationIssue.Reason,
        to issues: inout [ConfigurationIssue]
    ) {
        issues.append(ConfigurationIssue(field: field, reason: reason))
    }

    private static func uniqued(_ issues: [ConfigurationIssue]) -> [ConfigurationIssue] {
        issues.reduce(into: []) { result, issue in
            if !result.contains(issue) {
                result.append(issue)
            }
        }
    }
}
