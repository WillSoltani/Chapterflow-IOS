import AuthKit
import CoreKit
import Foundation
import Persistence
import Testing
@testable import AppFeature

@Suite("Account session scope lifecycle")
@MainActor
struct SessionScopeLifecycleTests {
    @Test("signed-out and guest modes construct zero private scopes")
    func guestHasNoPrivateScope() async throws {
        let session = SessionManager(tokenStore: InMemoryTokenStore())
        let probe = LifecycleProbe()
        let model = makeTestAppModel(session: session, scopeBuilder: builder(probe))

        model.enterGuestMode()
        await model.reconcileCurrentSession()

        #expect(model.activeSessionScope == nil)
        #expect(model.sessionScopePhase == .none)
        #expect(await probe.events.isEmpty)
        #expect(try await model.libraryRepository.getProgressOverview().progress.isEmpty)
        #expect(try await model.libraryRepository.getSaved().isEmpty)
        let libraryError = await #expect(throws: AppError.self) {
            _ = try await model.libraryRepository.toggleSaved(bookId: "book", saved: true)
        }
        let detailError = await #expect(throws: AppError.self) {
            _ = try await model.bookDetailRepository.startBook(id: "book")
        }
        assertUnauthenticated(libraryError)
        assertUnauthenticated(detailError)
    }

    @Test("signed-in A constructs and activates exactly one scope")
    func signedInConstructsOneScope() async throws {
        let session = try signedInSession(subject: "account-a")
        let probe = LifecycleProbe()
        let model = makeTestAppModel(session: session, scopeBuilder: builder(probe))

        await model.reconcileCurrentSession()

        #expect(model.activeSessionScope?.context.accountID == "account-a")
        #expect(model.sessionScopePhase == .active)
        #expect(await probe.events == ["construct:account-a", "activate:account-a"])
    }

    @Test("repeated A observations retain the exact same scope")
    func repeatedIdentityRetainsScope() async throws {
        let session = try signedInSession(subject: "account-a")
        let probe = LifecycleProbe()
        let model = makeTestAppModel(session: session, scopeBuilder: builder(probe))
        await model.reconcileCurrentSession()
        let first = try #require(model.activeSessionScope)

        await model.reconcileCurrentSession()
        await model.reconcileCurrentSession()

        #expect(model.activeSessionScope === first)
        #expect(await probe.events == ["construct:account-a", "activate:account-a"])
    }

    @Test("repeated SwiftUI root recomposition does not recreate the scope")
    func rootRecompositionRetainsScope() async throws {
        let session = try signedInSession(subject: "account-a")
        let probe = LifecycleProbe()
        let model = makeTestAppModel(session: session, scopeBuilder: builder(probe))
        await model.reconcileCurrentSession()
        let first = try #require(model.activeSessionScope)
        let firstRootValue = AppRootView(model: model)
        let secondRootValue = AppRootView(model: model)

        _ = firstRootValue
        _ = secondRootValue

        #expect(model.activeSessionScope === first)
        #expect(await probe.events == ["construct:account-a", "activate:account-a"])
    }

    @Test("quiesce closes the general private-work permit before dependency teardown")
    func quiesceClosesPermitBeforeDependencies() async throws {
        let context = AccountContext(
            identity: try identity(subject: "account-a"),
            config: makeTestValidatedConfig()
        )
        let permit = SessionWorkPermit()
        let observed = PermitStateProbe()
        let scope = SessionScope(
            context: context,
            permit: permit,
            operations: SessionScopeOperations(
                activate: {},
                quiesce: { await observed.record(permit.currentState()) },
                resume: {},
                invalidate: {}
            )
        )
        await scope.activate()

        await scope.quiesce()

        #expect(await observed.state == .quiesced)
        await #expect(throws: CancellationError.self) {
            _ = try permit.begin()
        }
    }

    @Test("B is not constructed until A sign-out has completed final teardown")
    func accountSwitchOrdersFinalizationBeforeConstruction() async throws {
        let session = try signedInSession(subject: "account-a")
        let probe = LifecycleProbe()
        let model = makeTestAppModel(session: session, scopeBuilder: builder(probe))
        await model.reconcileCurrentSession()

        await model.signOut()
        try session.establishHermeticSession(
            identity: try identity(subject: "account-b"),
            tokens: tokens(marker: "b")
        )
        await model.reconcileCurrentSession()

        let events = await probe.events
        #expect(events == [
            "construct:account-a",
            "activate:account-a",
            "quiesce:account-a",
            "invalidate:account-a",
            "construct:account-b",
            "activate:account-b",
        ])
        #expect(model.activeSessionScope?.context.accountID == "account-b")
    }

    @Test("A stops vending synchronously when the authoritative identity becomes B")
    func identityMismatchFailsClosedBeforeDeferredReconciliation() async throws {
        let session = try signedInSession(subject: "account-a")
        let probe = LifecycleProbe()
        let model = makeTestAppModel(session: session, scopeBuilder: builder(probe))
        await model.reconcileCurrentSession()
        let scopeA = try #require(model.activeSessionScope)

        #expect(model.hasActiveMatchingSessionScope)
        #expect(model.activeScopeInstanceID == scopeA.context.instanceID)

        try session.establishHermeticSession(
            identity: try identity(subject: "account-b"),
            tokens: tokens(marker: "b")
        )

        // The auth observer deliberately reconciles on a later main-actor turn.
        // Private presentation authority must already be closed in this gap.
        #expect(model.activeSessionScope === scopeA)
        #expect(!model.hasActiveMatchingSessionScope)
        #expect(model.activeScopeInstanceID == nil)

        await model.reconcileCurrentSession()
        #expect(model.activeSessionScope == nil)
        #expect(model.sessionScopePhase == .failure)
        #expect(!model.hasActiveMatchingSessionScope)
    }

    @Test("scope constructors receive the exact proven A and B identities")
    func constructorsReceiveExactIdentity() async throws {
        let session = try signedInSession(subject: "exact-subject-a")
        let probe = LifecycleProbe()
        let model = makeTestAppModel(session: session, scopeBuilder: builder(probe))
        await model.reconcileCurrentSession()
        await model.signOut()
        try session.establishHermeticSession(
            identity: try identity(subject: "exact-subject-b"),
            tokens: tokens(marker: "b")
        )
        await model.reconcileCurrentSession()

        let constructedAccounts = await probe.constructedAccounts
        #expect(constructedAccounts == ["exact-subject-a", "exact-subject-b"])
    }

    @Test("StoreKit composition accepts the exact UUID Cognito subject")
    func storeKitBindingUsesExactAccountIdentity() throws {
        let context = AccountContext(
            identity: try identity(subject: "8f14e45f-ea4f-4a1b-8c32-07bbf1cdb22f"),
            config: makeTestValidatedConfig()
        )

        #expect(SessionPrivateGraph.storeKitAccountBinding(for: context) != nil)
    }

    @Test("StoreKit composition leaves invalid Cognito identity purchase-unavailable")
    func invalidStoreKitBindingFailsClosed() throws {
        let context = AccountContext(
            identity: try identity(subject: "not-a-uuid"),
            config: makeTestValidatedConfig()
        )

        #expect(SessionPrivateGraph.storeKitAccountBinding(for: context) == nil)
    }

    @Test("successful sign-out quiesces and invalidates dependencies once")
    func successfulSignOutStopsOnce() async throws {
        let session = try signedInSession(subject: "account-a")
        let probe = LifecycleProbe()
        let model = makeTestAppModel(session: session, scopeBuilder: builder(probe))
        await model.reconcileCurrentSession()

        await model.signOut()
        await model.signOut()

        #expect(model.activeSessionScope == nil)
        #expect(session.authState == .signedOut)
        #expect(await probe.count(prefix: "quiesce:") == 1)
        #expect(await probe.count(prefix: "invalidate:") == 1)
    }

    @Test("signed-out entry remains closed until the app transaction finishes teardown")
    func signedOutEntryWaitsForTransactionTeardown() async throws {
        let identity = try identity(subject: "account-a")
        let session = SessionManager(
            tokenStore: InMemoryTokenStore(tokens: tokens(marker: "a")),
            hermeticIdentity: identity,
            hermeticSignOut: { true }
        )
        let gate = ControlledInvalidationGate()
        let model = makeTestAppModel(session: session) { context in
            SessionScope(
                context: context,
                operations: SessionScopeOperations(
                    activate: {},
                    quiesce: {},
                    resume: {},
                    invalidate: { await gate.perform() }
                )
            )
        }
        await model.reconcileCurrentSession()

        let signOut = Task { @MainActor in await model.signOut() }
        await gate.waitUntilStarted()

        #expect(session.authState == .signedOut)
        #expect(model.isCoordinatingSignOut)
        #expect(model.sessionScopePhase == .quiescing)
        #expect(!model.canPresentSignedOutEntry)

        await gate.release()
        await signOut.value

        #expect(model.canPresentSignedOutEntry)
    }

    @Test("authoritative signed-out observation blocks entry until old scope teardown")
    func signedOutEntryWaitsForObservedTeardown() async throws {
        let session = try signedInSession(subject: "account-a")
        let gate = ControlledInvalidationGate()
        let model = makeTestAppModel(session: session) { context in
            SessionScope(
                context: context,
                operations: SessionScopeOperations(
                    activate: {},
                    quiesce: {},
                    resume: {},
                    invalidate: { await gate.perform() }
                )
            )
        }
        await model.reconcileCurrentSession()

        #expect(await session.signOut())
        #expect(session.authState == .signedOut)
        #expect(!model.canPresentSignedOutEntry)

        let reconcile = Task { @MainActor in await model.reconcileCurrentSession() }
        await gate.waitUntilStarted()
        #expect(model.sessionScopePhase == .quiescing)
        #expect(!model.canPresentSignedOutEntry)

        await gate.release()
        await reconcile.value
        #expect(model.canPresentSignedOutEntry)
    }

    @Test("failed provider sign-out resumes the exact A scope")
    func failedSignOutResumesSameScope() async throws {
        let identity = try identity(subject: "account-a")
        let gate = ControlledSignOutGate(outcome: false)
        let session = SessionManager(
            tokenStore: InMemoryTokenStore(tokens: tokens(marker: "a")),
            hermeticIdentity: identity,
            hermeticSignOut: { await gate.perform() }
        )
        let probe = LifecycleProbe()
        let model = makeTestAppModel(session: session, scopeBuilder: builder(probe))
        await model.reconcileCurrentSession()
        let original = try #require(model.activeSessionScope)

        let signOut = Task { @MainActor in await model.signOut() }
        await gate.waitForSignOut()
        await model.reconcileCurrentSession()
        await gate.releaseSignOut()
        await signOut.value

        #expect(model.activeSessionScope === original)
        #expect(original.state == .active)
        #expect(session.currentIdentity == identity)
        #expect(model.showsSignOutFailure)
        #expect(await probe.count(prefix: "quiesce:") == 1)
        #expect(await probe.count(prefix: "resume:") == 1)
        #expect(await probe.count(prefix: "invalidate:") == 0)

        model.dismissSignOutFailure()
        #expect(!model.showsSignOutFailure)
    }

    @Test("reader presentation is suppressed without the exact active scope")
    func readerPresentationFailsClosed() {
        let flow = ReadingFlow(
            bookId: "book-a",
            chapterNumber: 2,
            variantFamily: .emh
        )

        #expect(SessionPrivatePresentationGate.item(
            flow,
            hasActiveMatchingScope: true
        ) == flow)
        #expect(SessionPrivatePresentationGate.item(
            flow,
            hasActiveMatchingScope: false
        ) == nil)
    }

    @Test("stale unknown observer during coordinated sign-out cannot destroy A")
    func staleObserverIsIgnored() async throws {
        let identity = try identity(subject: "account-a")
        let gate = ControlledSignOutGate(outcome: false)
        let session = SessionManager(
            tokenStore: InMemoryTokenStore(tokens: tokens(marker: "a")),
            hermeticIdentity: identity,
            hermeticSignOut: { await gate.perform() }
        )
        let probe = LifecycleProbe()
        let model = makeTestAppModel(session: session, scopeBuilder: builder(probe))
        await model.reconcileCurrentSession()
        let original = try #require(model.activeSessionScope)

        let signOut = Task { @MainActor in await model.signOut() }
        await gate.waitForSignOut()
        #expect(session.authState == .unknown)
        await model.reconcileCurrentSession()
        #expect(model.activeSessionScope === original)
        #expect(original.state == .quiesced)
        await gate.releaseSignOut()
        await signOut.value
        #expect(model.activeSessionScope === original)
    }

    @Test("cancelled A preparation cannot publish a stale scope after B")
    func cancelledPreparationCannotPublish() async throws {
        let session = try signedInSession(subject: "account-a")
        let gate = ScopeBuildGate(blockedAccount: "account-a")
        let probe = LifecycleProbe()
        let model = makeTestAppModel(session: session) { context in
            await probe.record("construct:\(context.accountID)")
            try await gate.waitIfBlocked(account: context.accountID)
            return makeScope(context: context, probe: probe)
        }

        let prepareA = Task { @MainActor in await model.reconcileCurrentSession() }
        await gate.waitUntilStarted()
        try session.establishHermeticSession(
            identity: try identity(subject: "account-b"),
            tokens: tokens(marker: "b")
        )
        await model.reconcileCurrentSession()
        await prepareA.value

        #expect(model.activeSessionScope?.context.accountID == "account-b")
        #expect(await probe.count(prefix: "activate:account-a") == 0)
        #expect(await probe.count(prefix: "activate:account-b") == 1)
    }

    @Test("scope preparation failure publishes no prior account content")
    func preparationFailureHasNoScope() async throws {
        let session = try signedInSession(subject: "account-a")
        let model = makeTestAppModel(session: session) { _ in
            throw AccountPersistenceLoadFailure.persistentStoreOpenOrMigration
        }

        await model.reconcileCurrentSession()

        #expect(model.activeSessionScope == nil)
        #expect(model.sessionScopePhase == .failure)
    }

    @Test("successful sign-out releases the scope while process services survive")
    func scopeDeallocatesAndProcessEnvironmentSurvives() async throws {
        let session = try signedInSession(subject: "account-a")
        let probe = LifecycleProbe()
        let model = makeTestAppModel(session: session, scopeBuilder: builder(probe))
        let processConfigService = model.appConfigService
        await model.reconcileCurrentSession()
        weak let weakScope = model.activeSessionScope

        await model.signOut()

        #expect(weakScope == nil)
        #expect(model.activeSessionScope == nil)
        #expect(model.appConfigService === processConfigService)
    }

    private func builder(
        _ probe: LifecycleProbe
    ) -> @MainActor (AccountContext) async throws -> SessionScope {
        { context in
            await probe.record("construct:\(context.accountID)")
            return makeScope(context: context, probe: probe)
        }
    }
}

@MainActor
private func makeScope(context: AccountContext, probe: LifecycleProbe) -> SessionScope {
    SessionScope(
        context: context,
        operations: SessionScopeOperations(
            activate: { await probe.record("activate:\(context.accountID)") },
            quiesce: { await probe.record("quiesce:\(context.accountID)") },
            resume: { await probe.record("resume:\(context.accountID)") },
            invalidate: { await probe.record("invalidate:\(context.accountID)") }
        )
    )
}

private actor LifecycleProbe {
    private(set) var events: [String] = []

    var constructedAccounts: [String] {
        events.compactMap { event in
            guard event.hasPrefix("construct:") else { return nil }
            return String(event.dropFirst("construct:".count))
        }
    }

    func record(_ event: String) {
        events.append(event)
    }

    func count(prefix: String) -> Int {
        events.count { $0.hasPrefix(prefix) }
    }
}

private actor PermitStateProbe {
    private(set) var state: SessionWorkPermit.State?

    func record(_ state: SessionWorkPermit.State) {
        self.state = state
    }
}

private actor ScopeBuildGate {
    private let blockedAccount: String
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var buildContinuation: CheckedContinuation<Void, Error>?

    init(blockedAccount: String) {
        self.blockedAccount = blockedAccount
    }

    func waitIfBlocked(account: String) async throws {
        guard account == blockedAccount else { return }
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                buildContinuation = continuation
            }
        } onCancel: {
            Task { await self.cancelBuild() }
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    private func cancelBuild() {
        buildContinuation?.resume(throwing: CancellationError())
        buildContinuation = nil
    }
}

private actor ControlledSignOutGate {
    private let outcome: Bool
    private var didRequestSignOut = false
    private var signOutWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(outcome: Bool) {
        self.outcome = outcome
    }

    func perform() async -> Bool {
        didRequestSignOut = true
        let waiters = signOutWaiters
        signOutWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return outcome
    }

    func waitForSignOut() async {
        guard !didRequestSignOut else { return }
        await withCheckedContinuation { continuation in
            signOutWaiters.append(continuation)
        }
    }

    func releaseSignOut() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor ControlledInvalidationGate {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func perform() async {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private func signedInSession(subject: String) throws -> SessionManager {
    SessionManager(
        tokenStore: InMemoryTokenStore(tokens: tokens(marker: subject)),
        refresher: StubTokenRefresher(),
        hermeticIdentity: try identity(subject: subject)
    )
}

private func assertUnauthenticated(_ error: AppError?) {
    guard let error else { return }
    guard case .unauthenticated = error else {
        Issue.record("Expected a closed unauthenticated boundary")
        return
    }
}

private func identity(subject: String) throws -> SessionIdentity {
    try #require(SessionIdentity(
        subject: subject,
        username: "Reader",
        email: nil,
        source: .cognitoUserPool
    ))
}

private func tokens(marker: String) -> StoredTokens {
    StoredTokens(
        idToken: "id-\(marker)",
        accessToken: "access-\(marker)",
        refreshToken: "refresh-\(marker)",
        expiresAt: Date().addingTimeInterval(3_600)
    )
}
