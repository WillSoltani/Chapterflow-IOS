import Testing
import Foundation
@testable import EngagementFeature
import Models
import Networking
import CoreKit

// MARK: - Test helpers

private final class StubAPIClient: APIClientProtocol, Sendable {
    typealias Handler = @Sendable (Endpoint) async throws -> Data
    private let handler: Handler
    init(handler: @escaping Handler) { self.handler = handler }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await handler(endpoint)
        return try JSONCoding.decoder.decode(T.self, from: data)
    }
}

private func makeTierRepository(tier: TierState) -> EngagementRepository {
    let client = StubAPIClient { endpoint in
        switch endpoint.path {
        case "/book/me/tier":
            return try JSONCoding.encoder.encode(TierResponse(tier: tier))
        default:
            throw AppError.notFound
        }
    }
    return EngagementRepository(apiClient: client, modelContainer: nil)
}

private func isolatedDefaults() -> UserDefaults {
    // UUID-based suite so parallel tests never share state.
    // swiftlint:disable:next force_unwrapping
    return UserDefaults(suiteName: "com.chapterflow.test.\(UUID().uuidString)")!
}

private func analystState(recentlyPromoted: Bool = false, previousTier: TierKey? = nil) -> TierState {
    TierState(
        currentTier: .analyst,
        nextTier: .synthesizer,
        overallProgress: 0.62,
        metrics: TierProgressDetail(
            loopsCompleted: 18, loopsTarget: 30,
            averageQuizScore: 74, quizScoreTarget: 80,
            categoriesExplored: 2, categoriesTarget: 3
        ),
        recentlyPromoted: recentlyPromoted,
        previousTier: previousTier
    )
}

// MARK: - TierModel load tests

@Suite("TierModel load state")
@MainActor
struct TierModelLoadTests {

    @Test("initial state is .loading")
    func initialStateIsLoading() {
        let sut = TierModel(
            repository: makeTierRepository(tier: analystState()),
            celebrationPresenter: CelebrationPresenter()
        )
        if case .loading = sut.loadState {
            // pass
        } else {
            Issue.record("Expected .loading on init")
        }
    }

    @Test("transitions to .loaded after successful fetch")
    func transitionsToLoaded() async throws {
        let sut = TierModel(
            repository: makeTierRepository(tier: analystState()),
            celebrationPresenter: CelebrationPresenter()
        )
        sut.load()
        await waitUntil { if case .loading = sut.loadState { return false } else { return true } }
        if case .loaded(let state) = sut.loadState {
            #expect(state.currentTier == .analyst)
        } else {
            Issue.record("Expected .loaded after successful fetch")
        }
    }

    @Test("transitions to .error on network failure")
    func transitionsToError() async throws {
        let client = StubAPIClient { _ in throw AppError.offline }
        let repo = EngagementRepository(apiClient: client, modelContainer: nil)
        let sut = TierModel(repository: repo, celebrationPresenter: CelebrationPresenter())
        sut.load()
        await waitUntil { if case .loading = sut.loadState { return false } else { return true } }
        if case .error = sut.loadState {
            // pass
        } else {
            Issue.record("Expected .error when network fails and no cache")
        }
    }

    @Test("refresh force-updates the loaded state")
    func refreshUpdatesState() async throws {
        let sut = TierModel(
            repository: makeTierRepository(tier: analystState()),
            celebrationPresenter: CelebrationPresenter()
        )
        sut.load()
        await waitUntil { if case .loading = sut.loadState { return false } else { return true } }
        await sut.refresh()
        if case .loaded(let state) = sut.loadState {
            #expect(state.currentTier == .analyst)
        } else {
            Issue.record("Expected .loaded after refresh")
        }
    }
}

// MARK: - TierModel derived state tests

@Suite("TierModel derived state")
@MainActor
struct TierModelDerivedStateTests {

    @Test("currentTier returns .reader before load")
    func defaultTierBeforeLoad() {
        let sut = TierModel(
            repository: makeTierRepository(tier: analystState()),
            celebrationPresenter: CelebrationPresenter()
        )
        #expect(sut.currentTier == .reader)
    }

    @Test("currentTier returns server value after load")
    func currentTierAfterLoad() async throws {
        let sut = TierModel(
            repository: makeTierRepository(tier: analystState()),
            celebrationPresenter: CelebrationPresenter()
        )
        sut.load()
        await waitUntil { if case .loading = sut.loadState { return false } else { return true } }
        #expect(sut.currentTier == .analyst)
    }

    @Test("overallProgress returns 0 before load")
    func overallProgressBeforeLoad() {
        let sut = TierModel(
            repository: makeTierRepository(tier: analystState()),
            celebrationPresenter: CelebrationPresenter()
        )
        #expect(sut.overallProgress == 0)
    }

    @Test("loopsProgress computes correctly from metrics")
    func loopsProgressComputed() async throws {
        // loopsCompleted=18, target=30 → 18/30 = 0.6
        let sut = TierModel(
            repository: makeTierRepository(tier: analystState()),
            celebrationPresenter: CelebrationPresenter()
        )
        sut.load()
        await waitUntil { if case .loading = sut.loadState { return false } else { return true } }
        #expect(abs(sut.loopsProgress - 0.6) < 0.001)
    }

    @Test("quizScoreProgress computes correctly from metrics")
    func quizScoreProgressComputed() async throws {
        // avgScore=74, target=80 → 74/80 = 0.925
        let sut = TierModel(
            repository: makeTierRepository(tier: analystState()),
            celebrationPresenter: CelebrationPresenter()
        )
        sut.load()
        await waitUntil { if case .loading = sut.loadState { return false } else { return true } }
        #expect(abs(sut.quizScoreProgress - 0.925) < 0.001)
    }

    @Test("categoriesProgress computes correctly from metrics")
    func categoriesProgressComputed() async throws {
        // explored=2, target=3 → 2/3 ≈ 0.667
        let sut = TierModel(
            repository: makeTierRepository(tier: analystState()),
            celebrationPresenter: CelebrationPresenter()
        )
        sut.load()
        await waitUntil { if case .loading = sut.loadState { return false } else { return true } }
        #expect(abs(sut.categoriesProgress - (2.0 / 3.0)) < 0.001)
    }

    @Test("progress returns 0 when metrics is nil")
    func progressIsZeroWithoutMetrics() async throws {
        let state = TierState(
            currentTier: .luminary,
            nextTier: nil,
            overallProgress: 1.0,
            metrics: nil,
            recentlyPromoted: false,
            previousTier: nil
        )
        let sut = TierModel(
            repository: makeTierRepository(tier: state),
            celebrationPresenter: CelebrationPresenter()
        )
        sut.load()
        await waitUntil { if case .loading = sut.loadState { return false } else { return true } }
        #expect(sut.loopsProgress == 0)
        #expect(sut.quizScoreProgress == 0)
        #expect(sut.categoriesProgress == 0)
    }

    @Test("progress clamps to 1.0 when completed exceeds target")
    func progressClampedAtOne() async throws {
        let state = TierState(
            currentTier: .analyst,
            nextTier: .synthesizer,
            overallProgress: 1.0,
            metrics: TierProgressDetail(
                loopsCompleted: 50, loopsTarget: 30,
                averageQuizScore: 95, quizScoreTarget: 80,
                categoriesExplored: 5, categoriesTarget: 3
            ),
            recentlyPromoted: false,
            previousTier: nil
        )
        let sut = TierModel(
            repository: makeTierRepository(tier: state),
            celebrationPresenter: CelebrationPresenter()
        )
        sut.load()
        await waitUntil { if case .loading = sut.loadState { return false } else { return true } }
        #expect(sut.loopsProgress == 1.0)
        #expect(sut.quizScoreProgress == 1.0)
        #expect(sut.categoriesProgress == 1.0)
    }
}

// MARK: - Celebration guard tests

@Suite("TierModel celebration guard")
@MainActor
struct TierModelCelebrationTests {

    @Test("fires tierUp celebration when recentlyPromoted is true")
    func firesCelebrationOnPromotion() async throws {
        let defaults = isolatedDefaults()
        let presenter = CelebrationPresenter()
        let state = analystState(recentlyPromoted: true, previousTier: .reader)
        let sut = TierModel(
            repository: makeTierRepository(tier: state),
            celebrationPresenter: presenter,
            userDefaults: defaults
        )
        sut.load()
        await waitUntil { if case .loading = sut.loadState { return false } else { return true } }
        #expect(presenter.isPresenting, "Celebration should fire when recentlyPromoted is true")
        if case .tierUp(let newTier, let prevTier) = presenter.currentEvent {
            #expect(newTier == "analyst")
            #expect(prevTier == "reader")
        } else {
            Issue.record("Expected .tierUp celebration event")
        }
    }

    @Test("does not fire celebration when recentlyPromoted is false")
    func noCelebrationWithoutPromotion() async throws {
        let defaults = isolatedDefaults()
        let presenter = CelebrationPresenter()
        let state = analystState(recentlyPromoted: false)
        let sut = TierModel(
            repository: makeTierRepository(tier: state),
            celebrationPresenter: presenter,
            userDefaults: defaults
        )
        sut.load()
        await waitUntil { if case .loading = sut.loadState { return false } else { return true } }
        #expect(!presenter.isPresenting)
    }

    @Test("does not re-fire celebration for the same tier on second load")
    func noDuplicateCelebration() async throws {
        let defaults = isolatedDefaults()
        let presenter = CelebrationPresenter()
        let state = analystState(recentlyPromoted: true, previousTier: .reader)
        let sut = TierModel(
            repository: makeTierRepository(tier: state),
            celebrationPresenter: presenter,
            userDefaults: defaults
        )
        // First load
        sut.load()
        await waitUntil { if case .loading = sut.loadState { return false } else { return true } }
        presenter.dismissAll()

        // Second load (refresh) — same state, same tier
        await sut.refresh()
        #expect(!presenter.isPresenting, "Second load with same tier must not re-fire celebration")
    }

    @Test("does not fire when recentlyPromoted is nil")
    func noCelebrationWhenNilFlag() async throws {
        let defaults = isolatedDefaults()
        let presenter = CelebrationPresenter()
        let state = TierState(
            currentTier: .analyst,
            nextTier: .synthesizer,
            overallProgress: 0.5,
            metrics: nil,
            recentlyPromoted: nil,
            previousTier: nil
        )
        let sut = TierModel(
            repository: makeTierRepository(tier: state),
            celebrationPresenter: presenter,
            userDefaults: defaults
        )
        sut.load()
        await waitUntil { if case .loading = sut.loadState { return false } else { return true } }
        #expect(!presenter.isPresenting)
    }
}

// MARK: - TierKey tests

@Suite("TierKey")
struct TierKeyTests {

    @Test("known tiers parse from rawValue")
    func knownTierParsing() {
        #expect(TierKey(rawValue: "reader") == .reader)
        #expect(TierKey(rawValue: "analyst") == .analyst)
        #expect(TierKey(rawValue: "synthesizer") == .synthesizer)
        #expect(TierKey(rawValue: "polymath") == .polymath)
        #expect(TierKey(rawValue: "luminary") == .luminary)
    }

    @Test("unknown tier parses to .unknown, not throws")
    func unknownTierParsesToUnknown() {
        let key = TierKey(rawValue: "sage")
        if case .unknown(let raw) = key {
            #expect(raw == "sage")
        } else {
            Issue.record("Expected .unknown(\"sage\")")
        }
    }

    @Test("rawValue round-trips for known tiers")
    func rawValueRoundTrip() {
        for tier in TierKey.allCases {
            #expect(TierKey(rawValue: tier.rawValue) == tier)
        }
    }

    @Test("rawValue round-trips for unknown tier")
    func unknownRawValueRoundTrip() {
        let key = TierKey(rawValue: "oracle")
        #expect(key.rawValue == "oracle")
    }

    @Test("allCases does not include .unknown")
    func allCasesExcludesUnknown() {
        let hasUnknown = TierKey.allCases.contains {
            if case .unknown = $0 { return true }
            return false
        }
        #expect(!hasUnknown)
        #expect(TierKey.allCases.count == 5)
    }

    @Test("rank is ordered reader < analyst < synthesizer < polymath < luminary")
    func rankOrdering() {
        #expect(TierKey.reader.rank < TierKey.analyst.rank)
        #expect(TierKey.analyst.rank < TierKey.synthesizer.rank)
        #expect(TierKey.synthesizer.rank < TierKey.polymath.rank)
        #expect(TierKey.polymath.rank < TierKey.luminary.rank)
    }

    @Test("unknown tier rank is Int.max (never blocks known-tier comparisons)")
    func unknownRankIsMax() {
        #expect(TierKey.unknown("future").rank == Int.max)
        #expect(TierKey.luminary.rank < TierKey.unknown("future").rank)
    }

    @Test("Codable round-trip for known tier")
    func codableKnownTier() throws {
        let encoded = try JSONEncoder().encode(TierKey.synthesizer)
        let decoded = try JSONDecoder().decode(TierKey.self, from: encoded)
        #expect(decoded == .synthesizer)
    }

    @Test("unknown tier decodes to .unknown from JSON, not throws")
    func unknownTierFromJSON() throws {
        let data = Data("\"sage\"".utf8)
        let decoded = try JSONDecoder().decode(TierKey.self, from: data)
        #expect(decoded == .unknown("sage"))
    }

    @Test("parse is case-insensitive")
    func caseInsensitiveParsing() {
        #expect(TierKey(rawValue: "ANALYST") == .analyst)
        #expect(TierKey(rawValue: "Synthesizer") == .synthesizer)
        #expect(TierKey(rawValue: "LUMINARY") == .luminary)
    }
}

// MARK: - TierState decoding tests

@Suite("TierState tolerant decoding")
struct TierStateDecodingTests {

    @Test("decodes all known fields correctly")
    func decodesFullResponse() throws {
        let json = """
        {
            "tier": {
                "currentTier": "analyst",
                "nextTier": "synthesizer",
                "overallProgress": 0.62,
                "metrics": {
                    "loopsCompleted": 18,
                    "loopsTarget": 30,
                    "averageQuizScore": 74.5,
                    "quizScoreTarget": 80.0,
                    "categoriesExplored": 2,
                    "categoriesTarget": 3
                },
                "recentlyPromoted": false,
                "previousTier": null
            }
        }
        """.data(using: .utf8)!
        let resp = try JSONCoding.decoder.decode(TierResponse.self, from: json)
        #expect(resp.tier.currentTier == .analyst)
        #expect(resp.tier.nextTier == .synthesizer)
        #expect(abs(resp.tier.overallProgress - 0.62) < 0.001)
        #expect(resp.tier.metrics?.loopsCompleted == 18)
        #expect(resp.tier.metrics?.loopsTarget == 30)
        #expect(resp.tier.recentlyPromoted == false)
        #expect(resp.tier.previousTier == nil)
    }

    @Test("decodes unknown tier to .unknown, not throws")
    func unknownTierDecodesGracefully() throws {
        let json = """
        {
            "tier": {
                "currentTier": "oracle",
                "nextTier": null,
                "overallProgress": 0.5,
                "recentlyPromoted": false,
                "previousTier": null
            }
        }
        """.data(using: .utf8)!
        let resp = try JSONCoding.decoder.decode(TierResponse.self, from: json)
        #expect(resp.tier.currentTier == .unknown("oracle"))
    }

    @Test("decodes when metrics is absent (server doesn't return it yet)")
    func decodesWithoutMetrics() throws {
        let json = """
        {
            "tier": {
                "currentTier": "luminary",
                "nextTier": null,
                "overallProgress": 1.0,
                "recentlyPromoted": false,
                "previousTier": null
            }
        }
        """.data(using: .utf8)!
        let resp = try JSONCoding.decoder.decode(TierResponse.self, from: json)
        #expect(resp.tier.currentTier == .luminary)
        #expect(resp.tier.metrics == nil)
    }

    @Test("decodes recentlyPromoted with previousTier present")
    func decodesPromotion() throws {
        let json = """
        {
            "tier": {
                "currentTier": "analyst",
                "nextTier": "synthesizer",
                "overallProgress": 0.02,
                "recentlyPromoted": true,
                "previousTier": "reader"
            }
        }
        """.data(using: .utf8)!
        let resp = try JSONCoding.decoder.decode(TierResponse.self, from: json)
        #expect(resp.tier.recentlyPromoted == true)
        #expect(resp.tier.previousTier == .reader)
    }

    @Test("tolerates unknown future fields without throwing")
    func toleratesUnknownFields() throws {
        let json = """
        {
            "tier": {
                "currentTier": "analyst",
                "nextTier": "synthesizer",
                "overallProgress": 0.5,
                "recentlyPromoted": false,
                "previousTier": null,
                "futureField": "value",
                "anotherNew": 42
            }
        }
        """.data(using: .utf8)!
        let resp = try JSONCoding.decoder.decode(TierResponse.self, from: json)
        #expect(resp.tier.currentTier == .analyst)
    }
}
