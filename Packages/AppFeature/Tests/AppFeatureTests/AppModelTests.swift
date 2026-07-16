import AuthKit
import CoreKit
import Foundation
import LibraryFeature
import Models
import Persistence
import Testing
@testable import AppFeature

@Suite("AppModel deep-link routing — custom scheme")
@MainActor
struct AppModelTests {
    @Test("book URL routes to the exact Library detail")
    func bookURLRoutesToLibrary() {
        let (model, _) = makeSignedOutRouteModel()

        model.handle(url: URL(string: "chapterflow://book/abc123")!)

        #expect(model.selectedTab == .library)
        #expect(model.libraryRouter.depth == 1)
    }

    @Test("chapter URL routes to the exact reader chapter")
    func chapterURLRoutesToReader() async throws {
        let (model, _) = try await makeActiveRouteModel()

        model.handle(url: URL(string: "chapterflow://book/abc123/chapter/3")!)

        #expect(model.pendingHandoffFlow?.bookId == "abc123")
        #expect(model.pendingHandoffFlow?.chapterNumber == 3)
    }

    @Test("review URL routes to reviews tab")
    func reviewURLRoutesToReviews() async throws {
        let (model, _) = try await makeActiveRouteModel()
        model.handle(url: URL(string: "chapterflow://review")!)
        #expect(model.selectedTab == .reviews)
    }

    @Test("pair accept URL routes exact code to profile")
    func pairAcceptRoutesToProfile() async throws {
        let (model, _) = try await makeActiveRouteModel()
        model.handle(url: URL(string: "chapterflow://pair/accept/XYZ")!)
        #expect(model.selectedTab == .profile)
        #expect(model.pendingPairAcceptCode == "XYZ")
    }

    @Test("gift URL routes exact code to profile")
    func giftURLRoutesToProfile() async throws {
        let (model, _) = try await makeActiveRouteModel()
        model.handle(url: URL(string: "chapterflow://gift/GIFTCODE")!)
        #expect(model.selectedTab == .profile)
        #expect(model.pendingGiftCode == "GIFTCODE")
    }

    @Test("referral URL routes exact code to profile")
    func referralURLRoutesToProfile() async throws {
        let (model, _) = try await makeActiveRouteModel()
        model.handle(url: URL(string: "chapterflow://ref/ALICE42")!)
        #expect(model.selectedTab == .profile)
        #expect(model.pendingReferralCode == "ALICE42")
    }

    @Test("paywall URL presents the paywall")
    func paywallURLPresentsPaywall() async throws {
        let (model, _) = try await makeActiveRouteModel()
        model.handle(url: URL(string: "chapterflow://paywall")!)
        #expect(model.showPaywall)
    }

    @Test("journey URL retains the safe Home fallback")
    func journeyURLRoutesToHome() async throws {
        let (model, _) = try await makeActiveRouteModel()
        model.selectedTab = .library
        model.handle(url: URL(string: "chapterflow://journey/j-summer")!)
        #expect(model.selectedTab == .home)
    }

    @Test("event URL retains the safe Home fallback")
    func eventURLRoutesToHome() async throws {
        let (model, _) = try await makeActiveRouteModel()
        model.selectedTab = .library
        model.handle(url: URL(string: "chapterflow://event/ev-nov")!)
        #expect(model.selectedTab == .home)
    }

    @Test("unrecognised chapterflow path leaves state unchanged")
    func unknownPathIgnored() {
        let (model, _) = makeSignedOutRouteModel()
        model.handle(url: URL(string: "chapterflow://unknown-feature")!)
        #expect(model.selectedTab == .home)
        #expect(model.pendingNavigationRequest == nil)
    }
}

// MARK: - Universal Link routing

@Suite("AppModel deep-link routing — Universal Links")
@MainActor
struct AppModelUniversalLinkTests {
    @Test("Universal Link book URL routes to exact Library detail")
    func universalLinkBookRoutesToLibrary() {
        let (model, _) = makeSignedOutRouteModel()
        model.handle(url: URL(string: "https://app.chapterflow.ca/book/abc123")!)
        #expect(model.selectedTab == .library)
        #expect(model.libraryRouter.depth == 1)
    }

    @Test("Universal Link chapter URL preserves exact chapter")
    func universalLinkChapterRoutesToReader() async throws {
        let (model, _) = try await makeActiveRouteModel()
        model.handle(url: URL(string: "https://app.chapterflow.ca/book/abc123/chapter/3")!)
        #expect(model.pendingHandoffFlow?.bookId == "abc123")
        #expect(model.pendingHandoffFlow?.chapterNumber == 3)
    }

    @Test("Universal Link review URL routes to reviews tab")
    func universalLinkReviewRoutesToReviews() async throws {
        let (model, _) = try await makeActiveRouteModel()
        model.handle(url: URL(string: "https://app.chapterflow.ca/review")!)
        #expect(model.selectedTab == .reviews)
    }

    @Test("Universal Link pair accept preserves exact code")
    func universalLinkPairAcceptRoutesToProfile() async throws {
        let (model, _) = try await makeActiveRouteModel()
        model.handle(url: URL(string: "https://app.chapterflow.ca/pair/accept/XYZ")!)
        #expect(model.selectedTab == .profile)
        #expect(model.pendingPairAcceptCode == "XYZ")
    }

    @Test("Universal Link gift preserves exact code")
    func universalLinkGiftRoutesToProfile() async throws {
        let (model, _) = try await makeActiveRouteModel()
        model.handle(url: URL(string: "https://app.chapterflow.ca/gift/GIFTCODE")!)
        #expect(model.selectedTab == .profile)
        #expect(model.pendingGiftCode == "GIFTCODE")
    }

    @Test("Universal Link paywall presents paywall")
    func universalLinkPaywallPresentsPaywall() async throws {
        let (model, _) = try await makeActiveRouteModel()
        model.handle(url: URL(string: "https://app.chapterflow.ca/paywall")!)
        #expect(model.showPaywall)
    }

    @Test("wrong-domain https URL is ignored")
    func wrongDomainIgnored() {
        let (model, _) = makeSignedOutRouteModel()
        model.handle(url: URL(string: "https://evil.com/book/abc123")!)
        #expect(model.selectedTab == .home)
        #expect(model.pendingNavigationRequest == nil)
    }
}

// MARK: - Handoff (WP-NAV-01B retains ownership)

@Suite("AppModel — Handoff")
@MainActor
struct AppModelHandoffTests {
    @Test("handleHandoff preserves book, chapter, and variant")
    func handoffSetsFlow() {
        let model = makeTestAppModel()
        model.handleHandoff(bookId: "book-abc", chapterNumber: 3, variantFamilyRaw: "EMH")
        #expect(model.pendingHandoffFlow?.bookId == "book-abc")
        #expect(model.pendingHandoffFlow?.chapterNumber == 3)
        #expect(model.pendingHandoffFlow?.variantFamily == .emh)
    }

    @Test("handleHandoff with nil variant defaults to EMH")
    func handoffDefaultsVariantFamily() {
        let model = makeTestAppModel()
        model.handleHandoff(bookId: "book-xyz", chapterNumber: 1, variantFamilyRaw: nil)
        #expect(model.pendingHandoffFlow?.variantFamily == .emh)
    }

    @Test("handleHandoff preserves an unknown variant")
    func handoffUnknownVariantFamily() {
        let model = makeTestAppModel()
        model.handleHandoff(
            bookId: "book-xyz",
            chapterNumber: 2,
            variantFamilyRaw: "FUTURE_FORMAT"
        )
        #expect(model.pendingHandoffFlow?.variantFamily == .unknown("FUTURE_FORMAT"))
    }
}

// MARK: - Guest mode and existing auth intents

@Suite("AppModel — guest mode")
@MainActor
struct AppModelGuestTests {
    @Test("enterGuestMode sets guest presentation")
    func enterGuestModeSetsFlag() {
        let (model, _) = makeSignedOutRouteModel()
        #expect(!model.isGuestMode)
        model.enterGuestMode()
        #expect(model.isGuestMode)
    }

    @Test("requestAuth stores the first existing auth intent")
    func requestAuthSetsIntentAndShowsGate() {
        let (model, _) = makeSignedOutRouteModel()
        let first = AuthGateIntent.startBook(bookId: "b-test", variantFamily: .emh)
        model.enterGuestMode()
        model.requestAuth(intent: first)
        model.requestAuth(intent: .startBook(bookId: "b-later", variantFamily: .emh))
        #expect(model.showAuthGate)
        #expect(model.pendingAuthIntent == first)
    }

    @Test("requestAuth with none presents a generic gate")
    func requestAuthNoneShowsGate() {
        let (model, _) = makeSignedOutRouteModel()
        model.enterGuestMode()
        model.requestAuth(intent: .none)
        #expect(model.showAuthGate)
        #expect(model.pendingAuthIntent.isNone)
    }

    @Test("guest book URL opens exact public detail without auth")
    func guestBookURLRoutesToLibrary() {
        let (model, _) = makeSignedOutRouteModel()
        model.enterGuestMode()
        model.handle(url: URL(string: "chapterflow://book/abc123")!)
        #expect(model.selectedTab == .library)
        #expect(!model.showAuthGate)
        #expect(model.libraryRouter.depth == 1)
    }

    @Test("guest private URL preserves a typed request and gates auth")
    func guestGatedURLTriggersAuthGate() {
        let (model, _) = makeSignedOutRouteModel()
        model.enterGuestMode()
        model.handle(url: URL(string: "chapterflow://review")!)
        #expect(model.showAuthGate)
        #expect(model.pendingNavigationRequest == .review)
        #expect(model.selectedTab == .home)
    }

    @Test("legacy auth intent cannot replay before private scope authority")
    func replayIntentWaitsForScope() async {
        let (model, _) = makeSignedOutRouteModel()
        let intent = AuthGateIntent.startBook(bookId: "b-atomic-habits", variantFamily: .emh)
        model.enterGuestMode()
        model.requestAuth(intent: intent)

        var readingFlowSet: ReadingFlow?
        await model.replayPendingIntent { readingFlowSet = $0 }

        #expect(model.pendingAuthIntent == intent)
        #expect(model.isGuestMode)
        #expect(readingFlowSet == nil)
    }
}

// MARK: - WP-NAV-01A exact-route regressions

@Suite("AppModel — exact route regressions")
@MainActor
struct AppModelExactRouteRegressionTests {
    @Test("signed-in book route replaces the stack with one exact detail")
    func signedInBookRoutePushesExactDetailOnce() async throws {
        let (model, _) = try await makeActiveRouteModel()

        model.handle(deepLink: .book(id: "b-exact"))
        model.handle(deepLink: .book(id: "b-exact"))

        #expect(model.selectedTab == .library)
        #expect(model.libraryRouter.depth == 1)
    }

    @Test("guest book route enters guest mode and opens one exact detail")
    func guestBookRoutePushesPublicDetailOnce() {
        let (model, _) = makeSignedOutRouteModel()

        model.handle(deepLink: .book(id: "b-public"))
        model.handle(deepLink: .book(id: "b-public"))

        #expect(model.isGuestMode)
        #expect(!model.showAuthGate)
        #expect(model.libraryRouter.depth == 1)
    }

    @Test("signed-in chapter route preserves exact values and is idempotent")
    func chapterRoutePreservesChapter() async throws {
        let (model, _) = try await makeActiveRouteModel()

        model.handle(deepLink: .chapter(bookId: "b-exact", chapter: 7))
        let firstFlowID = model.pendingHandoffFlow?.id
        model.handle(deepLink: .chapter(bookId: "b-exact", chapter: 7))

        #expect(model.pendingHandoffFlow?.bookId == "b-exact")
        #expect(model.pendingHandoffFlow?.chapterNumber == 7)
        #expect(model.pendingHandoffFlow?.variantFamily == .emh)
        #expect(model.pendingHandoffFlow?.id == firstFlowID)
    }

    @Test("signed-out chapter waits for scope then replays exact values once")
    func signedOutChapterRouteReplaysExactValues() async throws {
        let (model, session) = makeSignedOutRouteModel()
        model.handle(deepLink: .chapter(bookId: "b-exact", chapter: 7))

        #expect(model.showAuthGate)
        #expect(model.pendingNavigationRequest == .chapter(bookId: "b-exact", chapter: 7))
        model.replayPendingNavigationRequest()
        #expect(model.pendingHandoffFlow == nil)
        #expect(model.pendingNavigationRequest != nil)

        try await activate(model: model, session: session, subject: "route-user-a")
        model.replayPendingNavigationRequest()
        let consumedFlow = model.pendingHandoffFlow
        model.replayPendingNavigationRequest()

        #expect(consumedFlow?.bookId == "b-exact")
        #expect(consumedFlow?.chapterNumber == 7)
        #expect(model.pendingHandoffFlow?.id == consumedFlow?.id)
        #expect(model.pendingNavigationRequest == nil)
    }

    @Test(
        "private review, code, notification, and paywall routes replay exactly once",
        arguments: privateRouteCases
    )
    func privateRouteReplaysOnce(routeCase: PrivateRouteCase) async throws {
        let (model, session) = makeSignedOutRouteModel()
        model.handle(deepLink: routeCase.deepLink)

        #expect(model.pendingNavigationRequest == routeCase.request)
        #expect(model.showAuthGate)
        try await activate(model: model, session: session, subject: "route-user-a")
        model.replayPendingNavigationRequest()
        assertConsumed(routeCase.request, by: model)
        let snapshot = NavigationConsumptionSnapshot(model: model)

        model.replayPendingNavigationRequest()

        #expect(model.pendingNavigationRequest == nil)
        #expect(NavigationConsumptionSnapshot(model: model) == snapshot)
    }

    @Test("same-account scope recovery preserves and replays the exact request")
    func scopeRecoveryPreservesPendingRoute() async throws {
        let session = SessionManager(tokenStore: InMemoryTokenStore())
        var buildAttempts = 0
        let model = makeTestAppModel(session: session) { context in
            buildAttempts += 1
            if buildAttempts == 1 { throw RouteScopeBuildError.injected }
            return SessionScope(context: context)
        }
        model.handle(deepLink: .chapter(bookId: "b-recovery", chapter: 9))
        try session.establishHermeticSession(
            identity: try routeIdentity(subject: "recovery-user"),
            tokens: routeTokens(subject: "recovery-user")
        )

        await model.reconcileCurrentSession()
        #expect(model.pendingNavigationRequest == .chapter(
            bookId: "b-recovery",
            chapter: 9
        ))
        #expect(!model.hasActiveMatchingSessionScope)

        await model.reconcileCurrentSession()
        #expect(model.hasActiveMatchingSessionScope)
        model.replayPendingNavigationRequest()
        #expect(model.pendingHandoffFlow?.bookId == "b-recovery")
        #expect(model.pendingHandoffFlow?.chapterNumber == 9)
        #expect(model.pendingNavigationRequest == nil)
    }

    @Test("first pending private route cannot be overwritten")
    func firstPendingRequestWins() {
        let (model, _) = makeSignedOutRouteModel()
        model.handle(deepLink: .chapter(bookId: "first", chapter: 4))
        model.handle(deepLink: .gift(code: "SECOND"))
        #expect(model.pendingNavigationRequest == .chapter(bookId: "first", chapter: 4))
        #expect(model.pendingGiftCode == nil)
    }

    @Test("sign-out clears pending private navigation and tab routes")
    func signOutClearsPendingRoute() async {
        let (model, _) = makeSignedOutRouteModel()
        model.handle(deepLink: .chapter(bookId: "b-stale", chapter: 8))
        model.libraryRouter.push(LibraryRoute.bookDetail(bookId: "b-stale"))

        await model.signOut()

        #expect(model.pendingNavigationRequest == nil)
        #expect(model.libraryRouter.isAtRoot)
        #expect(!model.showAuthGate)
    }

    @Test("an A-bound request cannot replay under account B")
    func accountSwitchClearsStaleRequest() async throws {
        let (model, session) = makeSignedOutRouteModel()
        model.handle(deepLink: .chapter(bookId: "b-private", chapter: 5))
        try await activate(model: model, session: session, subject: "account-a")
        #expect(model.pendingNavigationRequest != nil)

        try session.establishHermeticSession(
            identity: try routeIdentity(subject: "account-b"),
            tokens: routeTokens(subject: "account-b")
        )
        await model.reconcileCurrentSession()
        model.replayPendingNavigationRequest()

        #expect(model.pendingNavigationRequest == nil)
        #expect(model.pendingHandoffFlow == nil)
    }

    @Test("Library router identity remains stable across root recomposition")
    func libraryRouterIdentityIsStable() {
        let (model, _) = makeSignedOutRouteModel()
        let routerID = ObjectIdentifier(model.libraryRouter)

        _ = AppRootView(model: model)
        _ = AppRootView(model: model)

        #expect(ObjectIdentifier(model.libraryRouter) == routerID)
    }

    @Test("deferred UI auth gate requires every hermetic flag")
    func deferredAuthGateFailsClosed() {
        let complete = [
            "CF_UITEST_DEFERRED_AUTH": "1",
            "CF_STUB_SERVER": "1",
            "CF_HERMETIC_TEST_CONFIGURATION": "1",
        ]
        #expect(AppModel.isHermeticDeferredAuthUITest(environment: complete))

        for missingKey in complete.keys {
            var incomplete = complete
            incomplete.removeValue(forKey: missingKey)
            #expect(!AppModel.isHermeticDeferredAuthUITest(environment: incomplete))
        }
        var bypassed = complete
        bypassed["CF_UITEST_BYPASS_AUTH"] = "1"
        #expect(!AppModel.isHermeticDeferredAuthUITest(environment: bypassed))
    }
}

struct PrivateRouteCase: Sendable, CustomTestStringConvertible {
    let deepLink: DeepLink
    let request: AppNavigationRequest

    var testDescription: String { String(describing: request) }
}

let privateRouteCases: [PrivateRouteCase] = [
    PrivateRouteCase(deepLink: .review, request: .review),
    PrivateRouteCase(
        deepLink: .pairAccept(code: "PAIR-42"),
        request: .pairAccept(code: "PAIR-42")
    ),
    PrivateRouteCase(
        deepLink: .gift(code: "GIFT-42"),
        request: .gift(code: "GIFT-42")
    ),
    PrivateRouteCase(
        deepLink: .referral(code: "REF-42"),
        request: .referral(code: "REF-42")
    ),
    PrivateRouteCase(deepLink: .notifications, request: .notifications),
    PrivateRouteCase(deepLink: .paywall, request: .paywall),
]

private enum RouteScopeBuildError: Error {
    case injected
}

private struct NavigationConsumptionSnapshot: Equatable {
    let selectedTab: AppTab
    let pairCode: String
    let giftCode: String?
    let referralCode: String
    let showsNotifications: Bool
    let showsPaywall: Bool

    @MainActor
    init(model: AppModel) {
        selectedTab = model.selectedTab
        pairCode = model.pendingPairAcceptCode
        giftCode = model.pendingGiftCode
        referralCode = model.pendingReferralCode
        showsNotifications = model.showNotificationInbox
        showsPaywall = model.showPaywall
    }
}

@MainActor
private func assertConsumed(_ request: AppNavigationRequest, by model: AppModel) {
    switch request {
    case .review:
        #expect(model.selectedTab == .reviews)
    case .pairAccept(let code):
        #expect(model.selectedTab == .profile)
        #expect(model.pendingPairAcceptCode == code)
    case .gift(let code):
        #expect(model.selectedTab == .profile)
        #expect(model.pendingGiftCode == code)
    case .referral(let code):
        #expect(model.selectedTab == .profile)
        #expect(model.pendingReferralCode == code)
    case .notifications:
        #expect(model.selectedTab == .home)
        #expect(model.showNotificationInbox)
    case .paywall:
        #expect(model.showPaywall)
    case .book, .chapter:
        Issue.record("Private-route table must not include book/chapter")
    }
}

@MainActor
private func makeSignedOutRouteModel() -> (model: AppModel, session: SessionManager) {
    let session = SessionManager(tokenStore: InMemoryTokenStore())
    let model = makeTestAppModel(
        session: session,
        scopeBuilder: { SessionScope(context: $0) }
    )
    return (model, session)
}

@MainActor
private func makeActiveRouteModel(
    subject: String = "route-user-a"
) async throws -> (model: AppModel, session: SessionManager) {
    let pair = makeSignedOutRouteModel()
    try await activate(model: pair.model, session: pair.session, subject: subject)
    return pair
}

@MainActor
private func activate(
    model: AppModel,
    session: SessionManager,
    subject: String
) async throws {
    try session.establishHermeticSession(
        identity: try routeIdentity(subject: subject),
        tokens: routeTokens(subject: subject)
    )
    await model.reconcileCurrentSession()
    #expect(model.hasActiveMatchingSessionScope)
}

private func routeIdentity(subject: String) throws -> SessionIdentity {
    try #require(SessionIdentity(
        subject: subject,
        username: "Route Tester",
        email: nil,
        source: .hermeticUITest
    ))
}

private func routeTokens(subject: String) -> StoredTokens {
    StoredTokens(
        idToken: "id-\(subject)",
        accessToken: "access-\(subject)",
        refreshToken: "refresh-\(subject)",
        expiresAt: Date().addingTimeInterval(3_600)
    )
}
