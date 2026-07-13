import Foundation

enum ConfigurationValueInspection {
    static func preliminaryIssue(
        for value: String,
        field: AppConfigurationField,
        isMissing: Bool
    ) -> AppConfigurationIssue? {
        if isMissing {
            return AppConfigurationIssue(field: field, category: .missing)
        }

        let candidate = trimmed(value)
        if candidate.isEmpty {
            return AppConfigurationIssue(field: field, category: .empty)
        }
        if candidate.contains("$(") || candidate.contains("${") {
            return AppConfigurationIssue(field: field, category: .unexpanded)
        }
        if isTemplateValue(candidate) {
            return AppConfigurationIssue(field: field, category: .templateValue)
        }
        if isXFilledPlaceholder(candidate) {
            return AppConfigurationIssue(field: field, category: .placeholder)
        }
        return nil
    }

    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isTemplateValue(_ value: String) -> Bool {
        let candidate = value.lowercased()
        let exactValues: Set<String> = [
            "changeme", "change-me", "change_me", "example", "placeholder",
            "replace-me", "replace_me", "sample", "todo", "tbd", "your-value"
        ]
        if exactValues.contains(candidate) {
            return true
        }

        let fragments = [
            "example.com", ".example.", "your-domain", "your_domain",
            "change-me", "change_me", "replace-me", "replace_me", "<", ">"
        ]
        return fragments.contains(where: candidate.contains)
    }

    private static func isXFilledPlaceholder(_ value: String) -> Bool {
        let significant = value.filter { $0.isLetter || $0.isNumber }
        let xCount = significant.lazy.filter { $0 == "x" || $0 == "X" }.count
        guard xCount >= 6, !significant.isEmpty else { return false }
        return xCount * 2 >= significant.count
    }
}
