/// The user's privacy preferences — persisted server-side via `PATCH /book/me/settings`.
///
/// All toggles default to the MORE-private option: no sharing, no leaderboards,
/// not discoverable. Users opt in on the Profile → Privacy Settings screen (P7.8).
///
/// **Server contract:** The server applies these settings when building the
/// ``PublicProfile`` for a partner; fields the user has hidden are returned as `nil`.
/// The client ALSO enforces them in ``PublicProfileView`` so a field is never
/// rendered even if the server sends a value (defence-in-depth / offline safety).
public struct PrivacySettings: Codable, Sendable, Equatable {

    // MARK: - Profile visibility toggles

    /// Reveal the current reading streak to partners (default: hidden).
    public var showStreak: Bool

    /// Reveal the total books-finished count to partners (default: hidden).
    public var showBooksFinished: Bool

    /// Reveal per-chapter reading progress to partners (default: hidden).
    public var showProgress: Bool

    // MARK: - Identity

    /// Show the display name (chosen by the user) instead of the account real name
    /// on public-facing surfaces (default: `true` — display name is privacy-respecting
    /// because the user controls it; `false` would expose the account/real name).
    public var useDisplayName: Bool

    // MARK: - Social surfaces

    /// Opt in to leaderboards and ranking surfaces (default: `false` — not ranked).
    public var leaderboardOptIn: Bool

    /// Allow other users to find this account via discovery or people-search
    /// (default: `false` — not discoverable).
    public var discoverabilityOptIn: Bool

    // MARK: - Init

    public init(
        showStreak: Bool = false,
        showBooksFinished: Bool = false,
        showProgress: Bool = false,
        useDisplayName: Bool = true,
        leaderboardOptIn: Bool = false,
        discoverabilityOptIn: Bool = false
    ) {
        self.showStreak = showStreak
        self.showBooksFinished = showBooksFinished
        self.showProgress = showProgress
        self.useDisplayName = useDisplayName
        self.leaderboardOptIn = leaderboardOptIn
        self.discoverabilityOptIn = discoverabilityOptIn
    }

    /// Privacy-respecting defaults: all sharing off, not ranked, not discoverable.
    public static let `default` = PrivacySettings()
}

// MARK: - PublicProfile visibility helpers

/// Visibility helpers on ``PublicProfile``: apply client-side privacy enforcement
/// on top of whatever the server already hid (nil = already hidden by server).
///
/// Pass the profile-owner's ``PrivacySettings`` when rendering your own profile in
/// "how others see me" mode. Pass `nil` when viewing a partner — rely on server truth.
public extension PublicProfile {

    /// Returns the streak value only when the privacy settings permit sharing,
    /// or when no settings are supplied (server-truth mode).
    ///
    /// - Parameter settings: The profile owner's current privacy settings,
    ///   or `nil` to rely solely on the server-returned value.
    func visibleStreak(honoring settings: PrivacySettings?) -> Int? {
        if let settings, !settings.showStreak { return nil }
        return currentStreak
    }

    /// Returns the books-finished count only when the privacy settings permit sharing,
    /// or when no settings are supplied (server-truth mode).
    func visibleBooksFinished(honoring settings: PrivacySettings?) -> Int? {
        if let settings, !settings.showBooksFinished { return nil }
        return booksFinished
    }
}
