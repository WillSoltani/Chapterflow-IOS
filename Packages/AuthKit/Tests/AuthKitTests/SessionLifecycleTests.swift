import Foundation
import Testing
@testable import AuthKit
import CoreKit
import Persistence

@Suite("Authoritative session identity")
@MainActor
struct AuthoritativeSessionIdentityTests {
    @Test(
        "identity rejects empty, altered, and local fallback subjects",
        arguments: ["", " ", " subject ", "anon", "local"]
    )
    func rejectsInvalidSubjects(_ subject: String) {
        #expect(SessionIdentity(
            subject: subject,
            username: nil,
            email: nil,
            source: .cognitoUserPool
        ) == nil)
    }

    @Test("email sign-in commits only matching nonempty identity evidence")
    func emailSignInCommitsVerifiedIdentity() async throws {
        let store = InMemoryTokenStore()
        let expectedTokens = makeSessionTokens()
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: expectedTokens),
            user: .init(userId: subjectA, username: "reader", email: nil)
        )
        let service = AuthService(config: makeAuthConfig(), tokenStore: store, sessionClient: client)
        let session = SessionManager(authService: service)

        try await session.signIn(username: "reader@example.com", password: "password")

        #expect(session.currentIdentity?.subject == subjectA)
        #expect(session.authState == .signedIn(try makeIdentity()))
        #expect(try store.load() == expectedTokens)
        #expect(await client.signInCallCount == 1)
    }

    @Test("an active A session must sign out before B sign-in begins")
    func activeSessionRejectsReplacementSignIn() async throws {
        let tokensA = makeSessionTokens(subject: subjectA, marker: "a")
        let tokensB = makeSessionTokens(subject: subjectB, marker: "b")
        let store = InMemoryTokenStore(tokens: tokensA)
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: tokensB),
            user: .init(userId: subjectB, username: "reader-b", email: nil)
        )
        let service = AuthService(config: makeAuthConfig(), tokenStore: store, sessionClient: client)
        let identityA = try makeIdentity(subjectA)
        let session = SessionManager(authService: service, testIdentity: identityA)

        await #expect(throws: AppError.self) {
            try await session.signIn(username: "reader-b", password: "password")
        }

        #expect(await client.signInCallCount == 0)
        #expect(session.currentIdentity == identityA)
        #expect(session.authState == .signedIn(identityA))
        #expect(try store.load() == tokensA)
    }

    @Test("reset-password next step preserves actionable sign-in guidance")
    func resetPasswordStepIsPreserved() async throws {
        let store = InMemoryTokenStore()
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: false, tokens: nil),
            user: .init(userId: subjectA, username: "reader", email: nil),
            signInOutcome: .resetPassword
        )
        let session = SessionManager(authService: AuthService(
            config: makeAuthConfig(), tokenStore: store, sessionClient: client
        ))

        do {
            try await session.signIn(username: "reader@example.com", password: "password")
            Issue.record("Expected reset-password guidance")
        } catch let error as AppError {
            #expect(error.errorDescription == "Your password must be reset before signing in.")
        }
        #expect(session.authState == .signedOut)
        #expect(try store.load() == nil)
    }

    @Test("restoration creates the same verified identity and replaces the mirror")
    func restorationCommitsVerifiedIdentity() async throws {
        let stale = makeSessionTokens(subject: subjectB, marker: "stale")
        let expectedTokens = makeSessionTokens()
        let store = InMemoryTokenStore(tokens: stale)
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: expectedTokens),
            user: .init(userId: subjectA, username: "reader", email: nil)
        )
        let service = AuthService(config: makeAuthConfig(), tokenStore: store, sessionClient: client)
        let session = SessionManager(authService: service)

        await session.restoreSession()

        let expectedIdentity = try makeIdentity()
        #expect(session.currentIdentity == expectedIdentity)
        #expect(try store.load() == expectedTokens)
    }

    @Test("missing current-user identity fails closed", arguments: ["", " ", "anon", "local"])
    func missingCurrentUserFailsClosed(_ userId: String) async throws {
        let store = InMemoryTokenStore(tokens: makeSessionTokens(subject: subjectB, marker: "stale"))
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: makeSessionTokens()),
            user: .init(userId: userId, username: "reader", email: nil)
        )
        let session = SessionManager(authService: AuthService(
            config: makeAuthConfig(), tokenStore: store, sessionClient: client
        ))

        await session.restoreSession()

        #expect(session.authState == .signedOut)
        #expect(session.currentIdentity == nil)
        #expect(try store.load() == nil)
    }

    @Test("missing or invalid token subject fails closed", arguments: [nil, "", " ", "anon", "local"] as [String?])
    func invalidTokenSubjectFailsClosed(_ tokenSubject: String?) async throws {
        let store = InMemoryTokenStore(tokens: makeSessionTokens(subject: subjectB, marker: "stale"))
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: makeSessionTokens(subject: tokenSubject)),
            user: .init(userId: subjectA, username: "reader", email: nil)
        )
        let session = SessionManager(authService: AuthService(
            config: makeAuthConfig(), tokenStore: store, sessionClient: client
        ))

        await session.restoreSession()

        #expect(session.authState == .signedOut)
        #expect(session.currentIdentity == nil)
        #expect(try store.load() == nil)
    }

    @Test("current user and token subject mismatch fails closed")
    func mismatchedIdentityEvidenceFailsClosed() async throws {
        let store = InMemoryTokenStore(tokens: makeSessionTokens(subject: subjectB, marker: "stale"))
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: makeSessionTokens(subject: subjectA)),
            user: .init(userId: subjectB, username: "reader", email: nil)
        )
        let session = SessionManager(authService: AuthService(
            config: makeAuthConfig(), tokenStore: store, sessionClient: client
        ))

        await session.restoreSession()

        #expect(session.authState == .signedOut)
        #expect(session.currentIdentity == nil)
        #expect(try store.load() == nil)
    }

    @Test(
        "missing or nonnumeric token expiry fails closed",
        arguments: [TestExpiryClaim.missing, .text]
    )
    func invalidTokenExpiryFailsClosed(_ expiryClaim: TestExpiryClaim) async throws {
        let store = InMemoryTokenStore(tokens: makeSessionTokens(subject: subjectB, marker: "stale"))
        let client = ScriptedCognitoSessionClient(
            session: .init(
                isSignedIn: true,
                tokens: makeSessionTokens(expiryClaim: expiryClaim)
            ),
            user: .init(userId: subjectA, username: "reader", email: nil)
        )
        let session = SessionManager(authService: AuthService(
            config: makeAuthConfig(), tokenStore: store, sessionClient: client
        ))

        await session.restoreSession()

        #expect(session.authState == .signedOut)
        #expect(session.currentIdentity == nil)
        #expect(try store.load() == nil)
    }

    @Test("stored mirror without signed-in Cognito session cannot authenticate")
    func mirrorAloneCannotAuthenticate() async throws {
        let store = InMemoryTokenStore(tokens: makeSessionTokens())
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: false, tokens: nil),
            user: .init(userId: subjectA, username: "reader", email: nil)
        )
        let session = SessionManager(authService: AuthService(
            config: makeAuthConfig(), tokenStore: store, sessionClient: client
        ))

        await session.restoreSession()

        #expect(session.authState == .signedOut)
        #expect(session.currentIdentity == nil)
        #expect(try store.load() == nil)
    }
}

@Suite("Refresh flight")
@MainActor
struct RefreshFlightTests {
    @Test("concurrent reactive refresh callers share one underlying operation")
    func reactiveRefreshIsSingleFlight() async throws {
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: makeSessionTokens()),
            user: .init(userId: subjectA, username: "reader", email: nil),
            suspendRefresh: true
        )
        let store = InMemoryTokenStore(tokens: makeSessionTokens())
        let service = AuthService(config: makeAuthConfig(), tokenStore: store, sessionClient: client)
        let session = SessionManager(authService: service, testIdentity: try makeIdentity())

        let callers = (0..<8).map { _ in Task { try await session.performRefresh() } }
        await client.waitForRefreshCallCount(1)
        await waitForRefreshWaiters(8, on: session)
        #expect(await client.refreshCallCount == 1)

        let refreshed = makeSessionTokens(marker: "refreshed")
        await client.releaseRefresh(with: .success(.init(isSignedIn: true, tokens: refreshed)))
        for caller in callers {
            #expect(try await caller.value == refreshed)
        }
        #expect(try store.load() == refreshed)
    }

    @Test("proactive and reactive refresh join one flight")
    func proactiveAndReactiveShareFlight() async throws {
        let nearExpiry = makeSessionTokens(expiresIn: 30)
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: nearExpiry),
            user: .init(userId: subjectA, username: "reader", email: nil),
            suspendRefresh: true
        )
        let store = InMemoryTokenStore(tokens: nearExpiry)
        let service = AuthService(config: makeAuthConfig(), tokenStore: store, sessionClient: client)
        let session = SessionManager(authService: service, testIdentity: try makeIdentity())

        let proactive = Task { try await session.validToken() }
        await client.waitForRefreshCallCount(1)
        let reactive = Task { try await session.refresh() }
        await waitForRefreshWaiters(2, on: session)
        #expect(await client.refreshCallCount == 1)

        let refreshed = makeSessionTokens(marker: "shared")
        await client.releaseRefresh(with: .success(.init(isSignedIn: true, tokens: refreshed)))
        #expect(try await proactive.value == refreshed.idToken)
        try await reactive.value
        #expect(try store.load() == refreshed)
    }

    @Test("refresh completion after sign-out is discarded")
    func refreshAfterSignOutIsDiscarded() async throws {
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: makeSessionTokens()),
            user: .init(userId: subjectA, username: "reader", email: nil),
            suspendRefresh: true
        )
        let store = InMemoryTokenStore(tokens: makeSessionTokens())
        let service = AuthService(config: makeAuthConfig(), tokenStore: store, sessionClient: client)
        let session = SessionManager(authService: service, testIdentity: try makeIdentity())
        let refresh = Task { try await session.performRefresh() }
        await client.waitForRefreshCallCount(1)

        await session.signOut()
        await client.releaseRefresh(with: .success(.init(
            isSignedIn: true,
            tokens: makeSessionTokens(marker: "stale")
        )))

        await #expect(throws: (any Error).self) { try await refresh.value }
        #expect(session.authState == .signedOut)
        #expect(session.currentIdentity == nil)
        #expect(try store.load() == nil)
    }

    @Test("generation A refresh cannot mutate generation B")
    func oldRefreshCannotMutateNewSession() async throws {
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: makeSessionTokens()),
            user: .init(userId: subjectA, username: "reader-a", email: nil),
            suspendRefresh: true
        )
        let store = InMemoryTokenStore(tokens: makeSessionTokens())
        let service = AuthService(config: makeAuthConfig(), tokenStore: store, sessionClient: client)
        let session = SessionManager(authService: service, testIdentity: try makeIdentity())
        let oldRefresh = Task { try await session.performRefresh() }
        await client.waitForRefreshCallCount(1)

        await session.signOut()
        let tokensB = makeSessionTokens(subject: subjectB, marker: "b")
        await client.setSession(.init(isSignedIn: true, tokens: tokensB))
        await client.setUser(.init(userId: subjectB, username: "reader-b", email: nil))
        try await session.signIn(username: "reader-b", password: "password")
        await client.releaseRefresh(with: .success(.init(
            isSignedIn: true,
            tokens: makeSessionTokens(subject: subjectA, marker: "stale-a")
        )))

        await #expect(throws: (any Error).self) { try await oldRefresh.value }
        #expect(session.currentIdentity?.subject == subjectB)
        #expect(try store.load() == tokensB)
    }

    @Test("cancelling one waiter does not cancel or corrupt the shared refresh")
    func cancelledWaiterDoesNotCorruptFlight() async throws {
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: makeSessionTokens()),
            user: .init(userId: subjectA, username: "reader", email: nil),
            suspendRefresh: true
        )
        let store = InMemoryTokenStore(tokens: makeSessionTokens())
        let service = AuthService(config: makeAuthConfig(), tokenStore: store, sessionClient: client)
        let session = SessionManager(authService: service, testIdentity: try makeIdentity())
        let cancelled = Task { try await session.performRefresh() }
        let survivor = Task { try await session.performRefresh() }
        await client.waitForRefreshCallCount(1)
        await waitForRefreshWaiters(2, on: session)

        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await client.refreshCallCount == 1)

        let refreshed = makeSessionTokens(marker: "survivor")
        await client.releaseRefresh(with: .success(.init(isSignedIn: true, tokens: refreshed)))
        #expect(try await survivor.value == refreshed)
        #expect(try store.load() == refreshed)
    }

    @Test("cancelling one refresh wrapper preserves the shared flight and session")
    func cancelledRefreshWrapperPreservesSession() async throws {
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: makeSessionTokens()),
            user: .init(userId: subjectA, username: "reader", email: nil),
            suspendRefresh: true
        )
        let store = InMemoryTokenStore(tokens: makeSessionTokens())
        let identity = try makeIdentity()
        let session = SessionManager(
            authService: AuthService(
                config: makeAuthConfig(), tokenStore: store, sessionClient: client
            ),
            testIdentity: identity
        )
        let cancelled = Task { try await session.refresh() }
        let survivor = Task { try await session.refresh() }
        await client.waitForRefreshCallCount(1)
        await waitForRefreshWaiters(2, on: session)

        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(session.authState == .signedIn(identity))

        let refreshed = makeSessionTokens(marker: "wrapper-survivor")
        await client.releaseRefresh(with: .success(.init(isSignedIn: true, tokens: refreshed)))
        try await survivor.value
        #expect(session.authState == .signedIn(identity))
        #expect(try store.load() == refreshed)
    }

    @Test("unrecoverable refresh fails closed and drains step-up waiters")
    func unrecoverableRefreshFailsClosed() async throws {
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: makeSessionTokens()),
            user: .init(userId: subjectA, username: "reader", email: nil),
            suspendRefresh: true
        )
        let store = InMemoryTokenStore(tokens: makeSessionTokens())
        let session = SessionManager(
            authService: AuthService(
                config: makeAuthConfig(), tokenStore: store, sessionClient: client
            ),
            testIdentity: try makeIdentity()
        )
        let stepUp = Task { try await session.stepUp() }
        await waitForStepUpWaiters(1, on: session)
        let refresh = Task { try await session.performRefresh() }
        await client.waitForRefreshCallCount(1)

        await client.releaseRefresh(with: .failure(AppError.unauthenticated))

        await #expect(throws: (any Error).self) { try await refresh.value }
        await #expect(throws: (any Error).self) { try await stepUp.value }
        #expect(session.authState == .signedOut)
        #expect(session.currentIdentity == nil)
        #expect(session.stepUpWaiterCount == 0)
        #expect(try store.load() == nil)
    }

    @Test("transient refresh failure preserves identity and mirror")
    func transientRefreshFailurePreservesSession() async throws {
        let original = makeSessionTokens()
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: original),
            user: .init(userId: subjectA, username: "reader", email: nil),
            suspendRefresh: true
        )
        let store = InMemoryTokenStore(tokens: original)
        let identity = try makeIdentity()
        let session = SessionManager(
            authService: AuthService(
                config: makeAuthConfig(), tokenStore: store, sessionClient: client
            ),
            testIdentity: identity
        )
        let refresh = Task { try await session.performRefresh() }
        await client.waitForRefreshCallCount(1)

        await client.releaseRefresh(with: .failure(AppError.offline))

        await #expect(throws: (any Error).self) { try await refresh.value }
        #expect(session.authState == .signedIn(identity))
        #expect(session.currentIdentity == identity)
        #expect(try store.load() == original)
    }

    @Test("authoritative refresh repairs a throwing token mirror")
    func refreshRepairsThrowingMirror() async throws {
        let refreshed = makeSessionTokens(marker: "repaired")
        let store = ThrowingLoadTokenStore(tokens: makeSessionTokens(), loadFailures: 1)
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: refreshed),
            user: .init(userId: subjectA, username: "reader", email: nil)
        )
        let session = SessionManager(
            authService: AuthService(
                config: makeAuthConfig(), tokenStore: store, sessionClient: client
            ),
            testIdentity: try makeIdentity()
        )

        #expect(try await session.validToken() == refreshed.idToken)
        #expect(store.snapshot == refreshed)
        #expect(await client.refreshCallCount == 1)
    }

    @Test("synchronous mirror read never exposes another session identity")
    func currentTokenRejectsCrossAccountMirror() async throws {
        let store = InMemoryTokenStore(tokens: makeSessionTokens(subject: subjectA))
        let session = SessionManager(
            tokenStore: store,
            refresher: StubTokenRefresher(),
            testIdentity: try makeIdentity(subjectB)
        )

        #expect(session.currentIdToken() == nil)
    }
}

@Suite("Step-up lifecycle")
@MainActor
struct StepUpLifecycleTests {
    @Test("step-up success preserves identity and resumes every waiter once")
    func successPreservesIdentity() async throws {
        let identity = try makeIdentity()
        let store = InMemoryTokenStore(tokens: makeSessionTokens())
        let session = SessionManager(
            tokenStore: store,
            refresher: StubTokenRefresher(),
            testIdentity: identity
        )
        let first = Task { try await session.stepUp() }
        let second = Task { try await session.stepUp() }
        await waitForStepUpWaiters(2, on: session)

        session.stepUpCompleted()
        try await first.value
        try await second.value
        session.stepUpCompleted()

        #expect(session.currentIdentity == identity)
        #expect(session.authState == .signedIn(identity))
        #expect(session.stepUpWaiterCount == 0)
    }

    @Test("step-up cancel fails every waiter and signs out")
    func cancellationFailsAllWaiters() async throws {
        let store = InMemoryTokenStore(tokens: makeSessionTokens())
        let session = SessionManager(
            tokenStore: store,
            refresher: StubTokenRefresher(),
            testIdentity: try makeIdentity()
        )
        let first = Task { try await session.stepUp() }
        let second = Task { try await session.stepUp() }
        await waitForStepUpWaiters(2, on: session)

        await session.stepUpCancelled()

        await #expect(throws: (any Error).self) { try await first.value }
        await #expect(throws: (any Error).self) { try await second.value }
        #expect(session.authState == .signedOut)
        #expect(session.currentIdentity == nil)
        #expect(try store.load() == nil)
    }

    @Test("step-up completion cannot create identity")
    func cannotCreateIdentity() {
        let session = SessionManager(tokenStore: InMemoryTokenStore())
        session.stepUpCompleted()
        #expect(session.authState == .signedOut)
        #expect(session.currentIdentity == nil)
    }
}

@Suite("Provider and hermetic boundaries")
@MainActor
struct ProviderBoundaryTests {
    @Test("unavailable Apple path cannot write a token mirror or sign in")
    func appleFailsClosed() async throws {
        let store = InMemoryTokenStore()
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: false, tokens: nil),
            user: .init(userId: subjectA, username: "reader", email: nil)
        )
        let service = AuthService(config: makeAuthConfig(), tokenStore: store, sessionClient: client)
        let sentinelCode = Data("sentinel-authorization-code".utf8)

        await #expect(throws: AuthProviderError.unavailable(.apple)) {
            try await service.signInWithApple(authorizationCode: sentinelCode, name: nil)
        }

        #expect(try store.load() == nil)
        #expect(await client.totalSessionCallCount == 0)
    }

    @Test("hermetic bypass requires bypass, stub, and hermetic flags", arguments: [
        [String: String](),
        ["CF_UITEST_BYPASS_AUTH": "1"],
        ["CF_STUB_SERVER": "1"],
        ["CF_HERMETIC_TEST_CONFIGURATION": "1"],
        ["CF_UITEST_BYPASS_AUTH": "1", "CF_STUB_SERVER": "1"],
        ["CF_UITEST_BYPASS_AUTH": "1", "CF_HERMETIC_TEST_CONFIGURATION": "1"],
        ["CF_STUB_SERVER": "1", "CF_HERMETIC_TEST_CONFIGURATION": "1"],
    ])
    func incompleteHermeticBoundaryFailsClosed(_ environment: [String: String]) {
        #expect(!SessionManager.isHermeticUITestBypass(environment: environment))
    }

    @Test("full hermetic boundary uses one fixed nonempty identity")
    func fullHermeticBoundaryUsesFixedIdentity() throws {
        let environment = [
            "CF_UITEST_BYPASS_AUTH": "1",
            "CF_STUB_SERVER": "1",
            "CF_HERMETIC_TEST_CONFIGURATION": "1",
        ]
        #expect(SessionManager.isHermeticUITestBypass(environment: environment))
        #expect(SessionManager.hermeticUITestIdentity.subject == "uitest-user-123")
        #expect(UserProfile.from(idToken: SessionManager.uitestFakeIDToken)?.sub == "uitest-user-123")
    }

    @Test("auth types and provider errors redact identity and raw auth material")
    func reflectionIsRedacted() throws {
        let sentinelSubject = "sentinel-secret-subject"
        let sentinelEmail = "sentinel@example.com"
        let identity = try #require(SessionIdentity(
            subject: sentinelSubject,
            username: "sentinel-user",
            email: sentinelEmail,
            source: .cognitoUserPool
        ))
        let values = [
            String(describing: identity),
            String(reflecting: identity),
            String(reflecting: identity.userSummary),
            String(describing: CognitoUserSnapshot(
                userId: sentinelSubject,
                username: "sentinel-user",
                email: sentinelEmail
            )),
            String(reflecting: CognitoUserSnapshot(
                userId: sentinelSubject,
                username: "sentinel-user",
                email: sentinelEmail
            )),
            String(reflecting: AuthState.signedIn(identity)),
            String(describing: AuthProviderError.unavailable(.apple)),
            String(reflecting: AuthProviderError.unavailable(.apple)),
        ]

        for value in values {
            #expect(!value.contains(sentinelSubject))
            #expect(!value.contains(sentinelEmail))
            #expect(!value.contains("sentinel-user"))
            #expect(!value.contains("authorization-code"))
        }
    }
}
