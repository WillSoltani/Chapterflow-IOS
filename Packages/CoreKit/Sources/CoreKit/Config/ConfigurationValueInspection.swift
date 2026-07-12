import Foundation

enum ConfigurationValueInspection {
    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func issueReason(
        for value: String,
        required: Bool
    ) -> ConfigurationIssue.Reason? {
        let candidate = trimmed(value)
        if candidate.isEmpty {
            return required ? .missing : nil
        }
        if candidate.contains("$(") || candidate.contains("${") || candidate.contains("@@") {
            return .unexpanded
        }
        if isPlaceholder(candidate) {
            return .placeholder
        }
        return nil
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        let exactPlaceholders: Set<String> = [
            "placeholder", "changeme", "change-me", "replace-me", "replace_me",
            "unknown", "dummy", "local", "todo", "tbd"
        ]
        if exactPlaceholders.contains(lowercased) {
            return true
        }
        let fragments = [
            "example.com", ".example.", "your-domain", "your_domain", "placeholder",
            "change-me", "changeme", "replace-me", "replace_me", "<", ">"
        ]
        if fragments.contains(where: lowercased.contains) {
            return true
        }
        return lowercased.range(
            of: #"x{6,}"#,
            options: .regularExpression
        ) != nil
    }
}
