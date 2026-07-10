import Testing
import Foundation
@testable import EngagementFeature
import Models
import Networking
import CoreKit

// MARK: - Shared helpers

private final class Box<T: Sendable>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private final class StubBadgesClient: APIClientProtocol, Sendable {
    typealias Handler = @Sendable (Endpoint) async throws -> Data
    private let handler: Handler
    init(handler: @escaping Handler) { self.handler = handler }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await handler(endpoint)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(error)
        }
    }
}

// MARK: - Badge fixtures

extension BadgeItem {
    static func fixture(
        id: String = "badge-1",
        name: String = "First Badge",
        category: String = "mastery",
        isEarned: Bool = true,
        earnedAt: String? = "2026-07-01T10:00:00Z",
        progress: Int? = nil,
        target: Int? = nil
    ) -> BadgeItem {
        BadgeItem(
            badgeId: id,
            name: name,
            description: "A test badge.",
            category: category,
            isEarned: isEarned,
            earnedAt: earnedAt,
            icon: "🏅",
            progress: progress,
            target: target
        )
    }
}

private func makeBadgesRepo(_ badges: [BadgeItem]) -> EngagementRepository {
    let client = StubBadgesClient { endpoint in
        guard endpoint.path == "/book/me/badges" else { throw AppError.notFound }
        return try JSONCoding.encoder.encode(BadgesResponse(badges: badges))
    }
    return EngagementRepository(apiClient: client, modelContainer: nil)
}

private func makeOfflineRepo() -> EngagementRepository {
    let client = StubBadgesClient { _ in throw AppError.offline }
    return EngagementRepository(apiClient: client, modelContainer: nil)
}

// MARK: - EngagementRepository badge tests

@Suite("EngagementRepository — badges")
struct EngagementRepositoryBadgeTests {

    @Test("fetchBadges returns list from server")
    func fetchBadgesSuccess() async throws {
        let badges: [BadgeItem] = [.fixture(), .fixture(id: "badge-2", isEarned: false, earnedAt: nil)]
        let repo = makeBadgesRepo(badges)

        let result = try await repo.fetchBadges()
        #expect(result.count == 2)
        #expect(result[0].badgeId == "badge-1")
    }

    @Test("fetchBadges caches within TTL")
    func fetchBadgesCachesResult() async throws {
        let callCount = Box(0)
        let client = StubBadgesClient { endpoint in
            guard endpoint.path == "/book/me/badges" else { throw AppError.notFound }
            callCount.value += 1
            return try JSONCoding.encoder.encode(BadgesResponse(badges: [.fixture()]))
        }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        _ = try await repo.fetchBadges()
        _ = try await repo.fetchBadges()
        #expect(callCount.value == 1, "Second call should use in-memory cache")
    }

    @Test("fetchBadges forceRefresh bypasses cache")
    func fetchBadgesForceRefresh() async throws {
        let callCount = Box(0)
        let client = StubBadgesClient { endpoint in
            guard endpoint.path == "/book/me/badges" else { throw AppError.notFound }
            callCount.value += 1
            return try JSONCoding.encoder.encode(BadgesResponse(badges: [.fixture()]))
        }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)

        _ = try await repo.fetchBadges()
        _ = try await repo.fetchBadges(forceRefresh: true)
        #expect(callCount.value == 2)
    }

    @Test("currentBadges is nil before first fetch")
    func currentBadgesNilBeforeFetch() async {
        let repo = makeBadgesRepo([])
        let current = await repo.currentBadges
        #expect(current == nil)
    }

    @Test("currentBadges reflects last-fetched value")
    func currentBadgesAfterFetch() async throws {
        let repo = makeBadgesRepo([.fixture()])
        _ = try await repo.fetchBadges()
        let current = await repo.currentBadges
        #expect(current?.count == 1)
    }

    @Test("invalidateAll clears badge cache")
    func invalidateAllClearsBadges() async throws {
        let repo = makeBadgesRepo([.fixture()])
        _ = try await repo.fetchBadges()
        await repo.invalidateAll()
        let current = await repo.currentBadges
        #expect(current == nil)
    }

    @Test("offline with no cache propagates error")
    func offlineNoCacheThrows() async {
        let repo = makeOfflineRepo()
        do {
            _ = try await repo.fetchBadges()
            Issue.record("Expected AppError.offline")
        } catch AppError.offline {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

// MARK: - BadgesModel initial state tests

@Suite("BadgesModel — initial state")
@MainActor
struct BadgesModelInitialStateTests {

    @Test("initial loadState is .loading")
    func initialState() {
        let model = BadgesModel(repository: makeBadgesRepo([]))
        if case .loading = model.loadState { } else {
            Issue.record("Expected .loading, got \(model.loadState)")
        }
    }

    @Test("displayedBadges is empty while loading")
    func displayedBadgesEmptyWhileLoading() {
        let model = BadgesModel(repository: makeBadgesRepo([]))
        #expect(model.displayedBadges.isEmpty)
    }

    @Test("selectedTrack defaults to nil")
    func selectedTrackDefaultsToNil() {
        let model = BadgesModel(repository: makeBadgesRepo([]))
        #expect(model.selectedTrack == nil)
    }
}

// MARK: - BadgesModel filtering tests

@Suite("BadgesModel — filtering")
@MainActor
struct BadgesModelFilteringTests {

    @Test("no filter returns all badges")
    func noFilterShowsAll() async {
        let badges: [BadgeItem] = [
            .fixture(id: "1", category: "mastery"),
            .fixture(id: "2", category: "consistency"),
            .fixture(id: "3", category: "exploration"),
        ]
        let model = BadgesModel(repository: makeBadgesRepo(badges))
        await model.refresh()
        #expect(model.displayedBadges.count == 3)
    }

    @Test("mastery filter returns only mastery badges")
    // swiftlint:disable:next inclusive_language
    func masteryFilter() async {
        let badges: [BadgeItem] = [
            .fixture(id: "1", category: "mastery"),
            .fixture(id: "2", category: "consistency"),
            .fixture(id: "3", category: "mastery"),
        ]
        let model = BadgesModel(repository: makeBadgesRepo(badges))
        await model.refresh()
        model.selectedTrack = .mastery
        let displayed = model.displayedBadges
        #expect(displayed.count == 2)
        #expect(displayed.allSatisfy { $0.category == "mastery" })
    }

    @Test("hidden filter returns only hidden badges")
    func hiddenFilter() async {
        let badges: [BadgeItem] = [
            .fixture(id: "1", category: "hidden"),
            .fixture(id: "2", category: "mastery"),
            .fixture(id: "3", category: "hidden", isEarned: false, earnedAt: nil),
        ]
        let model = BadgesModel(repository: makeBadgesRepo(badges))
        await model.refresh()
        model.selectedTrack = .hidden
        let displayed = model.displayedBadges
        #expect(displayed.count == 2)
        #expect(displayed.allSatisfy { $0.category == "hidden" })
    }

    @Test("exploration filter returns only exploration badges")
    func explorationFilter() async {
        let badges: [BadgeItem] = [
            .fixture(id: "1", category: "mastery"),
            .fixture(id: "2", category: "exploration"),
            .fixture(id: "3", category: "exploration"),
        ]
        let model = BadgesModel(repository: makeBadgesRepo(badges))
        await model.refresh()
        model.selectedTrack = .exploration
        #expect(model.displayedBadges.count == 2)
    }

    @Test("earned badges sort before locked")
    func earnedBeforeLocked() async {
        let badges: [BadgeItem] = [
            .fixture(id: "locked", isEarned: false, earnedAt: nil),
            .fixture(id: "earned", isEarned: true, earnedAt: "2026-07-01T00:00:00Z"),
        ]
        let model = BadgesModel(repository: makeBadgesRepo(badges))
        await model.refresh()
        #expect(model.displayedBadges.first?.badgeId == "earned")
    }

    @Test("locked badges with more progress sort higher")
    func progressSortOrder() async {
        let badges: [BadgeItem] = [
            .fixture(id: "low", isEarned: false, earnedAt: nil, progress: 1, target: 10),
            .fixture(id: "high", isEarned: false, earnedAt: nil, progress: 8, target: 10),
        ]
        let model = BadgesModel(repository: makeBadgesRepo(badges))
        await model.refresh()
        // Both locked — high progress should come first
        let locked = model.displayedBadges.filter { !$0.isEarned }
        #expect(locked.first?.badgeId == "high")
    }

    @Test("unknown category badge appears in All but not in known tracks")
    func unknownCategoryInAllOnly() async {
        let badges: [BadgeItem] = [
            .fixture(id: "1", category: "mastery"),
            .fixture(id: "2", category: "social"), // unknown track
        ]
        let model = BadgesModel(repository: makeBadgesRepo(badges))
        await model.refresh()

        // All shows both
        #expect(model.displayedBadges.count == 2)

        // Mastery filter shows only mastery
        model.selectedTrack = .mastery
        #expect(model.displayedBadges.count == 1)

        // Consistency filter shows neither
        model.selectedTrack = .consistency
        #expect(model.displayedBadges.isEmpty)
    }
}

// MARK: - BadgesModel celebration tests

@Suite("BadgesModel — celebration")
@MainActor
struct BadgesModelCelebrationTests {

    @Test("newly earned badge after initial load triggers celebration")
    func newlyEarnedBadgeTriggersCelebration() async {
        let presenter = CelebrationPresenter()
        let returnUpdated = Box(false)
        let client = StubBadgesClient { endpoint in
            guard endpoint.path == "/book/me/badges" else { throw AppError.notFound }
            let badges: [BadgeItem] = returnUpdated.value
                ? [.fixture(id: "bg-1", isEarned: true, earnedAt: "2026-07-02T10:00:00Z")]
                : [.fixture(id: "bg-1", isEarned: false, earnedAt: nil)]
            return try JSONCoding.encoder.encode(BadgesResponse(badges: badges))
        }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = BadgesModel(repository: repo, presenter: presenter)

        // First refresh: badge-1 not yet earned; seeds seenEarnedIds
        await model.refresh()
        #expect(!presenter.isPresenting, "No celebration on first load")

        // Badge earned on server; second refresh detects it
        returnUpdated.value = true
        await model.refresh()
        #expect(presenter.isPresenting, "Celebration should fire for newly earned badge")
        if case .badgeEarned(let b) = presenter.currentEvent {
            #expect(b.badgeId == "bg-1")
        } else {
            Issue.record("Expected .badgeEarned, got \(String(describing: presenter.currentEvent))")
        }
    }

    @Test("already-earned badge on first load does not trigger celebration")
    func existingEarnedBadgesNotCelebrated() async {
        let presenter = CelebrationPresenter()
        let badges: [BadgeItem] = [.fixture(id: "bg-1", isEarned: true, earnedAt: "2026-06-01T00:00:00Z")]
        let model = BadgesModel(repository: makeBadgesRepo(badges), presenter: presenter)

        await model.refresh()
        #expect(!presenter.isPresenting, "Pre-existing earned badge must not trigger celebration")
    }

    @Test("multiple newly earned badges all enqueued")
    func multipleNewlyEarnedEnqueued() async {
        let presenter = CelebrationPresenter()
        let returnUpdated = Box(false)
        let client = StubBadgesClient { endpoint in
            guard endpoint.path == "/book/me/badges" else { throw AppError.notFound }
            let badges: [BadgeItem] = returnUpdated.value
                ? [
                    .fixture(id: "bg-1", isEarned: true, earnedAt: "2026-07-02T10:00:00Z"),
                    .fixture(id: "bg-2", isEarned: true, earnedAt: "2026-07-02T10:01:00Z"),
                ]
                : [
                    .fixture(id: "bg-1", isEarned: false, earnedAt: nil),
                    .fixture(id: "bg-2", isEarned: false, earnedAt: nil),
                ]
            return try JSONCoding.encoder.encode(BadgesResponse(badges: badges))
        }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = BadgesModel(repository: repo, presenter: presenter)

        await model.refresh()
        returnUpdated.value = true
        await model.refresh()

        #expect(presenter.isPresenting)
        // Advance past first event
        presenter.advance()
        #expect(presenter.isPresenting, "Second badge celebration should be queued")
    }

    @Test("no presenter — celebration silently skipped, no crash")
    func noPresenterNocrash() async {
        let shouldBeEarned = Box(false)
        let client = StubBadgesClient { endpoint in
            guard endpoint.path == "/book/me/badges" else { throw AppError.notFound }
            let badge = BadgeItem.fixture(
                id: "bg-x",
                isEarned: shouldBeEarned.value,
                earnedAt: shouldBeEarned.value ? "2026-07-02T10:00:00Z" : nil
            )
            return try JSONCoding.encoder.encode(BadgesResponse(badges: [badge]))
        }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let model = BadgesModel(repository: repo, presenter: nil)

        // First fetch: badge locked — seeds seenEarnedIds with {}
        await model.refresh()
        #expect(!model.displayedBadges.isEmpty)

        // Badge becomes earned — detectAndCelebrate calls guard let presenter → returns early, no crash
        shouldBeEarned.value = true
        await model.refresh()

        if case .loaded(let badges) = model.loadState {
            #expect(badges.first?.isEarned == true)
        } else {
            Issue.record("Expected loaded state after second refresh")
        }
    }
}

// MARK: - AchievementTrack tests

@Suite("AchievementTrack")
struct AchievementTrackTests {

    @Test("from(category:) maps known values correctly")
    func knownCategoryMapping() {
        #expect(AchievementTrack.from(category: "mastery") == .mastery)
        #expect(AchievementTrack.from(category: "consistency") == .consistency)
        #expect(AchievementTrack.from(category: "exploration") == .exploration)
        #expect(AchievementTrack.from(category: "hidden") == .hidden)
    }

    @Test("from(category:) is case-insensitive")
    func caseInsensitiveMapping() {
        #expect(AchievementTrack.from(category: "MASTERY") == .mastery)
        #expect(AchievementTrack.from(category: "Consistency") == .consistency)
    }

    @Test("from(category:) returns nil for unknown categories")
    func unknownCategoryReturnsNil() {
        #expect(AchievementTrack.from(category: "social") == nil)
        #expect(AchievementTrack.from(category: "") == nil)
        #expect(AchievementTrack.from(category: "future_track") == nil)
    }

    @Test("all tracks have non-empty displayName and systemImage")
    func allTracksHaveDisplayInfo() {
        for track in AchievementTrack.allCases {
            #expect(!track.displayName.isEmpty)
            #expect(!track.systemImage.isEmpty)
        }
    }

    @Test("four known cases exist")
    func caseCount() {
        #expect(AchievementTrack.allCases.count == 4)
    }
}

// MARK: - BadgeItem progress tests

@Suite("BadgeItem — progressFraction")
struct BadgeItemProgressTests {

    @Test("progressFraction is nil when progress data absent")
    func progressFractionNilWithoutData() {
        let badge = BadgeItem.fixture(progress: nil, target: nil)
        #expect(badge.progressFraction == nil)
    }

    @Test("progressFraction computes correctly")
    func progressFractionComputed() {
        let badge = BadgeItem.fixture(progress: 3, target: 10)
        #expect(abs((badge.progressFraction ?? 0) - 0.3) < 0.001)
    }

    @Test("progressFraction clamps to 1.0 when progress exceeds target")
    func progressFractionClamped() {
        let badge = BadgeItem.fixture(progress: 15, target: 10)
        #expect(badge.progressFraction == 1.0)
    }

    @Test("progressFraction is nil when target is zero")
    func progressFractionNilZeroTarget() {
        let badge = BadgeItem.fixture(progress: 5, target: 0)
        #expect(badge.progressFraction == nil)
    }

    @Test("BadgeItem decodes without progress fields (optional absent)")
    func decodesWithoutProgressFields() throws {
        let json = """
        {
            "badgeId": "b1",
            "name": "Test",
            "description": "desc",
            "category": "mastery",
            "isEarned": false,
            "earnedAt": null,
            "icon": null
        }
        """.data(using: .utf8)!
        let badge = try JSONCoding.decoder.decode(BadgeItem.self, from: json)
        #expect(badge.progress == nil)
        #expect(badge.target == nil)
        #expect(badge.progressFraction == nil)
    }

    @Test("BadgeItem decodes with progress and target present")
    func decodesWithProgressFields() throws {
        let json = """
        {
            "badgeId": "b1",
            "name": "Test",
            "description": "desc",
            "category": "mastery",
            "isEarned": false,
            "earnedAt": null,
            "icon": null,
            "progress": 7,
            "target": 10
        }
        """.data(using: .utf8)!
        let badge = try JSONCoding.decoder.decode(BadgeItem.self, from: json)
        #expect(badge.progress == 7)
        #expect(badge.target == 10)
        #expect(abs((badge.progressFraction ?? 0) - 0.7) < 0.001)
    }
}

// MARK: - BadgesResponse evolution (tolerant decoding)

@Suite("BadgesResponse lossy decoding (evolution)")
struct BadgesResponseEvolutionTests {

    @Test("null element is dropped; rest survive")
    func nullBadgeDropped() throws {
        let good = #"{"badgeId":"b1","name":"N","description":"d","category":"mastery","isEarned":false,"earnedAt":null,"icon":null}"#
        let json = "{\"badges\":[\(good),null,\(good)]}".data(using: .utf8)!
        let resp = try JSONCoding.decoder.decode(BadgesResponse.self, from: json)
        #expect(resp.badges.count == 2)
    }

    @Test("element missing the identity field is dropped; rest survive")
    func missingIdentityDropped() throws {
        // Post-reconciliation, `badgeId` is the ONLY required field — the
        // deployed /me/badges returns bare award records ({badgeId, earnedAt})
        // whose display fields default rather than dropping the badge.
        let good = #"{"badgeId":"b1","name":"N","description":"d","category":"mastery","isEarned":false,"earnedAt":null,"icon":null}"#
        let bad = #"{"name":"No identity"}"#
        let json = "{\"badges\":[\(good),\(bad),\(good)]}".data(using: .utf8)!
        let resp = try JSONCoding.decoder.decode(BadgesResponse.self, from: json)
        #expect(resp.badges.count == 2)
        #expect(resp.badges.allSatisfy { $0.badgeId == "b1" })
    }

    @Test("deployed award record decodes with inferred isEarned + defaulted display fields")
    func deployedAwardRecordDecodes() throws {
        let award = #"{"badgeId":"first-book","earnedAt":"2026-07-01T00:00:00Z","tier":"bronze"}"#
        let json = "{\"awards\":[\(award)]}".data(using: .utf8)!
        let resp = try JSONCoding.decoder.decode(BadgesResponse.self, from: json)
        #expect(resp.badges.count == 1)
        let badge = try #require(resp.badges.first)
        #expect(badge.badgeId == "first-book")
        #expect(badge.isEarned) // inferred from earnedAt
        #expect(badge.name == "first-book") // falls back to the id
    }

    @Test("extra future fields are silently ignored")
    func extraFieldsIgnored() throws {
        let withExtra = #"{"badgeId":"b1","name":"N","description":"d","category":"mastery","isEarned":true,"earnedAt":"2024-01-01T00:00:00Z","icon":"🏅","futureField":"val","newMetric":42}"#
        let json = "{\"badges\":[\(withExtra)]}".data(using: .utf8)!
        let resp = try JSONCoding.decoder.decode(BadgesResponse.self, from: json)
        #expect(resp.badges.count == 1)
        #expect(resp.badges[0].badgeId == "b1")
    }
}
