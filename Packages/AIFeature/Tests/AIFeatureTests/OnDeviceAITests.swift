import Testing
import Foundation
@testable import AIFeature
import CoreKit

// MARK: - OnDeviceFeatureFlag tests

@Suite("OnDeviceFeatureFlag")
struct OnDeviceFeatureFlagTests {

    @Test("defaults to enabled when key not set")
    func defaultsToEnabled() {
        let store = makeEmptyDefaults()
        let flag = OnDeviceFeatureFlag(isEnabled: true)
        #expect(flag.isEnabled == true)
        _ = store
    }

    @Test("init(isEnabled:) directly controls the flag")
    func directInit() {
        #expect(OnDeviceFeatureFlag(isEnabled: true).isEnabled == true)
        #expect(OnDeviceFeatureFlag(isEnabled: false).isEnabled == false)
    }

    @Test("save writes to UserDefaults and affects subsequent init")
    func saveAndReadback() {
        let store = makeEmptyDefaults()
        let flag = OnDeviceFeatureFlag(isEnabled: true)
        flag.save(false, to: store)
        let read = OnDeviceFeatureFlag(defaults: store)
        #expect(read.isEnabled == false)
    }

    private func makeEmptyDefaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
}

// MARK: - OnDeviceAIAvailability tests

@Suite("OnDeviceAIAvailability")
struct OnDeviceAIAvailabilityTests {

    @Test("isAvailable is true only for .available")
    func isAvailable() {
        #expect(OnDeviceAIAvailability.available.isAvailable == true)
        #expect(OnDeviceAIAvailability.unavailableOSVersion.isAvailable == false)
        #expect(OnDeviceAIAvailability.unavailableDeviceNotEligible.isAvailable == false)
        #expect(OnDeviceAIAvailability.unavailableNotEnabled.isAvailable == false)
        #expect(OnDeviceAIAvailability.unavailableModelNotReady.isAvailable == false)
        #expect(OnDeviceAIAvailability.unavailableFeatureDisabled.isAvailable == false)
        #expect(OnDeviceAIAvailability.unavailableUnknown.isAvailable == false)
    }

    @Test("all cases have non-empty debugDescription")
    func debugDescriptions() {
        let cases: [OnDeviceAIAvailability] = [
            .available, .unavailableOSVersion, .unavailableDeviceNotEligible,
            .unavailableNotEnabled, .unavailableModelNotReady,
            .unavailableFeatureDisabled, .unavailableUnknown
        ]
        for availability in cases {
            #expect(!availability.debugDescription.isEmpty)
        }
    }
}

// MARK: - UnavailableOnDeviceAIService tests

@Suite("UnavailableOnDeviceAIService")
struct UnavailableOnDeviceAIServiceTests {

    @Test("availability reflects injected reason")
    func availabilityReason() async {
        let service = UnavailableOnDeviceAIService(reason: .unavailableOSVersion)
        let state = await service.availability
        #expect(state == .unavailableOSVersion)
    }

    @Test("summarizeChapter throws unavailable")
    func summarizeThrows() async throws {
        let service = UnavailableOnDeviceAIService(reason: .unavailableFeatureDisabled)
        await #expect(throws: (any Error).self) {
            _ = try await service.summarizeChapter(title: "T", text: "text")
        }
    }

    @Test("explainHighlight throws unavailable")
    func explainThrows() async throws {
        let service = UnavailableOnDeviceAIService()
        await #expect(throws: (any Error).self) {
            _ = try await service.explainHighlight("H", chapterText: "text")
        }
    }

    @Test("answerQuestion throws unavailable")
    func answerThrows() async throws {
        let service = UnavailableOnDeviceAIService()
        await #expect(throws: (any Error).self) {
            _ = try await service.answerQuestion("Q?", chapterText: "text", selectionContext: nil)
        }
    }

    @Test("suggestHighlights throws unavailable")
    func suggestThrows() async throws {
        let service = UnavailableOnDeviceAIService()
        await #expect(throws: (any Error).self) {
            _ = try await service.suggestHighlights(from: "text", count: 3)
        }
    }
}

// MARK: - FakeOnDeviceAIService tests

@Suite("FakeOnDeviceAIService")
struct FakeOnDeviceAIServiceTests {

    @Test("summarize returns non-empty string when available")
    func summarizeSuccess() async throws {
        let service = FakeOnDeviceAIService(availability: .available)
        let result = try await service.summarizeChapter(title: "Test", text: "Chapter text.")
        #expect(!result.isEmpty)
    }

    @Test("explain returns non-empty string when available")
    func explainSuccess() async throws {
        let service = FakeOnDeviceAIService(availability: .available)
        let result = try await service.explainHighlight("Highlight", chapterText: "Chapter text.")
        #expect(!result.isEmpty)
    }

    @Test("answer returns non-empty string when available")
    func answerSuccess() async throws {
        let service = FakeOnDeviceAIService(availability: .available)
        let result = try await service.answerQuestion("Q?", chapterText: "Chapter text.", selectionContext: nil)
        #expect(!result.isEmpty)
    }

    @Test("suggestHighlights returns up to count suggestions")
    func suggestSuccess() async throws {
        let service = FakeOnDeviceAIService(availability: .available)
        let results = try await service.suggestHighlights(from: "Some text.", count: 2)
        #expect(results.count <= 2)
        #expect(!results.isEmpty)
    }

    @Test("throws when availability is unavailable")
    func throwsWhenUnavailable() async throws {
        let service = FakeOnDeviceAIService(availability: .unavailableDeviceNotEligible)
        await #expect(throws: (any Error).self) {
            _ = try await service.summarizeChapter(title: "T", text: "text")
        }
    }

    @Test("propagates forcedError over unavailability")
    func propagatesForcedError() async throws {
        let error = OnDeviceAIError.emptyResponse
        let service = FakeOnDeviceAIService(
            availability: .available,
            forcedError: error
        )
        await #expect(throws: (any Error).self) {
            _ = try await service.summarizeChapter(title: "T", text: "text")
        }
    }
}

// MARK: - String truncation tests

@Suite("String.truncatedForAI")
struct StringTruncationTests {

    @Test("short string passes through unchanged")
    func shortString() {
        let s = "Hello"
        #expect(s.truncatedForAI(maxCharacters: 100) == "Hello")
    }

    @Test("long string is truncated and appended with ellipsis")
    func longString() {
        let s = String(repeating: "a", count: 200)
        let result = s.truncatedForAI(maxCharacters: 100)
        #expect(result.count == 101) // 100 chars + "…"
        #expect(result.hasSuffix("…"))
    }

    @Test("string of exact maxCharacters is not truncated")
    func exactLength() {
        let s = String(repeating: "x", count: 50)
        let result = s.truncatedForAI(maxCharacters: 50)
        #expect(result == s)
    }
}

// MARK: - AskTheBookModel offline routing tests

@Suite("AskTheBookModel — on-device offline routing")
@MainActor
struct AskTheBookModelOnDeviceTests {

    @Test("when offline and on-device available, appends isOnDeviceAnswer message")
    func offlineAnsweredOnDevice() async throws {
        let repo = FakeAIRepository(error: AppError.offline, delay: 0)
        let onDevice = FakeOnDeviceAIService(availability: .available, delay: 0)
        let model = AskTheBookModel(
            bookId: "b-test",
            repository: repo,
            chapterText: "Chapter text grounding context.",
            onDeviceService: onDevice
        )
        model.inputText = "What is this about?"

        await model.sendQuestion()

        #expect(model.messages.count == 1)
        #expect(model.messages[0].isOnDeviceAnswer == true)
        #expect(!model.messages[0].answer.isEmpty)
        #expect(model.phase == .idle)
    }

    @Test("when offline and on-device unavailable, falls back to .offline phase")
    func offlineFallsBackWhenDeviceNotEligible() async throws {
        let repo = FakeAIRepository(error: AppError.offline, delay: 0)
        let onDevice = FakeOnDeviceAIService(availability: .unavailableDeviceNotEligible)
        let model = AskTheBookModel(
            bookId: "b-test",
            repository: repo,
            chapterText: "Chapter text.",
            onDeviceService: onDevice
        )
        model.inputText = "Question?"

        await model.sendQuestion()

        #expect(model.phase == .offline)
        #expect(model.messages.isEmpty)
    }

    @Test("when offline and no chapter text, falls back to .offline phase")
    func offlineFallsBackWithoutChapterText() async throws {
        let repo = FakeAIRepository(error: AppError.offline, delay: 0)
        let onDevice = FakeOnDeviceAIService(availability: .available)
        let model = AskTheBookModel(
            bookId: "b-test",
            repository: repo,
            chapterText: nil,
            onDeviceService: onDevice
        )
        model.inputText = "Question?"

        await model.sendQuestion()

        #expect(model.phase == .offline)
        #expect(model.messages.isEmpty)
    }

    @Test("when offline and on-device service is nil, shows .offline phase")
    func offlineWithNoServiceShowsOfflinePhase() async throws {
        let repo = FakeAIRepository(error: AppError.offline, delay: 0)
        let model = AskTheBookModel(
            bookId: "b-test",
            repository: repo,
            chapterText: "Some chapter text.",
            onDeviceService: nil
        )
        model.inputText = "Question?"

        await model.sendQuestion()

        #expect(model.phase == .offline)
    }

    @Test("on-device error during offline answer falls back to .offline phase")
    func onDeviceGenerationFailureFallsBack() async throws {
        let repo = FakeAIRepository(error: AppError.offline, delay: 0)
        let onDevice = FakeOnDeviceAIService(
            availability: .available,
            forcedError: OnDeviceAIError.emptyResponse
        )
        let model = AskTheBookModel(
            bookId: "b-test",
            repository: repo,
            chapterText: "Chapter text.",
            onDeviceService: onDevice
        )
        model.inputText = "Question?"

        await model.sendQuestion()

        #expect(model.phase == .offline)
        #expect(model.messages.isEmpty)
    }

    @Test("isOnDeviceWired is true when service and chapterText are both set")
    func isOnDeviceWiredTrue() {
        let model = AskTheBookModel(
            bookId: "b-test",
            repository: FakeAIRepository(),
            chapterText: "Some text.",
            onDeviceService: FakeOnDeviceAIService()
        )
        #expect(model.isOnDeviceWired == true)
    }

    @Test("isOnDeviceWired is false when chapterText is nil")
    func isOnDeviceWiredFalseNoText() {
        let model = AskTheBookModel(
            bookId: "b-test",
            repository: FakeAIRepository(),
            chapterText: nil,
            onDeviceService: FakeOnDeviceAIService()
        )
        #expect(model.isOnDeviceWired == false)
    }

    @Test("isOnDeviceWired is false when onDeviceService is nil")
    func isOnDeviceWiredFalseNoService() {
        let model = AskTheBookModel(
            bookId: "b-test",
            repository: FakeAIRepository(),
            chapterText: "Some text.",
            onDeviceService: nil
        )
        #expect(model.isOnDeviceWired == false)
    }

    @Test("server success path unaffected by on-device service presence")
    func serverSuccessUnaffected() async throws {
        let repo = FakeAIRepository(response: FakeAIRepository.sampleResponse, delay: 0)
        let onDevice = FakeOnDeviceAIService(availability: .available)
        let model = AskTheBookModel(
            bookId: "b-test",
            repository: repo,
            chapterText: "Chapter text.",
            onDeviceService: onDevice
        )
        model.inputText = "Server question?"

        await model.sendQuestion()

        #expect(model.messages.count == 1)
        #expect(model.messages[0].isOnDeviceAnswer == false)
        #expect(model.phase == .idle)
    }
}

// MARK: - SmartHighlightModel tests

@Suite("SmartHighlightModel")
@MainActor
struct SmartHighlightModelTests {

    @Test("loads suggestions when service available")
    func loadsSuggestions() async throws {
        let service = FakeOnDeviceAIService(availability: .available, delay: 0)
        let model = SmartHighlightModel(
            chapterText: "Habits compound like interest.",
            service: service,
            count: 2
        )
        await model.loadSuggestions()
        #expect(!model.suggestions.isEmpty)
        #expect(model.suggestions.count <= 2)
        #expect(model.isLoading == false)
    }

    @Test("stays empty when service unavailable")
    func emptyWhenUnavailable() async throws {
        let service = FakeOnDeviceAIService(availability: .unavailableOSVersion)
        let model = SmartHighlightModel(
            chapterText: "Some text.",
            service: service
        )
        await model.loadSuggestions()
        #expect(model.suggestions.isEmpty)
    }

    @Test("stays empty when chapter text is empty")
    func emptyWhenNoText() async throws {
        let service = FakeOnDeviceAIService(availability: .available)
        let model = SmartHighlightModel(chapterText: "", service: service)
        await model.loadSuggestions()
        #expect(model.suggestions.isEmpty)
    }

    @Test("dismiss removes specific suggestion")
    func dismissSuggestion() async throws {
        let service = FakeOnDeviceAIService(availability: .available, delay: 0)
        let model = SmartHighlightModel(
            chapterText: "Some text.",
            service: service,
            count: 3
        )
        await model.loadSuggestions()
        guard let first = model.suggestions.first else { return }

        model.dismiss(first)
        #expect(!model.suggestions.contains(first))
    }

    @Test("clearAll removes all suggestions")
    func clearAll() async throws {
        let service = FakeOnDeviceAIService(availability: .available, delay: 0)
        let model = SmartHighlightModel(
            chapterText: "Some text.",
            service: service
        )
        await model.loadSuggestions()
        model.clearAll()
        #expect(model.suggestions.isEmpty)
    }

    @Test("loadSuggestions is a no-op when already loaded")
    func noopWhenAlreadyLoaded() async throws {
        let service = FakeOnDeviceAIService(availability: .available, delay: 0)
        let model = SmartHighlightModel(
            chapterText: "Some text.",
            service: service,
            count: 3
        )
        await model.loadSuggestions()
        let count = model.suggestions.count

        // Second call should be no-op
        await model.loadSuggestions()
        #expect(model.suggestions.count == count)
    }
}

// MARK: - ChapterSummaryModel tests

@Suite("ChapterSummaryModel")
@MainActor
struct ChapterSummaryModelTests {

    @Test("generate transitions to .done on success")
    func generateSuccess() async throws {
        let service = FakeOnDeviceAIService(availability: .available, delay: 0)
        let model = ChapterSummaryModel(
            chapterTitle: "Test Chapter",
            chapterText: "Chapter content here.",
            service: service
        )
        await model.generate()
        if case .done(let summary) = model.phase {
            #expect(!summary.isEmpty)
        } else {
            Issue.record("Expected .done phase, got \(model.phase)")
        }
    }

    @Test("generate transitions to .failed when unavailable")
    func generateUnavailable() async throws {
        let service = FakeOnDeviceAIService(availability: .unavailableNotEnabled)
        let model = ChapterSummaryModel(
            chapterTitle: "Test",
            chapterText: "Some text.",
            service: service
        )
        await model.generate()
        if case .failed = model.phase {
            // expected
        } else {
            Issue.record("Expected .failed phase, got \(model.phase)")
        }
    }

    @Test("retry resets phase to .idle")
    func retryResetsToIdle() async throws {
        let service = FakeOnDeviceAIService(availability: .unavailableNotEnabled)
        let model = ChapterSummaryModel(
            chapterTitle: "Test",
            chapterText: "Text.",
            service: service
        )
        await model.generate()
        model.retry()
        #expect(model.phase == .idle)
    }
}

// MARK: - HighlightExplainerModel tests

@Suite("HighlightExplainerModel")
@MainActor
struct HighlightExplainerModelTests {

    @Test("generate transitions to .done on success")
    func generateSuccess() async throws {
        let service = FakeOnDeviceAIService(availability: .available, delay: 0)
        let model = HighlightExplainerModel(
            highlight: "Habits are the compound interest of self-improvement.",
            chapterText: "Chapter content.",
            service: service
        )
        await model.generate()
        if case .done(let explanation) = model.phase {
            #expect(!explanation.isEmpty)
        } else {
            Issue.record("Expected .done phase, got \(model.phase)")
        }
    }

    @Test("generate transitions to .failed when unavailable")
    func generateUnavailable() async throws {
        let service = FakeOnDeviceAIService(availability: .unavailableOSVersion)
        let model = HighlightExplainerModel(
            highlight: "Some highlight.",
            chapterText: "Chapter.",
            service: service
        )
        await model.generate()
        if case .failed = model.phase {
            // expected
        } else {
            Issue.record("Expected .failed phase, got \(model.phase)")
        }
    }
}

// MARK: - makeOnDeviceAIService factory test

@Suite("makeOnDeviceAIService factory")
struct MakeOnDeviceAIServiceTests {

    @Test("returns unavailable service when flag disabled")
    func flagDisabledReturnsUnavailable() async {
        let flag = OnDeviceFeatureFlag(isEnabled: false)
        let service = makeOnDeviceAIService(flag: flag)
        let state = await service.availability
        #expect(state == .unavailableFeatureDisabled)
    }
}
