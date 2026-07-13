import Foundation

public extension AppConfig {
    /// Validates all required development service values without performing I/O.
    func validate() -> AppConfigurationValidation {
        let issues = configurationIssues
        if issues.isEmpty {
            return .valid(ValidatedAppConfig(value: normalizedRequiredValues))
        }
        return .invalid(issues)
    }

    /// Deterministically ordered, privacy-safe issues for API and Cognito setup.
    var configurationIssues: [AppConfigurationIssue] {
        AppConfigValidator.issues(for: self)
    }

    private var normalizedRequiredValues: AppConfig {
        AppConfig(
            apiBaseURL: ConfigurationValueInspection.trimmed(apiBaseURL),
            cognitoRegion: ConfigurationValueInspection.trimmed(cognitoRegion),
            cognitoUserPoolID: ConfigurationValueInspection.trimmed(cognitoUserPoolID),
            cognitoClientID: ConfigurationValueInspection.trimmed(cognitoClientID),
            cognitoDomain: ConfigurationValueInspection.trimmed(cognitoDomain),
            sentryDSN: sentryDSN,
            storeKitMonthlyProductID: storeKitMonthlyProductID,
            storeKitAnnualProductID: storeKitAnnualProductID,
            storeKitAnnualUpfrontProductID: storeKitAnnualUpfrontProductID
        )
    }
}

private enum AppConfigValidator {
    static func issues(for config: AppConfig) -> [AppConfigurationIssue] {
        var issues: [AppConfigurationIssue] = []

        validateAPIBaseURL(config.apiBaseURL, config: config, issues: &issues)
        let region = validateRegion(config.cognitoRegion, config: config, issues: &issues)
        validateUserPool(
            config.cognitoUserPoolID,
            expectedRegion: region,
            config: config,
            issues: &issues
        )
        validateClientID(config.cognitoClientID, config: config, issues: &issues)
        validateDomain(
            config.cognitoDomain,
            expectedRegion: region,
            config: config,
            issues: &issues
        )

        return Array(Set(issues)).sorted {
            if $0.field.sortIndex != $1.field.sortIndex {
                return $0.field.sortIndex < $1.field.sortIndex
            }
            return $0.category.sortIndex < $1.category.sortIndex
        }
    }

    private static func validateAPIBaseURL(
        _ value: String,
        config: AppConfig,
        issues: inout [AppConfigurationIssue]
    ) {
        let field = AppConfigurationField.apiBaseURL
        guard inspect(value, field: field, config: config, issues: &issues) else { return }

        let candidate = ConfigurationValueInspection.trimmed(value)
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              isValidAPIHost(host),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.url != nil else {
            issues.append(AppConfigurationIssue(field: field, category: .malformed))
            return
        }

        if scheme != "https", !isLoopbackHost(host) {
            issues.append(AppConfigurationIssue(field: field, category: .insecureTransport))
        }
    }

    @discardableResult
    private static func validateRegion(
        _ value: String,
        config: AppConfig,
        issues: inout [AppConfigurationIssue]
    ) -> String? {
        let field = AppConfigurationField.cognitoRegion
        guard inspect(value, field: field, config: config, issues: &issues) else { return nil }

        let candidate = ConfigurationValueInspection.trimmed(value)
        guard isValidRegion(candidate) else {
            issues.append(AppConfigurationIssue(field: field, category: .malformed))
            return nil
        }
        return candidate
    }

    private static func validateUserPool(
        _ value: String,
        expectedRegion: String?,
        config: AppConfig,
        issues: inout [AppConfigurationIssue]
    ) {
        let field = AppConfigurationField.cognitoUserPoolID
        guard inspect(value, field: field, config: config, issues: &issues) else { return }

        let candidate = ConfigurationValueInspection.trimmed(value)
        guard matches(
            candidate,
            pattern: #"^[a-z]{2}(?:-[a-z0-9]+)+-[0-9]+_[A-Za-z0-9]+$"#
        ) else {
            issues.append(AppConfigurationIssue(field: field, category: .malformed))
            return
        }

        if let expectedRegion, !candidate.hasPrefix("\(expectedRegion)_") {
            issues.append(AppConfigurationIssue(field: field, category: .regionMismatch))
        }
    }

    private static func validateClientID(
        _ value: String,
        config: AppConfig,
        issues: inout [AppConfigurationIssue]
    ) {
        let field = AppConfigurationField.cognitoClientID
        guard inspect(value, field: field, config: config, issues: &issues) else { return }

        let candidate = ConfigurationValueInspection.trimmed(value)
        if !matches(candidate, pattern: #"^[A-Za-z0-9]{10,128}$"#) {
            issues.append(AppConfigurationIssue(field: field, category: .malformed))
        }
    }

    private static func validateDomain(
        _ value: String,
        expectedRegion: String?,
        config: AppConfig,
        issues: inout [AppConfigurationIssue]
    ) {
        let field = AppConfigurationField.cognitoDomain
        guard inspect(value, field: field, config: config, issues: &issues) else { return }

        let candidate = ConfigurationValueInspection.trimmed(value)
        guard !candidate.contains("://"), !candidate.contains("/"),
              !candidate.contains("?"), !candidate.contains("#"),
              isValidHostname(candidate) else {
            issues.append(AppConfigurationIssue(field: field, category: .malformed))
            return
        }

        let hostname = candidate.lowercased()
        let isAWSHostedDomain = hostname == "amazoncognito.com" ||
            hostname.hasSuffix(".amazoncognito.com")
        guard isAWSHostedDomain else { return }

        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 5,
              labels[1] == "auth",
              isValidRegion(String(labels[2])) else {
            issues.append(AppConfigurationIssue(field: field, category: .malformed))
            return
        }

        if let expectedRegion, labels[2] != Substring(expectedRegion) {
            issues.append(AppConfigurationIssue(field: field, category: .regionMismatch))
        }
    }

    private static func inspect(
        _ value: String,
        field: AppConfigurationField,
        config: AppConfig,
        issues: inout [AppConfigurationIssue]
    ) -> Bool {
        if let issue = ConfigurationValueInspection.preliminaryIssue(
            for: value,
            field: field,
            isMissing: config.missingRequiredFields.contains(field)
        ) {
            issues.append(issue)
            return false
        }
        return true
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isValidRegion(_ value: String) -> Bool {
        matches(value, pattern: #"^[a-z]{2}(?:-[a-z0-9]+)+-[0-9]+$"#)
    }

    private static func isValidAPIHost(_ host: String) -> Bool {
        isLoopbackHost(host) || isValidHostname(host)
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let candidate = host.lowercased()
        return candidate == "localhost" || candidate == "127.0.0.1" || candidate == "::1"
    }

    private static func isValidHostname(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 253, value.unicodeScalars.allSatisfy(\.isASCII) else {
            return false
        }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }

        return labels.allSatisfy { label in
            guard !label.isEmpty, label.utf8.count <= 63,
                  let first = label.utf8.first,
                  let last = label.utf8.last,
                  isASCIILetterOrDigit(first),
                  isASCIILetterOrDigit(last) else {
                return false
            }
            return label.utf8.allSatisfy { byte in
                isASCIILetterOrDigit(byte) || byte == Character("-").asciiValue
            }
        }
    }

    private static func isASCIILetterOrDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) ||
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ||
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}
