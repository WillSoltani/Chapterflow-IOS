import Foundation
import Testing
import CoreKit
import Networking
import Persistence
@testable import ReaderFeature

@Suite("LiveReaderRepository identity", .serialized)
@MainActor
struct LiveReaderRepositoryIdentityTests {
    @Test("scroll positions are keyed by immutable account authority")
    func scrollPositionsAreAccountIsolated() {
        let suite = "LiveReaderRepositoryIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let reachability = ReachabilityService()
        let accountA = LiveReaderRepository(
            client: MockAPIClient(),
            store: KeyValueStore(defaults: defaults),
            reachability: reachability,
            accountID: "account-a"
        )
        let accountB = LiveReaderRepository(
            client: MockAPIClient(),
            store: KeyValueStore(defaults: defaults),
            reachability: reachability,
            accountID: "account-b"
        )

        accountA.saveScrollPosition(bookId: "shared-book", chapterNumber: 2, blockIndex: 17)
        #expect(accountA.loadScrollPosition(bookId: "shared-book", chapterNumber: 2) == 17)
        #expect(accountB.loadScrollPosition(bookId: "shared-book", chapterNumber: 2) == nil)

        accountB.saveScrollPosition(bookId: "shared-book", chapterNumber: 2, blockIndex: 41)
        #expect(accountA.loadScrollPosition(bookId: "shared-book", chapterNumber: 2) == 17)
        #expect(accountB.loadScrollPosition(bookId: "shared-book", chapterNumber: 2) == 41)
        #expect(defaults.object(forKey: "reader.position.v1.anon.shared-book.2") == nil)
    }

    @Test("concurrent position writes remain serialized")
    func concurrentPositionWritesAreSerialized() async {
        let suite = "LiveReaderRepositoryIdentityTests.concurrent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = LiveReaderRepository(
            client: MockAPIClient(),
            store: KeyValueStore(defaults: defaults),
            reachability: ReachabilityService(),
            accountID: "account-a"
        )

        await withTaskGroup(of: Void.self) { group in
            for chapterNumber in 1...100 {
                group.addTask {
                    await repository.saveScrollPosition(
                        bookId: "shared-book",
                        chapterNumber: chapterNumber,
                        blockIndex: chapterNumber * 2
                    )
                }
            }
        }

        for chapterNumber in 1...100 {
            #expect(repository.loadScrollPosition(
                bookId: "shared-book",
                chapterNumber: chapterNumber
            ) == chapterNumber * 2)
        }
    }
}
