import Testing
import Foundation
@testable import AppFeature
import AuthKit

// MARK: - Stub

private struct StubIdentityLoader: IdentityLoading {
    var sessionResult: SessionLoadResult = .valid
    var profileFixture: UserProfile = .fixture
    var sessionError: Bool = false
    var profileError: Bool = false

    func loadSession() async throws -> SessionLoadResult {
        if sessionError { throw URLError(.notConnectedToInternet) }
        return sessionResult
    }

    func loadProfile() async throws -> UserProfile {
        if profileError { throw URLError(.notConnectedToInternet) }
        return profileFixture
    }
}

private extension UserProfile {
    static let fixture = UserProfile(
        sub: "sub-abc123",
        email: "test@example.com",
        displayName: "Test User"
    )
}

// MARK: - Helpers

private func makeStore() -> UserProfileStore {
    UserProfileStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
}

// MARK: - Tests

@Suite("AppModel bootstrap")
@MainActor
struct AppRootModelTests {

    @Test("no tokens → signedOut immediately, bootstrap is a no-op")
    func signedOutWithNoTokens() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore())
        let model = AppModel(session: session, identityLoader: StubIdentityLoader(), profileStore: makeStore())

        #expect(model.launchState == .signedOut)

        await model.bootstrap()

        #expect(model.launchState == .signedOut)
        #expect(model.currentUser == nil)
    }

    @Test("tokens present → loading on init, signedIn after bootstrap")
    func signedInAfterSuccessfulBootstrap() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore(idToken: "tok", refreshToken: "ref"))
        let loader = StubIdentityLoader(sessionResult: .valid, profileFixture: .fixture)
        let model = AppModel(session: session, identityLoader: loader, profileStore: makeStore())

        #expect(model.launchState == .loading)

        await model.bootstrap()

        #expect(model.launchState == .signedIn)
        #expect(model.currentUser == .fixture)
    }

    @Test("session check returns invalid → signedOut, tokens cleared")
    func signedOutWhenSessionInvalid() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore(idToken: "tok", refreshToken: "ref"))
        let loader = StubIdentityLoader(sessionResult: .invalid)
        let model = AppModel(session: session, identityLoader: loader, profileStore: makeStore())

        await model.bootstrap()

        #expect(model.launchState == .signedOut)
        #expect(model.currentUser == nil)
        #expect(session.authState == .signedOut)
    }

    @Test("session check returns deactivated → accountDeactivated")
    func accountDeactivatedWhenSessionDeactivated() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore(idToken: "tok", refreshToken: "ref"))
        let loader = StubIdentityLoader(sessionResult: .deactivated)
        let model = AppModel(session: session, identityLoader: loader, profileStore: makeStore())

        await model.bootstrap()

        #expect(model.launchState == .accountDeactivated)
    }

    @Test("session check returns deleted → accountDeleted")
    func accountDeletedWhenSessionDeleted() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore(idToken: "tok", refreshToken: "ref"))
        let loader = StubIdentityLoader(sessionResult: .deleted)
        let model = AppModel(session: session, identityLoader: loader, profileStore: makeStore())

        await model.bootstrap()

        #expect(model.launchState == .accountDeleted)
    }

    @Test("profile accountStatus deactivated → accountDeactivated")
    func accountDeactivatedFromProfile() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore(idToken: "tok", refreshToken: "ref"))
        let deactivatedProfile = UserProfile(
            sub: "sub", email: "x@x.com", displayName: "X",
            accountStatus: .deactivated
        )
        let loader = StubIdentityLoader(sessionResult: .valid, profileFixture: deactivatedProfile)
        let model = AppModel(session: session, identityLoader: loader, profileStore: makeStore())

        await model.bootstrap()

        #expect(model.launchState == .accountDeactivated)
    }

    @Test("network error + cached profile → stays signedIn")
    func networkErrorWithCachedProfileStaysSignedIn() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore(idToken: "tok", refreshToken: "ref"))
        let loader = StubIdentityLoader(sessionError: true)
        let store = makeStore()
        store.save(.fixture)
        let model = AppModel(session: session, identityLoader: loader, profileStore: store)

        await model.bootstrap()

        #expect(model.launchState == .signedIn)
        #expect(model.currentUser == .fixture)
    }

    @Test("network error + no cached profile → signedOut")
    func networkErrorNoCacheSignsOut() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore(idToken: "tok", refreshToken: "ref"))
        let loader = StubIdentityLoader(sessionError: true)
        let model = AppModel(session: session, identityLoader: loader, profileStore: makeStore())

        await model.bootstrap()

        #expect(model.launchState == .signedOut)
    }

    @Test("profile cached → surfaced immediately, then overwritten by server profile")
    func cachedProfileSurfacedThenRefreshed() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore(idToken: "tok", refreshToken: "ref"))
        let loader = StubIdentityLoader(sessionResult: .valid, profileFixture: .fixture)
        let store = makeStore()
        let stale = UserProfile(sub: "old", email: "old@example.com", displayName: "Old User")
        store.save(stale)
        let model = AppModel(session: session, identityLoader: loader, profileStore: store)

        await model.bootstrap()

        // After bootstrap the fresh server profile replaces the cached one.
        #expect(model.currentUser == .fixture)
        #expect(store.load() == .fixture)
    }

    @Test("profile fetch error + valid session → stays signedIn with cached data")
    func profileFetchErrorWithCacheStaysSignedIn() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore(idToken: "tok", refreshToken: "ref"))
        let loader = StubIdentityLoader(sessionResult: .valid, profileError: true)
        let store = makeStore()
        store.save(.fixture)
        let model = AppModel(session: session, identityLoader: loader, profileStore: store)

        await model.bootstrap()

        #expect(model.launchState == .signedIn)
        #expect(model.currentUser == .fixture)
    }

    @Test("signOut clears identity and returns to auth flow")
    func signOutClearsEverything() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore(idToken: "tok", refreshToken: "ref"))
        let loader = StubIdentityLoader(sessionResult: .valid, profileFixture: .fixture)
        let store = makeStore()
        let model = AppModel(session: session, identityLoader: loader, profileStore: store)

        await model.bootstrap()
        #expect(model.launchState == .signedIn)

        model.signOut()

        #expect(model.launchState == .signedOut)
        #expect(model.currentUser == nil)
        #expect(store.load() == nil)
        #expect(session.authState == .signedOut)
    }

    @Test("handleSessionSignOut clears identity without double-signing-out session")
    func handleSessionSignOutClearsIdentity() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore(idToken: "tok", refreshToken: "ref"))
        let loader = StubIdentityLoader(sessionResult: .valid, profileFixture: .fixture)
        let store = makeStore()
        let model = AppModel(session: session, identityLoader: loader, profileStore: store)

        await model.bootstrap()
        #expect(model.launchState == .signedIn)

        model.handleSessionSignOut()

        #expect(model.launchState == .signedOut)
        #expect(model.currentUser == nil)
        #expect(store.load() == nil)
    }

    @Test("deep-link routing unaffected by identity changes")
    func deepLinkRoutingStillWorks() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore())
        let model = AppModel(session: session)

        model.handle(url: URL(string: "chapterflow://book/abc123")!)
        #expect(model.selectedTab == .library)

        model.handle(url: URL(string: "chapterflow://review")!)
        #expect(model.selectedTab == .reviews)
    }
}
