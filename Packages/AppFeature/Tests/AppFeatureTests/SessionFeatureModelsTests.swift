import AuthKit
import Foundation
import Persistence
import Testing
@testable import AppFeature

@Suite("Session-owned feature models")
@MainActor
struct SessionFeatureModelsTests {
    @Test("one owner is installed once for repeated observations of scope A")
    func oneOwnerPerScope() async throws {
        let session = try makeSession(subject: "account-a")
        let probe = SessionFeatureModelsProbe()
        let model = makeModel(session: session, probe: probe)

        await model.reconcileCurrentSession()
        let first = try #require(model.activeSessionFeatureModels)
        let firstReviews = first.reviews
        let firstSettings = first.settings

        await model.reconcileCurrentSession()
        await model.reconcileCurrentSession()

        #expect(first.scopeID == model.activeScopeInstanceID)
        #expect(model.activeSessionFeatureModels === first)
        #expect(model.activeSessionFeatureModels?.reviews === firstReviews)
        #expect(model.activeSessionFeatureModels?.settings === firstSettings)
        #expect(probe.constructionCount == 1)
    }

    @Test("one hundred tab evaluations preserve review and settings state")
    func tabEvaluationsPreserveState() async throws {
        let session = try makeSession(subject: "account-a")
        let model = makeModel(session: session)
        await model.reconcileCurrentSession()
        let owner = try #require(model.activeSessionFeatureModels)
        let reviews = owner.reviews
        let settings = owner.settings
        let root = AppRootView(model: model)

        owner.reviews.sessionState = .back
        model.selectedTab = .reviews
        _ = root.tabContent(for: .reviews)
        owner.settings.showDeleteConfirm = true
        model.selectedTab = .settings
        model.selectedTab = .reviews
        _ = root.tabContent(for: .reviews)

        for _ in 0..<100 {
            _ = root.tabContent(for: .reviews)
        }

        #expect(model.activeSessionFeatureModels === owner)
        #expect(model.activeSessionFeatureModels?.reviews === reviews)
        #expect(model.activeSessionFeatureModels?.settings === settings)
        #expect(owner.reviews.sessionState == .back)
        #expect(owner.settings.showDeleteConfirm)
    }

    @Test("successful sign-out clears and releases the owner")
    func successfulSignOutReleasesOwner() async throws {
        let session = try makeSession(subject: "account-a", signOutSucceeds: true)
        let model = makeModel(session: session)
        await model.reconcileCurrentSession()
        weak let owner = model.activeSessionFeatureModels

        await model.signOut()

        #expect(model.activeSessionFeatureModels == nil)
        #expect(owner == nil)
    }

    @Test("failed sign-out retains the exact owner")
    func failedSignOutRetainsOwner() async throws {
        let session = try makeSession(subject: "account-a", signOutSucceeds: false)
        let model = makeModel(session: session)
        await model.reconcileCurrentSession()
        let owner = try #require(model.activeSessionFeatureModels)

        await model.signOut()

        #expect(model.activeSessionFeatureModels === owner)
        #expect(model.sessionScopePhase == .active)
        #expect(model.showsSignOutFailure)
    }

    @Test("the next account receives a fresh owner")
    func nextAccountReceivesFreshOwner() async throws {
        let session = try makeSession(subject: "account-a", signOutSucceeds: true)
        let probe = SessionFeatureModelsProbe()
        let model = makeModel(session: session, probe: probe)
        await model.reconcileCurrentSession()
        let ownerA = try #require(model.activeSessionFeatureModels)

        await model.signOut()
        try session.establishHermeticSession(
            identity: try makeIdentity(subject: "account-b"),
            tokens: makeTokens(marker: "b")
        )
        await model.reconcileCurrentSession()
        let ownerB = try #require(model.activeSessionFeatureModels)

        #expect(ownerB !== ownerA)
        #expect(ownerB.scopeID == model.activeScopeInstanceID)
        #expect(probe.constructionCount == 2)
    }

    @Test("guest and signed-out modes expose no owner")
    func publicModesExposeNoOwner() async {
        let session = SessionManager(tokenStore: InMemoryTokenStore())
        let probe = SessionFeatureModelsProbe()
        let model = makeModel(session: session, probe: probe)

        await model.reconcileCurrentSession()
        #expect(model.activeSessionFeatureModels == nil)

        model.enterGuestMode()
        await model.reconcileCurrentSession()
        #expect(model.activeSessionFeatureModels == nil)
        #expect(probe.constructionCount == 0)
    }

    @Test("a stale owner fails closed before deferred account reconciliation")
    func staleOwnerFailsClosed() async throws {
        let session = try makeSession(subject: "account-a")
        let model = makeModel(session: session)
        await model.reconcileCurrentSession()
        let scopeA = try #require(model.activeSessionScope)
        let ownerA = try #require(model.activeSessionFeatureModels)

        try session.establishHermeticSession(
            identity: try makeIdentity(subject: "account-b"),
            tokens: makeTokens(marker: "b")
        )

        #expect(model.activeSessionScope === scopeA)
        #expect(ownerA.scopeID == scopeA.context.instanceID)
        #expect(model.activeScopeInstanceID == nil)
        #expect(model.activeSessionFeatureModels == nil)
    }

    @Test("tab composition contains no feature-model constructors")
    func tabCompositionContainsNoFeatureModelConstructors() throws {
        let sourceRoot = packageRoot
            .appending(path: "Sources")
            .appending(path: "AppFeature")
        let sources = try ["AppRootView.swift", "AppRootView+TabContent.swift"]
            .map { try String(contentsOf: sourceRoot.appending(path: $0), encoding: .utf8) }
            .joined(separator: "\n")

        #expect(!sources.contains("ReviewsModel("))
        #expect(!sources.contains("SettingsModel("))
    }

    @Test("owner access is checked against the active scope generation")
    func ownerAccessChecksScopeGeneration() throws {
        let source = try String(
            contentsOf: packageRoot
                .appending(path: "Sources")
                .appending(path: "AppFeature")
                .appending(path: "AppModel.swift"),
            encoding: .utf8
        )

        #expect(source.contains(
            "sessionFeatureModelsStorage?.scopeID == activeScopeInstanceID"
        ))
        #expect(source.contains(
            "Session feature model requested without an active matching session scope"
        ))
    }

    private var packageRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
private final class SessionFeatureModelsProbe {
    private(set) var constructionCount = 0

    func build(scope: SessionScope, model: AppModel) -> SessionFeatureModels {
        constructionCount += 1
        return makeTestSessionFeatureModels(scope: scope, model: model)
    }
}

@MainActor
private func makeModel(
    session: SessionManager,
    probe: SessionFeatureModelsProbe = SessionFeatureModelsProbe()
) -> AppModel {
    makeTestAppModel(
        session: session,
        scopeBuilder: { SessionScope(context: $0) },
        sessionFeatureModelsBuilder: { scope, model in
            probe.build(scope: scope, model: model)
        }
    )
}

@MainActor
private func makeSession(
    subject: String,
    signOutSucceeds: Bool = true
) throws -> SessionManager {
    SessionManager(
        tokenStore: InMemoryTokenStore(tokens: makeTokens(marker: subject)),
        refresher: StubTokenRefresher(),
        hermeticIdentity: try makeIdentity(subject: subject),
        hermeticSignOut: { signOutSucceeds }
    )
}

private func makeIdentity(subject: String) throws -> SessionIdentity {
    try #require(SessionIdentity(
        subject: subject,
        username: "Reader",
        email: nil,
        source: .cognitoUserPool
    ))
}

private func makeTokens(marker: String) -> StoredTokens {
    StoredTokens(
        idToken: "id-\(marker)",
        accessToken: "access-\(marker)",
        refreshToken: "refresh-\(marker)",
        expiresAt: Date().addingTimeInterval(3_600)
    )
}
