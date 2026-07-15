import Persistence

#if DEBUG
extension SessionManager {
    static let uitestFakeIDToken =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJzdWIiOiJ1aXRlc3QtdXNlci0xMjMiLCJuYW1lIjoiVGVzdCBVc2VyIiwiZXhwIjo5OTk5OTk5OTk5fQ." +
        "uitestfakesignature"

    static let hermeticUITestIdentity: SessionIdentity = {
        guard let identity = SessionIdentity(
            subject: "uitest-user-123",
            username: "Test User",
            email: nil,
            source: .hermeticUITest
        ) else {
            preconditionFailure("Invalid fixed hermetic identity")
        }
        return identity
    }()

    public static func isHermeticUITestBypass(environment: [String: String]) -> Bool {
        environment["CF_UITEST_BYPASS_AUTH"] == "1"
            && environment["CF_STUB_SERVER"] == "1"
            && environment["CF_HERMETIC_TEST_CONFIGURATION"] == "1"
    }

    /// Constructs a deterministic signed-in session for hermetic package/UI tests.
    /// Production authentication continues to enter exclusively through `AuthService`.
    public convenience init(
        tokenStore: any TokenStoring,
        refresher: any TokenRefreshing = StubTokenRefresher(),
        hermeticIdentity: SessionIdentity,
        hermeticSignOut: @escaping @MainActor @Sendable () async -> Bool = { true }
    ) {
        self.init(
            tokenStore: tokenStore,
            refresher: refresher,
            testIdentity: hermeticIdentity
        )
        self.hermeticSignOut = hermeticSignOut
    }

    /// Moves a hermetic test session to another fixed, already-validated identity.
    public func establishHermeticSession(
        identity: SessionIdentity,
        tokens: StoredTokens
    ) throws {
        try establishSessionForTesting(identity: identity, tokens: tokens)
    }
}
#endif
