import Testing
import Foundation
@testable import EngagementFeature
import Models
import Networking
import CoreKit

// MARK: - Shared body helpers

private func makeBody(
    title: String = "Test",
    scenario: String = "My scenario",
    whatToDo: String = "Do this",
    whyItMatters: String = "Because",
    scope: String = "work"
) -> ScenarioPostBody {
    ScenarioPostBody(title: title, scenario: scenario, whatToDo: whatToDo, whyItMatters: whyItMatters, scope: scope)
}

// MARK: - Helpers

private func makeSampleScenario(
    id: String = "s-1",
    bookId: String = "book-1",
    chapterNumber: Int = 1,
    status: ScenarioStatus = .pending
) -> UserScenario {
    UserScenario(
        id: id,
        bookId: bookId,
        chapterNumber: chapterNumber,
        title: "Test Scenario",
        scenario: "In my work as an engineer...",
        whatToDo: "Apply the principle to code reviews.",
        whyItMatters: "Better code, fewer bugs.",
        scope: .work,
        status: status,
        pointsAwarded: status == .approved ? 50 : nil,
        createdAt: Date()
    )
}

private func makeRepo(
    scenarios: [UserScenario] = [],
    community: [CommunityScenario] = []
) -> ScenarioRepository {
    ScenarioRepository.makePreview(myScenarios: scenarios, community: community)
}

// MARK: - ScenarioRepositoryTests

@Suite("ScenarioRepository")
struct ScenarioRepositoryTests {

    @Test("fetchScenarios returns server response")
    func fetchScenariosReturnsList() async throws {
        let scenario = makeSampleScenario()
        let repo = makeRepo(scenarios: [scenario])

        let result = try await repo.fetchScenarios(bookId: "atomic-habits", chapterNumber: 3)

        #expect(result.scenarios.count == 1)
        #expect(result.scenarios[0].id == "s-1")
    }

    @Test("fetchScenarios uses in-memory cache on second call")
    func fetchScenariosUsesCache() async throws {
        let repo = makeRepo(scenarios: [makeSampleScenario()])

        _ = try await repo.fetchScenarios(bookId: "atomic-habits", chapterNumber: 3)
        // Second call with same key returns cached — not an error
        let second = try await repo.fetchScenarios(bookId: "atomic-habits", chapterNumber: 3)
        #expect(second.scenarios.count == 1)
    }

    @Test("fetchScenarios force-refresh fetches again")
    func fetchScenariosForceRefresh() async throws {
        let repo = makeRepo(scenarios: [makeSampleScenario()])

        _ = try await repo.fetchScenarios(bookId: "atomic-habits", chapterNumber: 3)
        let second = try await repo.fetchScenarios(bookId: "atomic-habits", chapterNumber: 3, forceRefresh: true)
        #expect(second.scenarios.count == 1)
    }

    @Test("fetchScenarios isolates cache per chapter")
    func fetchScenariosIsolateCachePerChapter() async throws {
        let repo1 = makeRepo(scenarios: [makeSampleScenario(id: "ch1")])
        let repo2 = makeRepo(scenarios: [makeSampleScenario(id: "ch2")])

        let r1 = try await repo1.fetchScenarios(bookId: "book-1", chapterNumber: 1)
        let r2 = try await repo2.fetchScenarios(bookId: "book-1", chapterNumber: 2)

        #expect(r1.scenarios[0].id == "ch1")
        #expect(r2.scenarios[0].id == "ch2")
    }

    @Test("submitScenario returns server scenario with pending status")
    func submitScenarioReturnsServerResult() async throws {
        let repo = makeRepo()

        let result = try await repo.submitScenario(
            bookId: "atomic-habits",
            chapterNumber: 3,
            body: makeBody(),
            scope: .work
        )

        #expect(result.status == .pending)
        #expect(result.title == "New scenario") // preview stub returns this title
    }

    @Test("submitScenario offline creates local placeholder")
    func submitScenarioOfflineCreatesLocal() async throws {
        let client = MockAPIClient()
        await client.setDefault(.failure(AppError.offline))
        let repo = ScenarioRepository(apiClient: client, modelContainer: nil)

        let result = try await repo.submitScenario(
            bookId: "book-1",
            chapterNumber: 1,
            body: makeBody(title: "Offline Title", scope: "personal"),
            scope: .personal
        )

        #expect(result.id.hasPrefix("local-"))
        #expect(result.status == .pending)
        #expect(result.pointsAwarded == nil)
        #expect(result.scope == .personal)
    }

    @Test("submitScenario offline never grants points")
    func submitScenarioNeverGrantsPoints() async throws {
        let client = MockAPIClient()
        await client.setDefault(.failure(AppError.offline))
        let repo = ScenarioRepository(apiClient: client, modelContainer: nil)

        let result = try await repo.submitScenario(
            bookId: "book-1",
            chapterNumber: 1,
            body: makeBody(),
            scope: .work
        )

        #expect(result.pointsAwarded == nil)
        #expect(result.status == .pending)
    }

    @Test("pendingUploadCount returns 0 with no container")
    func pendingCountNoContainer() async {
        let repo = ScenarioRepository(apiClient: MockAPIClient(), modelContainer: nil)
        let count = await repo.pendingUploadCount()
        #expect(count == 0)
    }

    @Test("invalidateAll clears cache")
    func invalidateAllClearsCache() async throws {
        let client = MockAPIClient()
        let resp = ScenariosResponse(scenarios: [], community: [])
        try await client.setStub(resp, for: "/book/me/books/book-1/chapters/1/scenarios")
        let repo = ScenarioRepository(apiClient: client, modelContainer: nil)

        _ = try await repo.fetchScenarios(bookId: "book-1", chapterNumber: 1)
        await repo.invalidateAll()
        // After invalidation, should re-fetch (no cached value)
        _ = try await repo.fetchScenarios(bookId: "book-1", chapterNumber: 1)

        let recorded = await client.recordedEndpoints
        #expect(recorded.count == 2)
    }
}

// MARK: - ScenarioScopeTests

@Suite("ScenarioScope — server evolution")
struct ScenarioScopeTests {
    @Test("known values decode correctly")
    func knownValues() {
        #expect(ScenarioScope(rawValue: "work") == .work)
        #expect(ScenarioScope(rawValue: "school") == .school)
        #expect(ScenarioScope(rawValue: "personal") == .personal)
    }

    @Test("unknown raw value maps to .unknown, never crashes")
    func unknownNeverCrashes() {
        let scope = ScenarioScope(rawValue: "community_pool")
        guard case .unknown(let raw) = scope else {
            Issue.record("Expected .unknown, got \(scope)")
            return
        }
        #expect(raw == "community_pool")
    }

    @Test("decodes unknown from JSON without throwing")
    func decodesUnknownFromJSON() throws {
        let json = #"{"scope":"future_value"}"#.data(using: .utf8)!
        struct ScopeWrapper: Decodable { let scope: ScenarioScope }
        let wrapper = try JSONDecoder().decode(ScopeWrapper.self, from: json)
        guard case .unknown(let raw) = wrapper.scope else {
            Issue.record("Expected .unknown")
            return
        }
        #expect(raw == "future_value")
    }

    @Test("round-trips through encode/decode")
    func roundTrips() throws {
        let scope = ScenarioScope.personal
        let data = try JSONEncoder().encode(scope)
        let decoded = try JSONDecoder().decode(ScenarioScope.self, from: data)
        #expect(decoded == scope)
    }
}

// MARK: - ScenarioStatusTests

@Suite("ScenarioStatus — server evolution")
struct ScenarioStatusTests {
    @Test("known values decode correctly")
    func knownValues() {
        #expect(ScenarioStatus(rawValue: "pending") == .pending)
        #expect(ScenarioStatus(rawValue: "approved") == .approved)
        #expect(ScenarioStatus(rawValue: "rejected") == .rejected)
    }

    @Test("unknown value maps to .unknown")
    func unknownValue() {
        let status = ScenarioStatus(rawValue: "flagged_for_review")
        guard case .unknown(let raw) = status else {
            Issue.record("Expected .unknown")
            return
        }
        #expect(raw == "flagged_for_review")
    }
}

// MARK: - ScenariosResponseTests

@Suite("ScenariosResponse — decoding")
struct ScenariosResponseTests {
    @Test("decodes full response with scenarios and community")
    func decodesFullResponse() throws {
        let json = """
        {
            "scenarios": [
                {
                    "id": "s-1",
                    "bookId": "b-1",
                    "chapterNumber": 1,
                    "title": "Test",
                    "scenario": "My scenario",
                    "whatToDo": "Do this",
                    "whyItMatters": "Because",
                    "scope": "work",
                    "status": "pending",
                    "createdAt": "2026-01-01T00:00:00Z"
                }
            ],
            "community": [
                {
                    "id": "cs-1",
                    "title": "Community one",
                    "scenario": "Community scenario",
                    "whatToDo": "Community action",
                    "whyItMatters": "Community reason",
                    "scope": "personal",
                    "authorName": "Alex K.",
                    "createdAt": "2026-01-01T00:00:00Z"
                }
            ]
        }
        """.data(using: .utf8)!

        let resp = try JSONCoding.decoder.decode(ScenariosResponse.self, from: json)
        #expect(resp.scenarios.count == 1)
        #expect(resp.community.count == 1)
        #expect(resp.scenarios[0].scope == .work)
        #expect(resp.community[0].scope == .personal)
    }

    @Test("empty community array does not throw")
    func emptyCommunityOK() throws {
        let json = #"{"scenarios":[],"community":[]}"#.data(using: .utf8)!
        let resp = try JSONCoding.decoder.decode(ScenariosResponse.self, from: json)
        #expect(resp.scenarios.isEmpty)
        #expect(resp.community.isEmpty)
    }

    @Test("malformed scenario element is dropped, good ones survive")
    func lossyDecodeDropsMalformed() throws {
        let json = """
        {
            "scenarios": [
                null,
                {
                    "id": "s-good",
                    "bookId": "b",
                    "chapterNumber": 1,
                    "title": "Good",
                    "scenario": "Good scenario",
                    "whatToDo": "Do",
                    "whyItMatters": "Why",
                    "scope": "work",
                    "status": "pending",
                    "createdAt": "2026-01-01T00:00:00Z"
                }
            ],
            "community": []
        }
        """.data(using: .utf8)!

        let resp = try JSONCoding.decoder.decode(ScenariosResponse.self, from: json)
        #expect(resp.scenarios.count == 1)
        #expect(resp.scenarios[0].id == "s-good")
    }

    @Test("unknown scope does not crash decoding")
    func unknownScopeDoesNotCrash() throws {
        let json = """
        {
            "scenarios": [
                {
                    "id": "s-1",
                    "bookId": "b-1",
                    "chapterNumber": 1,
                    "title": "T",
                    "scenario": "S",
                    "whatToDo": "W",
                    "whyItMatters": "Y",
                    "scope": "new_scope_from_future",
                    "status": "pending",
                    "createdAt": "2026-01-01T00:00:00Z"
                }
            ],
            "community": []
        }
        """.data(using: .utf8)!

        let resp = try JSONCoding.decoder.decode(ScenariosResponse.self, from: json)
        #expect(resp.scenarios.count == 1)
        guard case .unknown(let raw) = resp.scenarios[0].scope else {
            Issue.record("Expected .unknown scope")
            return
        }
        #expect(raw == "new_scope_from_future")
    }

    @Test("unknown status does not crash decoding")
    func unknownStatusDoesNotCrash() throws {
        let json = """
        {
            "scenarios": [
                {
                    "id": "s-1",
                    "bookId": "b-1",
                    "chapterNumber": 1,
                    "title": "T",
                    "scenario": "S",
                    "whatToDo": "W",
                    "whyItMatters": "Y",
                    "scope": "work",
                    "status": "under_appeal",
                    "createdAt": "2026-01-01T00:00:00Z"
                }
            ],
            "community": []
        }
        """.data(using: .utf8)!

        let resp = try JSONCoding.decoder.decode(ScenariosResponse.self, from: json)
        #expect(resp.scenarios.count == 1)
        guard case .unknown(let raw) = resp.scenarios[0].status else {
            Issue.record("Expected .unknown status")
            return
        }
        #expect(raw == "under_appeal")
    }
}

// MARK: - ScenariosModelTests

@Suite("ScenariosModel")
@MainActor
struct ScenariosModelTests {

    @Test("isFormValid false when fields empty")
    func formInvalidWhenEmpty() {
        let model = ScenariosModel(
            repository: .makePreview(),
            bookId: "book-1",
            chapterNumber: 1
        )
        #expect(!model.isFormValid)
    }

    @Test("isFormValid true when all fields filled")
    func formValidWhenFilled() {
        let model = ScenariosModel(
            repository: .makePreview(),
            bookId: "book-1",
            chapterNumber: 1
        )
        model.title = "My Title"
        model.scenario = "My scenario"
        model.whatToDo = "My action"
        model.whyItMatters = "My reason"
        model.selectedScope = .work
        #expect(model.isFormValid)
    }

    @Test("isTitleOverLimit flags correctly at limit+1")
    func titleOverLimit() {
        let model = ScenariosModel(
            repository: .makePreview(),
            bookId: "book-1",
            chapterNumber: 1
        )
        model.title = String(repeating: "a", count: ScenariosModel.titleLimit + 1)
        #expect(model.isTitleOverLimit)
        #expect(model.hasAnyOverLimit)
    }

    @Test("isScenarioOverLimit flags correctly at limit+1")
    func scenarioOverLimit() {
        let model = ScenariosModel(
            repository: .makePreview(),
            bookId: "book-1",
            chapterNumber: 1
        )
        model.scenario = String(repeating: "a", count: ScenariosModel.fieldLimit + 1)
        #expect(model.isScenarioOverLimit)
    }

    @Test("hasAnyOverLimit false when all fields within limits")
    func noOverLimit() {
        let model = ScenariosModel(
            repository: .makePreview(),
            bookId: "book-1",
            chapterNumber: 1
        )
        model.title = "OK"
        model.scenario = "OK"
        model.whatToDo = "OK"
        model.whyItMatters = "OK"
        #expect(!model.hasAnyOverLimit)
    }

    @Test("resetForm clears all fields")
    func resetFormClearsFields() {
        let model = ScenariosModel(
            repository: .makePreview(),
            bookId: "book-1",
            chapterNumber: 1
        )
        model.title = "Something"
        model.scenario = "Scenario"
        model.whatToDo = "Action"
        model.whyItMatters = "Reason"
        model.resetForm()
        #expect(model.title.isEmpty)
        #expect(model.scenario.isEmpty)
        #expect(model.whatToDo.isEmpty)
        #expect(model.whyItMatters.isEmpty)
    }

    @Test("myScenarios empty before load")
    func myScenariosEmptyBeforeLoad() {
        let model = ScenariosModel(
            repository: .makePreview(),
            bookId: "book-1",
            chapterNumber: 1
        )
        #expect(model.myScenarios.isEmpty)
    }

    @Test("communityScenarios empty before load")
    func communityScenariosEmptyBeforeLoad() {
        let model = ScenariosModel(
            repository: .makePreview(),
            bookId: "book-1",
            chapterNumber: 1
        )
        #expect(model.communityScenarios.isEmpty)
    }
}
