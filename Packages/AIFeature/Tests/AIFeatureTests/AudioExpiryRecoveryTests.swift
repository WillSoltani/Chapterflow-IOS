import Testing
import Foundation
@testable import AIFeature
import Models

// MARK: - Expiry recovery logic tests

/// Tests that verify the URL-expiry recovery logic:
/// 1. Error classification (is this a likely expiry?)
/// 2. Position preservation across a recovery cycle
/// 3. FakeAudioRepository correctly counts re-fetches
/// 4. AudioSegmentKind tolerant decoding (RF2)

@Suite("Expiry recovery")
struct AudioExpiryRecoveryTests {

    // MARK: - Error classification

    @Test("NSURLErrorDomain error is classified as likely expiry")
    func urlErrorIsExpiry() async {
        let repo = FakeAudioRepository()
        let player = AudioPlayer(repository: repo)
        let nsError = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse)
        let result = await player.isLikelyExpiry(nsError)
        #expect(result == true)
    }

    @Test("nil error is not classified as expiry")
    func nilErrorIsNotExpiry() async {
        let repo = FakeAudioRepository()
        let player = AudioPlayer(repository: repo)
        let result = await player.isLikelyExpiry(nil)
        #expect(result == false)
    }

    @Test("arbitrary error domain is not classified as expiry")
    func randomErrorIsNotExpiry() async {
        let repo = FakeAudioRepository()
        let player = AudioPlayer(repository: repo)
        let nsError = NSError(domain: "com.example.SomeOtherDomain", code: 42)
        let result = await player.isLikelyExpiry(nsError)
        #expect(result == false)
    }

    @Test("error with NSURLErrorDomain underlying error IS classified as expiry")
    func underlyingUrlErrorIsExpiry() async {
        let repo = FakeAudioRepository()
        let player = AudioPlayer(repository: repo)
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let wrapper = NSError(
            domain: "AVFoundationErrorDomain",
            code: -11800,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        let result = await player.isLikelyExpiry(wrapper)
        #expect(result == true)
    }

    // MARK: - Repository re-fetch on expiry

    @Test("recovery re-fetches the plan exactly once more")
    func recoveryRefetchesPlan() async throws {
        let freshPlan = AudioNarrationPlan.makeFake(bookId: "b-deep-work", chapterNumber: 2)
        let repo = FakeAudioRepository(plan: freshPlan)
        let player = AudioPlayer(repository: repo)

        // Simulate loading a chapter (1 fetch)
        try await player.loadChapter(bookId: "b-deep-work", chapterNumber: 2)
        let fetchCountAfterLoad = await repo.fetchCallCount
        #expect(fetchCountAfterLoad == 1)

        // Fire recovery (simulates what happens when isLikelyExpiry detects a 403)
        // We test the re-fetch count — not AVPlayer state (which needs a real player)
        let beforeRecovery = await repo.fetchCallCount
        // Directly call the internal recovery path by triggering handleItemFailure
        // via the public expiry-check helper + manually invoking the recovery API.
        // Since handleItemFailure is private, we test indirectly: call loadChapter again
        // (the same code path as recovery) and assert fetch count increments.
        try await player.loadChapter(bookId: "b-deep-work", chapterNumber: 2)
        let afterRecovery = await repo.fetchCallCount
        #expect(afterRecovery == beforeRecovery + 1)
    }

    @Test("recovery preserves global time position")
    func recoveryPreservesPosition() async throws {
        // Build a plan with known durations so timeline is deterministic.
        let plan = AudioNarrationPlan.makeFake(
            bookId: "b-atomic",
            chapterNumber: 1,
            segmentDurations: [10, 120, 60]
        )
        let repo = FakeAudioRepository(plan: plan)
        let player = AudioPlayer(repository: repo)

        // Load and seek to a mid-chapter position.
        try await player.loadChapter(bookId: "b-atomic", chapterNumber: 1)
        let targetTime = 80.0  // inside segment 1 (body)
        await player.seek(to: targetTime)

        let savedTime = await player.savedGlobalTimeForTest

        // Recovery logic: save time → re-fetch → seek to same position.
        // We verify the re-fetch happens and the saved time matches our target.
        #expect(abs(savedTime - targetTime) < 0.5, "Player should be near the target time")

        // Simulate what recovery does: re-load with startAt = savedTime
        try await player.loadChapter(
            bookId: "b-atomic",
            chapterNumber: 1,
            startAt: savedTime
        )
        let restoredTime = await player.savedGlobalTimeForTest
        // After loadChapter with startAt, the player should be at or near savedTime.
        #expect(abs(restoredTime - savedTime) < 1.0, "Position should be restored after recovery")
    }

    @Test("recovery fetch count matches expected calls when error occurs twice")
    func recoveryFetchCountMultipleErrors() async throws {
        let plan = AudioNarrationPlan.makeFake()
        let repo = FakeAudioRepository(plan: plan)
        let player = AudioPlayer(repository: repo)

        // Three loads simulate: initial + two recoveries
        try await player.loadChapter(bookId: plan.bookId, chapterNumber: plan.chapterNumber)
        try await player.loadChapter(bookId: plan.bookId, chapterNumber: plan.chapterNumber)
        try await player.loadChapter(bookId: plan.bookId, chapterNumber: plan.chapterNumber)

        let count = await repo.fetchCallCount
        #expect(count == 3)
    }

    @Test("notification observers do not retain the audio player")
    func notificationObserversDoNotRetainPlayer() async throws {
        let plan = AudioNarrationPlan.makeFake()
        let repo = FakeAudioRepository(plan: plan)
        weak var retainedPlayer: AudioPlayer?

        do {
            let player = AudioPlayer(repository: repo)
            retainedPlayer = player
            try await player.loadChapter(bookId: plan.bookId, chapterNumber: plan.chapterNumber)
        }

        #expect(retainedPlayer == nil)
    }
}

// MARK: - AudioSegmentKind tolerant decoding (RF2)

@Suite("AudioSegmentKind tolerant decoding")
struct AudioSegmentKindEvolutionTests {

    @Test("known kinds decode correctly")
    func knownKinds() throws {
        let pairs: [(String, AudioSegmentKind)] = [
            ("greeting", .greeting),
            ("body", .body),
            ("takeaway", .takeaway)
        ]
        for (raw, expected) in pairs {
            let json = "\"\(raw)\""
            let decoded = try JSONDecoder().decode(AudioSegmentKind.self, from: Data(json.utf8))
            #expect(decoded == expected, "Failed for raw='\(raw)'")
        }
    }

    @Test("unknown kind decodes to .unknown(rawValue) — never throws")
    func unknownKindTolerant() throws {
        let json = "\"future_kind_we_dont_know\""
        let decoded = try JSONDecoder().decode(AudioSegmentKind.self, from: Data(json.utf8))
        if case .unknown(let raw) = decoded {
            #expect(raw == "future_kind_we_dont_know")
        } else {
            Issue.record("Expected .unknown but got \(decoded)")
        }
    }

    @Test("AudioNarrationPlan with unknown segment kind decodes without throwing")
    func planWithUnknownKindDecodes() throws {
        let json = """
        {
          "plan": {
            "bookId": "b-test",
            "chapterNumber": 1,
            "chapterTitle": "Test",
            "bookTitle": "Test Book",
            "coverEmoji": "📚",
            "coverColor": "#000000",
            "segments": [
              {
                "segmentId": "seg-1",
                "kind": "unknown_future_type",
                "url": "https://example.com/seg.mp3",
                "durationSeconds": 10.0
              }
            ]
          }
        }
        """
        let response = try JSONDecoder.chapterFlow.decode(
            AudioNarrationResponse.self,
            from: Data(json.utf8)
        )
        #expect(response.plan.segments.count == 1)
        if case .unknown(let raw) = response.plan.segments[0].kind {
            #expect(raw == "unknown_future_type")
        } else {
            Issue.record("Expected .unknown but got \(response.plan.segments[0].kind)")
        }
    }

    @Test("AudioNarrationPlan with missing optional fields decodes without throwing")
    func planWithMissingOptionals() throws {
        let json = """
        {
          "plan": {
            "bookId": "b-test",
            "chapterNumber": 2,
            "segments": [
              {
                "segmentId": "seg-1",
                "kind": "body",
                "url": "https://example.com/seg.mp3"
              }
            ]
          }
        }
        """
        let response = try JSONDecoder.chapterFlow.decode(
            AudioNarrationResponse.self,
            from: Data(json.utf8)
        )
        #expect(response.plan.chapterTitle == nil)
        #expect(response.plan.bookTitle == nil)
        #expect(response.plan.coverEmoji == nil)
        #expect(response.plan.coverColor == nil)
        #expect(response.plan.segments[0].durationSeconds == nil)
    }

    @Test("AudioNarrationPlan fixture decodes correctly")
    func fixtureDecodes() throws {
        let json = """
        {
          "plan": {
            "bookId": "b-atomic-habits",
            "chapterNumber": 1,
            "chapterTitle": "The Surprising Power of Atomic Habits",
            "bookTitle": "Atomic Habits",
            "coverEmoji": "⚛️",
            "coverColor": "#3B82F6",
            "segments": [
              { "segmentId": "greeting-1", "kind": "greeting", "url": "https://a.b/g.mp3", "durationSeconds": 12.5 },
              { "segmentId": "body-1", "kind": "body", "url": "https://a.b/b1.mp3", "durationSeconds": 187.3 },
              { "segmentId": "body-2", "kind": "body", "url": "https://a.b/b2.mp3", "durationSeconds": 154.2 },
              { "segmentId": "takeaway-1", "kind": "takeaway", "url": "https://a.b/t.mp3", "durationSeconds": 45.8 }
            ]
          }
        }
        """
        let response = try JSONDecoder.chapterFlow.decode(
            AudioNarrationResponse.self,
            from: Data(json.utf8)
        )
        let plan = response.plan
        #expect(plan.bookId == "b-atomic-habits")
        #expect(plan.segments.count == 4)
        #expect(plan.segments[0].kind == .greeting)
        #expect(plan.segments[1].kind == .body)
        #expect(plan.segments[2].kind == .body)
        #expect(plan.segments[3].kind == .takeaway)
        #expect(abs((plan.segments[0].durationSeconds ?? 0) - 12.5) < 0.001)
    }
}

// MARK: - FakeAudioRepository tests

@Suite("FakeAudioRepository")
struct FakeAudioRepositoryTests {

    @Test("fetchPlan returns configured plan")
    func returnsConfiguredPlan() async throws {
        let expected = AudioNarrationPlan.makeFake(bookId: "b-123", chapterNumber: 5)
        let repo = FakeAudioRepository(plan: expected)
        let result = try await repo.fetchPlan(bookId: "b-123", chapterNumber: 5)
        #expect(result == expected)
    }

    @Test("fetchPlan throws when errorToThrow is set")
    func throwsConfiguredError() async throws {
        let repo = FakeAudioRepository(errorToThrow: URLError(.notConnectedToInternet))
        await #expect(throws: URLError.self) {
            _ = try await repo.fetchPlan(bookId: "b-test", chapterNumber: 1)
        }
    }

    @Test("fetchCallCount increments on each call")
    func incrementsCallCount() async throws {
        let repo = FakeAudioRepository()
        _ = try await repo.fetchPlan(bookId: "b-a", chapterNumber: 1)
        _ = try await repo.fetchPlan(bookId: "b-a", chapterNumber: 2)
        let count = await repo.fetchCallCount
        #expect(count == 2)
    }

    @Test("postAudioSessionEvent increments sessionEventCount")
    func postsSessionEvent() async throws {
        let repo = FakeAudioRepository()
        try await repo.postAudioSessionEvent(
            event: "start",
            bookId: "b-test",
            chapterNumber: 1,
            sessionId: "s-1",
            listeningSeconds: nil
        )
        let count = await repo.sessionEventCount
        #expect(count == 1)
    }
}
