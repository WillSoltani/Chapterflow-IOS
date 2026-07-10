import Foundation

// MARK: - AppVersion

/// A dotted numeric app version (`"1.2.3"`) with component-wise ordering.
///
/// Comparison ignores any non-numeric suffix and treats missing trailing
/// components as zero, so `"1.2"` and `"1.2.0"` are equal and `"1.10" > "1.9"`.
public struct AppVersion: Comparable, Equatable, Sendable {
    public let components: [Int]

    /// Parses `"1.2.3"` into `[1, 2, 3]`. Non-numeric parts contribute `0`.
    public init(_ string: String) {
        self.components = string
            .split(separator: ".")
            .map { part in Int(part.prefix { $0.isNumber }) ?? 0 }
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return false }
        }
        return true
    }
}

// MARK: - WhatsNewPolicy

/// Pure, testable decision for whether the What's New screen should be shown
/// automatically at launch.
///
/// The rule is deliberately conservative: What's New announces *updates*, so it
/// never appears on a fresh install (`lastSeen == nil`) — the onboarding flow
/// covers first-run. It shows exactly when the current version is strictly newer
/// than the last version the user has already seen.
public enum WhatsNewPolicy {
    /// - Parameters:
    ///   - lastSeenVersion: The version the user last saw What's New for, or
    ///     `nil` on a fresh install / before any launch has recorded it.
    ///   - currentVersion: The running app's marketing version.
    /// - Returns: `true` when What's New should auto-present at launch.
    public static func shouldShow(lastSeenVersion: String?, currentVersion: String) -> Bool {
        guard let lastSeenVersion, !lastSeenVersion.isEmpty else {
            // Fresh install — nothing to announce yet.
            return false
        }
        return AppVersion(currentVersion) > AppVersion(lastSeenVersion)
    }
}
