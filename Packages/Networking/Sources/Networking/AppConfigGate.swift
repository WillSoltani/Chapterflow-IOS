import Foundation

// MARK: - Semantic version

/// A minimal, pure, testable semantic-version value used to compare the running
/// build against the server's `minSupportedVersion` / `latestVersion`.
///
/// Parses a dot-separated numeric string (`"2.10.1"`), ignoring any pre-release
/// or build suffix after a `-`/`+`. Missing trailing components compare as `0`
/// (`"2.10"` == `"2.10.0"`). Comparison is component-wise numeric, so
/// `"2.10" > "2.9"` — the correctness point that a string compare gets wrong.
public struct SemanticVersion: Comparable, Equatable, Sendable {
    public let components: [Int]

    /// Parses a version string. Returns `nil` when there is no leading numeric
    /// component at all, so callers can fail open on unparseable input.
    public init?(_ raw: String) {
        // Drop any pre-release / build metadata: "1.2.3-beta.1+build" → "1.2.3".
        let core = raw
            .trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == "-" || $0 == "+" })
            .first
            .map(String.init) ?? ""
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        var parsed: [Int] = []
        for part in parts {
            guard let value = Int(part) else { break }
            parsed.append(value)
        }
        guard !parsed.isEmpty else { return nil }
        // Trim trailing zeros so "2.10.0" and "2.10" compare equal.
        while parsed.count > 1, parsed.last == 0 {
            parsed.removeLast()
        }
        self.components = parsed
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

// MARK: - Gate state

/// The one thing `AppRootView` needs to render for the mobile-config gate.
public enum AppConfigGateState: Equatable, Sendable {
    /// Nothing to show — the app proceeds normally.
    case none
    /// A dismissible "update available" nudge. Carries the newest version and an
    /// optional server message for the copy.
    case softNudge(latestVersion: String?, message: String?)
    /// A blocking "update required" gate. No dismiss; only an App Store link.
    case hardGate(message: String?)
    /// A blocking maintenance-mode screen (backend downtime).
    case maintenance(message: String?)

    /// Whether this state blocks the whole app (no interaction with content).
    public var isBlocking: Bool {
        switch self {
        case .hardGate, .maintenance: return true
        case .none, .softNudge:       return false
        }
    }
}

// MARK: - Pure evaluation

/// Pure, dependency-free evaluation of an ``IOSAppConfig`` against the running
/// build version. This is the single source of truth for the four states and is
/// exhaustively unit-tested. It never performs I/O.
public enum AppConfigGate {
    /// Maps a (possibly absent) config + current version to a gate state.
    ///
    /// Fail-open by construction: a `nil` config, an absent/empty
    /// `minSupportedVersion`/`latestVersion`, or a version string that can't be
    /// parsed all resolve to `.none` (or skip that particular check) rather than
    /// locking the user out.
    ///
    /// Precedence: maintenance → hard gate → soft nudge → none.
    public static func evaluate(config: IOSAppConfig?, currentVersion: String) -> AppConfigGateState {
        // No config at all (never fetched, or unparseable) → proceed normally.
        guard let config else { return .none }

        // Maintenance is an explicit server directive that applies to everyone.
        if config.maintenanceMode {
            return .maintenance(message: config.messageOfTheDay)
        }

        // Both version checks require a parseable running version; if the build's
        // own version can't be parsed we fail open rather than risk a false lock.
        guard let current = SemanticVersion(currentVersion) else { return .none }

        // HARD GATE: running below the minimum supported version.
        if let minRaw = config.minSupportedVersion,
           let minimum = SemanticVersion(minRaw),
           current < minimum {
            return .hardGate(message: config.messageOfTheDay)
        }

        // SOFT NUDGE: a newer version exists (but we're still supported).
        if let latestRaw = config.latestVersion,
           let latest = SemanticVersion(latestRaw),
           current < latest {
            return .softNudge(latestVersion: latestRaw, message: config.messageOfTheDay)
        }

        return .none
    }
}
