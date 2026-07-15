import Testing
@testable import LibraryFeature
import Models
import CoreKit
import Fixtures

@Suite("BookDetailModel — freeStartsLeft")
@MainActor
struct BookDetailModelFreeStartsTests {

    @Test("freeStartsLeft is 0 before fetch completes")
    func freeStartsLeftZeroBeforeFetch() {
        let model = BookDetailModel(
            bookId: "b-atomic-habits",
            repository: FakeBookDetailRepository(
                manifest: BookDetailModelTests.manifest,
                entitlement: BookDetailModelTests.proEntitlement()
            )
        )
        #expect(model.freeStartsLeft == 0)
    }

    @Test("freeStartsLeft reflects remainingFreeStarts from entitlement after fetch")
    func freeStartsLeftFromFreeEntitlement() async {
        let repo = FakeBookDetailRepository(
            manifest: BookDetailModelTests.manifest,
            state: BookDetailModelTests.notStartedState,
            entitlement: BookDetailModelTests.freeWithSlotEntitlement()
        )
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)
        await model.fetch()
        #expect(model.freeStartsLeft == 1)
    }

    @Test("freeStartsLeft is 0 for a fully locked free user")
    func freeStartsLeftZeroForLockedUser() async {
        let repo = FakeBookDetailRepository(
            manifest: BookDetailModelTests.manifest,
            state: BookDetailModelTests.notStartedState,
            entitlement: BookDetailModelTests.freeLockedEntitlement()
        )
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)
        await model.fetch()
        #expect(model.freeStartsLeft == 0)
    }

    @Test("freeStartsLeft is 0 for Pro user (remainingFreeStarts is irrelevant)")
    func freeStartsLeftZeroForProUser() async {
        let repo = FakeBookDetailRepository(
            manifest: BookDetailModelTests.manifest,
            state: BookDetailModelTests.notStartedState,
            entitlement: BookDetailModelTests.proEntitlement()
        )
        let model = BookDetailModel(bookId: "b-atomic-habits", repository: repo)
        await model.fetch()
        // Pro entitlement has remainingFreeStarts: 0 — irrelevant for gating, correctly zero.
        #expect(model.freeStartsLeft == 0)
    }
}
