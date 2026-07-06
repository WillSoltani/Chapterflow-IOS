import Testing
@testable import LibraryFeature
import Models
import CoreKit
import Fixtures

@Suite("BookDetailModel — guest mode")
@MainActor
struct BookDetailModelGuestTests {

    static var manifest: BookManifest { Fixtures.bookManifest }

    static func anyEntitlement() -> EntitlementResponse {
        EntitlementResponse(
            entitlement: Entitlement(
                plan: .free, proStatus: nil, proSource: nil,
                freeBookSlots: 0, unlockedBookIds: [],
                unlockedBooksCount: 0, remainingFreeStarts: 0,
                currentPeriodEnd: nil, cancelAtPeriodEnd: nil,
                licenseKey: nil, licenseExpiresAt: nil
            ),
            paywall: nil
        )
    }

    // MARK: - fetch()

    @Test("guest fetch loads only manifest, not entitlement or state")
    func guestFetchLoadsManifestOnly() async {
        let repo = FakeBookDetailRepository(
            manifest: Self.manifest,
            state: nil,
            stateError: .notFound,
            entitlement: Self.anyEntitlement()
        )
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)
        model.isGuest = true
        await model.fetch()

        #expect(model.manifest?.bookId == "b-atomic-habits")
        #expect(model.entitlement == nil)
        #expect(model.bookState == nil)
        if case .loaded = model.loadState { } else {
            Issue.record("Expected .loaded, got \(model.loadState)")
        }
    }

    @Test("guest fetch sets error state on network failure")
    func guestFetchSetsErrorOnNetworkFailure() async {
        let repo = FakeBookDetailRepository(
            manifest: Self.manifest,
            entitlement: Self.anyEntitlement(),
            error: .offline
        )
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)
        model.isGuest = true
        await model.fetch()

        if case .error = model.loadState { } else {
            Issue.record("Expected .error for offline guest fetch, got \(model.loadState)")
        }
    }

    // MARK: - primaryAction

    @Test("primaryAction is .disabled for guest before manifest loads")
    func guestPrimaryActionDisabledBeforeLoad() {
        let repo = FakeBookDetailRepository(
            manifest: Self.manifest,
            entitlement: Self.anyEntitlement()
        )
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)
        model.isGuest = true
        #expect(model.primaryAction == .disabled)
    }

    @Test("primaryAction is .signInRequired for guest after manifest loads")
    func guestPrimaryActionSignInRequired() async {
        let repo = FakeBookDetailRepository(
            manifest: Self.manifest,
            entitlement: Self.anyEntitlement()
        )
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)
        model.isGuest = true
        await model.fetch()
        #expect(model.primaryAction == .signInRequired)
    }

    // MARK: - performPrimaryAction

    @Test("performPrimaryAction calls onSignInRequired with bookId and variantFamily")
    func guestPrimaryActionCallsOnSignInRequired() async {
        let repo = FakeBookDetailRepository(
            manifest: Self.manifest,
            entitlement: Self.anyEntitlement()
        )
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)
        model.isGuest = true
        await model.fetch()

        var receivedBookId: String?
        var receivedFamily: VariantFamily?
        model.onSignInRequired = { bookId, family in
            receivedBookId = bookId
            receivedFamily = family
        }
        await model.performPrimaryAction()

        #expect(receivedBookId == "b-atomic-habits")
        #expect(receivedFamily == Self.manifest.variantFamily)
    }

    @Test("performPrimaryAction does not call onOpenReader or onShowPaywall for guest")
    func guestPrimaryActionDoesNotCallOtherCallbacks() async {
        let repo = FakeBookDetailRepository(
            manifest: Self.manifest,
            entitlement: Self.anyEntitlement()
        )
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)
        model.isGuest = true
        await model.fetch()

        var openReaderCalled = false
        var showPaywallCalled = false
        model.onOpenReader = { _, _, _ in openReaderCalled = true }
        model.onShowPaywall = { showPaywallCalled = true }
        model.onSignInRequired = { _, _ in } // no-op

        await model.performPrimaryAction()

        #expect(!openReaderCalled)
        #expect(!showPaywallCalled)
    }
}
