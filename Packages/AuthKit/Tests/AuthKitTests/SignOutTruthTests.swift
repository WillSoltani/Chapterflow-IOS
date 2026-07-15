import Foundation
import Persistence
import Testing
@testable import AuthKit

@Suite("Sign-out truth")
@MainActor
struct SignOutTruthTests {
    @Test("sign-out serializes behind an in-flight provider sign-in")
    func signOutClearsLateProviderSignIn() async throws {
        let store = InMemoryTokenStore()
        let signedInSession = CognitoSessionSnapshot(
            isSignedIn: true,
            tokens: makeSessionTokens()
        )
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: false, tokens: nil),
            user: .init(userId: subjectA, username: "reader", email: nil),
            suspendSignIn: true,
            signInSession: signedInSession
        )
        let session = SessionManager(authService: AuthService(
            config: makeAuthConfig(), tokenStore: store, sessionClient: client
        ))

        let signIn = Task { @MainActor in
            try await session.signIn(username: "reader@example.com", password: "password")
        }
        await client.waitForSignInCallCount(1)

        let signOut = Task { @MainActor in await session.signOut() }
        for _ in 0..<200 where session.authState != .unknown {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(session.authState == .unknown)
        #expect(await client.signOutCallCount == 0)

        await client.releaseSignIn(with: .success(.signedIn))

        await #expect(throws: CancellationError.self) { try await signIn.value }
        #expect(await signOut.value)
        await session.restoreSession()
        #expect(session.authState == .signedOut)
        #expect(session.currentIdentity == nil)
        #expect(try store.load() == nil)
    }

    @Test("failed Amplify local sign-out never publishes signed-out success")
    func failedLocalSignOutRestoresAuthoritativeState() async throws {
        let tokens = makeSessionTokens()
        let store = InMemoryTokenStore(tokens: tokens)
        let identity = try makeIdentity()
        let client = ScriptedCognitoSessionClient(
            session: .init(isSignedIn: true, tokens: tokens),
            user: .init(userId: subjectA, username: "reader", email: nil),
            signOutOutcome: .failedLocally
        )
        let session = SessionManager(
            authService: AuthService(
                config: makeAuthConfig(), tokenStore: store, sessionClient: client
            ),
            testIdentity: identity
        )

        #expect(await session.signOut() == false)
        #expect(session.authState == .signedIn(identity))
        #expect(session.currentIdentity == identity)
        #expect(try store.load() == tokens)
    }
}
