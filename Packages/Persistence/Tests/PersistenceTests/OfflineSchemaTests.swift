// swiftlint:disable file_length
import Foundation
import SwiftData
import Testing
import Models
@testable import Persistence

// MARK: - Shared in-memory container
//
// Creating multiple ModelContainers with the same schema in a single test
// process triggers a CoreData entity-description re-registration crash on
// macOS 26 (Darwin 25).  One container is created at module load time and
// reused for every container-bearing test.  The .serialized trait on
// OfflineSchemaTests guarantees tests run serially, so the shared store is
// never accessed by two tests simultaneously.
// swiftlint:disable:next force_try
private let sharedV7Container: ModelContainer = try! {
    let schema = Schema(PersistenceSchemaV7.models)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: config)
}()

// MARK: - Offline Schema Tests

// All container-bearing tests live inside this single .serialized suite so
// they never run concurrently with each other.
@Suite("OfflineSchema", .serialized)
struct OfflineSchemaTests {

    /// Returns the shared main context with all offline tables wiped.
    @MainActor
    private func freshContext() throws -> ModelContext {
        let ctx = sharedV7Container.mainContext
        try ctx.delete(model: CachedBook.self)
        try ctx.delete(model: CachedChapter.self)
        try ctx.delete(model: CachedManifest.self)
        try ctx.delete(model: CachedProgress.self)
        try ctx.delete(model: CachedBookState.self)
        try ctx.delete(model: CachedQuizState.self)
        try ctx.delete(model: CachedNotebookEntry.self)
        try ctx.delete(model: CachedHighlight.self)
        try ctx.delete(model: CachedReviewCard.self)
        try ctx.delete(model: PendingMutation.self)
        try ctx.delete(model: CachedKeyValue.self)
        try ctx.delete(model: LocalAnnotation.self)
        try ctx.delete(model: PendingAnnotationUpload.self)
        try ctx.delete(model: PendingReviewGrade.self)
        try ctx.delete(model: PendingCommitmentUpload.self)
        try ctx.delete(model: PendingScenarioUpload.self)
        try ctx.delete(model: CachedBookDownload.self)
        try ctx.delete(model: CachedDownloadedSegment.self)
        try ctx.save()
        return ctx
    }

    // MARK: - Pre-existing controller tests

    @Suite("PersistenceController")
    struct PersistenceControllerTests {
        @MainActor
        @Test("boots an in-memory container with the sample @Model and round-trips a record")
        func containerBoots() throws {
            let context = try OfflineSchemaTests().freshContext()
            context.insert(CachedKeyValue(key: "greeting", value: "hello"))
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<CachedKeyValue>())
            #expect(fetched.count == 1)
            #expect(fetched.first?.value == "hello")
        }

        @Test("background store inserts and counts off the main actor")
        func backgroundStore() async throws {
            let background = BackgroundStore(modelContainer: sharedV7Container)
            try await background.insert(CachedKeyValue(key: "k", value: "v"))
            let count = try await background.count(CachedKeyValue.self)
            #expect(count >= 1)
        }

        @MainActor
        @Test("LocalAnnotation round-trips in-memory")
        func localAnnotationRoundTrip() throws {
            let context = try OfflineSchemaTests().freshContext()
            let ann = LocalAnnotation(
                bookId: "book-1",
                chapterId: "ch-1",
                type: "highlight",
                colorRaw: "yellow",
                snippet: "Hello"
            )
            context.insert(ann)
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<LocalAnnotation>())
            #expect(fetched.count == 1)
            #expect(fetched.first?.type == "highlight")
            #expect(fetched.first?.colorRaw == "yellow")
        }

        @MainActor
        @Test("PendingReviewGrade round-trips in-memory")
        func pendingReviewGradeRoundTrip() throws {
            let context = try OfflineSchemaTests().freshContext()
            let grade = PendingReviewGrade(
                cardId: "card-1",
                rating: 3,
                reviewedAt: "2026-01-01T00:00:00Z",
                optimisticStability: 5.0,
                optimisticDifficulty: 4.5,
                optimisticDueAt: "2026-01-04T00:00:00Z"
            )
            context.insert(grade)
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<PendingReviewGrade>())
            #expect(fetched.count == 1)
            #expect(fetched.first?.cardId == "card-1")
            #expect(fetched.first?.rating == 3)
        }
    }

    // MARK: - CachedBook

    @Suite("CachedBook")
    struct CachedBookTests {
        @MainActor
        @Test("round-trips BookCatalogItem losslessly")
        func roundTrip() throws {
            let context = try OfflineSchemaTests().freshContext()
            context.insert(try CachedBook.from(sampleBook, userId: "user-1"))
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<CachedBook>())
            #expect(fetched.count == 1)
            let domain = try fetched[0].toDomain()
            #expect(domain.bookId == sampleBook.bookId)
            #expect(domain.title == sampleBook.title)
            #expect(domain.author == sampleBook.author)
            #expect(domain.variantFamily == sampleBook.variantFamily)
            #expect(domain.categories == sampleBook.categories)
            #expect(domain.latestVersion == sampleBook.latestVersion)
        }

        @Test("userId partition and rowId are stored correctly")
        func userPartition() throws {
            let row = try CachedBook.from(sampleBook, userId: "user-xyz")
            #expect(row.userId == "user-xyz")
            #expect(row.bookId == sampleBook.bookId)
            #expect(row.rowId == "user-xyz:\(sampleBook.bookId)")
        }
    }

    // MARK: - CachedChapter

    @Suite("CachedChapter")
    struct CachedChapterTests {
        @MainActor
        @Test("round-trips Chapter losslessly including all contentVariants")
        func roundTrip() throws {
            let context = try OfflineSchemaTests().freshContext()
            let row = try CachedChapter.from(sampleChapter, userId: "user-1", bookId: "book-1")
            context.insert(row)
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<CachedChapter>())
            #expect(fetched.count == 1)
            #expect(fetched[0].number == 1)
            #expect(fetched[0].bookId == "book-1")
            let domain = try fetched[0].toDomain()
            #expect(domain.chapterId == sampleChapter.chapterId)
            #expect(domain.number == sampleChapter.number)
            #expect(domain.title == sampleChapter.title)
            #expect(domain.activeVariant == sampleChapter.activeVariant)
            #expect(domain.availableVariants == sampleChapter.availableVariants)
            #expect(domain.contentVariants.keys.sorted() == sampleChapter.contentVariants.keys.sorted())
        }
    }

    // MARK: - CachedManifest

    @Suite("CachedManifest")
    struct CachedManifestTests {
        @MainActor
        @Test("round-trips BookManifest losslessly")
        func roundTrip() throws {
            let context = try OfflineSchemaTests().freshContext()
            context.insert(try CachedManifest.from(sampleManifest, userId: "user-1"))
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<CachedManifest>())
            #expect(fetched.count == 1)
            let domain = try fetched[0].toDomain()
            #expect(domain.bookId == sampleManifest.bookId)
            #expect(domain.chapters.count == sampleManifest.chapters.count)
            #expect(domain.chapters[0].chapterId == "ch-1")
            #expect(domain.totalReadingTimeMinutes == 210)
            #expect(domain.chapterCount == 14)
        }
    }

    // MARK: - CachedProgress

    @Suite("CachedProgress")
    struct CachedProgressTests {
        @MainActor
        @Test("round-trips BookProgress losslessly including server-owned gating fields")
        func roundTrip() throws {
            let context = try OfflineSchemaTests().freshContext()
            context.insert(
                try CachedProgress.from(sampleProgress, userId: "user-1", bookId: "book-1")
            )
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<CachedProgress>())
            #expect(fetched.count == 1)
            let domain = try fetched[0].toDomain()
            #expect(domain.currentChapterNumber == 3)
            #expect(domain.unlockedThroughChapterNumber == 3)
            #expect(domain.completedChapters == [1, 2])
            #expect(domain.bestScoreByChapter == ["1": 90, "2": 85])
            #expect(domain.preferredVariant == .medium)
            #expect(domain.progressRev == 7)
        }
    }

    // MARK: - CachedBookState

    @Suite("CachedBookState")
    struct CachedBookStateTests {
        @MainActor
        @Test("round-trips BookStateResponse losslessly")
        func roundTrip() throws {
            let context = try OfflineSchemaTests().freshContext()
            context.insert(
                try CachedBookState.from(sampleBookState, userId: "user-1", bookId: "book-1")
            )
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<CachedBookState>())
            #expect(fetched.count == 1)
            let domain = try fetched[0].toDomain()
            #expect(domain.state.currentChapterId == "ch-3")
            #expect(domain.state.completedChapterIds == ["ch-1", "ch-2"])
            #expect(domain.applicationStates?["ch-1"] == .committed)
            #expect(domain.applicationStates?["ch-2"] == .applied)
        }
    }

    // MARK: - CachedQuizState

    @Suite("CachedQuizState")
    struct CachedQuizStateTests {
        @Test("current quiz session decodes attempt identity and tolerant status")
        func currentSessionAttemptIdentity() throws {
            let data = Data(#"{"attemptNumber":3,"nextAttemptNumber":3,"status":"future_state","questions":[{"questionId":"q-1","prompt":"Prompt","choices":[{"choiceId":"c-1","text":"One"}]}]}"#.utf8)
            let session = try JSONDecoder().decode(QuizClientSession.self, from: data)

            #expect(session.attemptNumber == 3)
            #expect(session.nextAttemptNumber == 3)
            #expect(session.status == .unknown("future_state"))
        }

        @Test("missing attempt number remains displayable without an inferred default")
        func missingAttemptNumberIsTolerated() throws {
            let data = Data(#"{"status":"ready","questions":[{"questionId":"q-1","prompt":"Prompt","choices":[{"choiceId":"c-1","text":"One"}]}]}"#.utf8)
            let session = try JSONDecoder().decode(QuizClientSession.self, from: data)

            #expect(session.attemptNumber == nil)
            #expect(session.questions.count == 1)
        }

        @MainActor
        @Test("round-trips QuizClientSession losslessly with .ready status")
        func roundTripReady() throws {
            let context = try OfflineSchemaTests().freshContext()
            context.insert(
                try CachedQuizState.from(sampleQuiz, userId: "user-1", bookId: "book-1", chapterNumber: 3)
            )
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<CachedQuizState>())
            #expect(fetched.count == 1)
            let row = fetched[0]
            #expect(row.status == .ready)
            #expect(row.sessionId == "session-42")
            let domain = try row.toDomain()
            #expect(domain.sessionId == sampleQuiz.sessionId)
            #expect(domain.questions.count == 1)
            #expect(domain.questions[0].questionId == "q-1")
            #expect(domain.passingScorePercent == 70)
            #expect(domain.tone == .direct)
        }

        @Test("legacy bare-session cache decodes with an empty draft")
        func legacyBareSession() throws {
            let data = try JSONEncoder().encode(sampleQuiz)
            let json = try #require(String(bytes: data, encoding: .utf8))
            let row = CachedQuizState(
                rowId: "u:b:1",
                userId: "u",
                bookId: "b",
                chapterNumber: 1,
                sessionId: sampleQuiz.sessionId,
                dataJSON: json
            )

            let document = try row.toDocument()
            #expect(document.version == CachedQuizDocument.currentVersion)
            #expect(document.session.sessionId == sampleQuiz.sessionId)
            #expect(document.selectedAnswers.isEmpty)
        }

        @Test("versioned draft round-trips selected answers")
        func versionedDraftRoundTrip() throws {
            let session = currentSession()
            let row = try CachedQuizState.from(
                session,
                userId: "u",
                bookId: "b",
                chapterNumber: 1,
                selectedAnswers: ["q-1": "c-2"],
                status: .draftPendingOnline
            )

            let document = try row.toDocument()
            #expect(document.version == 1)
            #expect(document.session.attemptNumber == 2)
            #expect(document.selectedAnswers == ["q-1": "c-2"])
            #expect(row.status == .draftPendingOnline)
        }

        @Test("malformed document fails without manufacturing a session")
        func malformedDocumentFailsSafely() {
            let row = CachedQuizState(
                rowId: "u:b:1",
                userId: "u",
                bookId: "b",
                chapterNumber: 1,
                dataJSON: #"{"version":1,"session":"not-a-session"}"#
            )

            #expect(throws: (any Error).self) {
                try row.toDocument()
            }
        }

        @Test("different attempt or question assignment never restores answers")
        func mismatchedSessionDoesNotRestoreAnswers() throws {
            let document = try CachedQuizDocument(
                session: currentSession(),
                selectedAnswers: ["q-1": "c-1"]
            )
            let nextAttempt = currentSession(attemptNumber: 3)
            let changedQuestions = currentSession(questionID: "q-new")

            #expect(document.answers(matching: nextAttempt).isEmpty)
            #expect(document.answers(matching: changedQuestions).isEmpty)
        }

        @Test("invalid question and choice IDs cannot enter a draft")
        func invalidSelectionsAreRejected() {
            #expect(throws: CachedQuizDocumentError.self) {
                try CachedQuizDocument(
                    session: currentSession(),
                    selectedAnswers: ["q-1": "not-a-choice"]
                )
            }
        }

        @Test("pendingGrading status stored and retrieved correctly")
        func pendingGradingStatus() throws {
            let row = try CachedQuizState.from(
                sampleQuiz, userId: "u", bookId: "b", chapterNumber: 1, status: .pendingGrading
            )
            #expect(row.status == .pendingGrading)
            #expect(row.statusRaw == QuizCacheStatus.pendingGrading.rawValue)
        }

        private func currentSession(
            attemptNumber: Int = 2,
            questionID: String = "q-1"
        ) -> QuizClientSession {
            QuizClientSession(
                sessionId: nil,
                attemptNumber: attemptNumber,
                nextAttemptNumber: attemptNumber,
                status: .ready,
                questions: [
                    QuizQuestion(
                        questionId: questionID,
                        prompt: "Prompt",
                        choices: [
                            QuizChoice(choiceId: "c-1", text: "One"),
                            QuizChoice(choiceId: "c-2", text: "Two"),
                        ]
                    ),
                ],
                passingScorePercent: 70,
                bookId: "b",
                chapterNumber: 1,
                tone: .direct
            )
        }
    }

    // MARK: - CachedNotebookEntry

    @Suite("CachedNotebookEntry")
    struct CachedNotebookEntryTests {
        @MainActor
        @Test("round-trips NotebookEntry losslessly")
        func roundTrip() throws {
            let context = try OfflineSchemaTests().freshContext()
            context.insert(try CachedNotebookEntry.from(sampleNotebookEntry, userId: "user-1"))
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<CachedNotebookEntry>())
            #expect(fetched.count == 1)
            #expect(fetched[0].typeRaw == "note")
            #expect(fetched[0].bookId == "book-1")
            let domain = try fetched[0].toDomain()
            #expect(domain.entryId == sampleNotebookEntry.entryId)
            #expect(domain.type == .note)
            #expect(domain.content == sampleNotebookEntry.content)
            #expect(domain.chapterId == "ch-2")
            #expect(domain.createdAt == sampleNotebookEntry.createdAt)
        }

        @Test("typeRaw column extracted from domain type for query efficiency")
        func typeRawExtracted() throws {
            let row = try CachedNotebookEntry.from(sampleNotebookEntry, userId: "u")
            #expect(row.typeRaw == NotebookEntryType.note.rawValue)
        }
    }

    // MARK: - CachedHighlight

    @Suite("CachedHighlight")
    struct CachedHighlightTests {
        @MainActor
        @Test("round-trips NotebookEntry (highlight type) losslessly")
        func roundTrip() throws {
            let context = try OfflineSchemaTests().freshContext()
            let row = try CachedHighlight.from(sampleHighlightEntry, userId: "user-1")
            row.colorRaw = "yellow"
            row.anchorJSON = "{\"start\":0,\"end\":50}"
            context.insert(row)
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<CachedHighlight>())
            #expect(fetched.count == 1)
            let highlight = fetched[0]
            #expect(highlight.colorRaw == "yellow")
            #expect(highlight.anchorJSON == "{\"start\":0,\"end\":50}")
            let domain = try highlight.toDomain()
            #expect(domain.entryId == sampleHighlightEntry.entryId)
            #expect(domain.type == .highlight)
            #expect(domain.quote == sampleHighlightEntry.quote)
        }

        @Test("reader-only fields default to nil from domain model")
        func readerFieldsDefaultNil() throws {
            let row = try CachedHighlight.from(sampleHighlightEntry, userId: "u")
            #expect(row.colorRaw == nil)
            #expect(row.anchorJSON == nil)
        }
    }

    // MARK: - CachedReviewCard

    @Suite("CachedReviewCard")
    struct CachedReviewCardTests {
        @MainActor
        @Test("round-trips FsrsCard losslessly including dueAt index column")
        func roundTrip() throws {
            let context = try OfflineSchemaTests().freshContext()
            context.insert(try CachedReviewCard.from(sampleFsrsCard, userId: "user-1"))
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<CachedReviewCard>())
            #expect(fetched.count == 1)
            let row = fetched[0]
            #expect(row.dueAt != nil)
            #expect(row.stateRaw == FsrsCardState.due.rawValue)
            let domain = try row.toDomain()
            #expect(domain.cardId == sampleFsrsCard.cardId)
            #expect(domain.front == sampleFsrsCard.front)
            #expect(domain.back == sampleFsrsCard.back)
            #expect(domain.dueAt == sampleFsrsCard.dueAt)
            #expect(domain.stability == sampleFsrsCard.stability)
            #expect(domain.difficulty == sampleFsrsCard.difficulty)
            #expect(domain.state == .due)
        }

        @Test("dueAt column is parsed from ISO string for index use")
        func dueAtParsed() throws {
            let row = try CachedReviewCard.from(sampleFsrsCard, userId: "u")
            #expect(row.dueAt != nil)
        }

        @Test("nil dueAt in domain model is handled gracefully")
        func nilDueAt() throws {
            let json = """
            {"cardId":"c-2","bookId":"b-1","front":"Q","back":"A","state":"new"}
            """
            let cardNoDue = try JSONDecoder.chapterFlow.decode(
                FsrsCard.self, from: Data(json.utf8)
            )
            let row = try CachedReviewCard.from(cardNoDue, userId: "u")
            #expect(row.dueAt == nil)
            let domain = try row.toDomain()
            #expect(domain.dueAt == nil)
            #expect(domain.state == .new)
        }
    }

    // MARK: - PendingMutation

    @Suite("PendingMutation")
    struct PendingMutationTests {
        private struct ProgressPayload: Codable, Equatable {
            var bookId: String
            var chapterNumber: Int
        }

        @MainActor
        @Test("round-trips all 8 mutation kinds via payloadJSON losslessly")
        func allKindsRoundTrip() throws {
            let context = try OfflineSchemaTests().freshContext()
            let payload = ProgressPayload(bookId: "book-1", chapterNumber: 3)

            for kind in MutationKind.allCases {
                let mutation = try PendingMutation.make(userId: "user-1", kind: kind, payload: payload)
                context.insert(mutation)
            }
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<PendingMutation>())
            #expect(fetched.count == MutationKind.allCases.count)
            let kinds = Set(fetched.compactMap { $0.kind })
            #expect(kinds == Set(MutationKind.allCases))

            for mutation in fetched {
                let decoded = try mutation.decodePayload(as: ProgressPayload.self)
                #expect(decoded == payload)
            }
        }

        @Test("default status is pending with zero attemptCount")
        func defaultStatus() {
            let mutation = PendingMutation(
                mutationId: "test-id",
                userId: "u",
                kindRaw: MutationKind.progressCursor.rawValue,
                payloadJSON: "{}"
            )
            #expect(mutation.status == .pending)
            #expect(mutation.attemptCount == 0)
            #expect(mutation.lastError == nil)
        }

        @Test("complex payload round-trips losslessly")
        func payloadRoundTrip() throws {
            struct Payload: Codable, Equatable {
                var sessionId: String
                var answers: [String: String]
            }
            let original = Payload(sessionId: "s-1", answers: ["q-1": "c-1a", "q-2": "c-2b"])
            let mutation = try PendingMutation.make(userId: "u", kind: .quizSubmit, payload: original)
            let decoded = try mutation.decodePayload(as: Payload.self)
            #expect(decoded == original)
        }

        @MainActor
        @Test("inflight status persists correctly")
        func inflightStatus() throws {
            let context = try OfflineSchemaTests().freshContext()
            let mutation = PendingMutation(
                mutationId: UUID().uuidString,
                userId: "u",
                kindRaw: MutationKind.reviewGrade.rawValue,
                payloadJSON: "{}",
                statusRaw: MutationStatus.inflight.rawValue
            )
            context.insert(mutation)
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<PendingMutation>())
            #expect(fetched.first?.status == .inflight)
        }

        @MainActor
        @Test("quarantined status round-trips through the existing raw field")
        func quarantinedStatus() throws {
            let context = try OfflineSchemaTests().freshContext()
            let originalPayload = "{\"opaque\":\"unchanged\"}"
            context.insert(PendingMutation(
                mutationId: "quarantined-row",
                userId: "u",
                kindRaw: "future-kind",
                payloadJSON: originalPayload,
                lastError: "sync.quarantine.unknown_kind",
                statusRaw: MutationStatus.quarantined.rawValue
            ))
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<PendingMutation>())
            let mutation = try #require(fetched.first)
            #expect(mutation.status == .quarantined)
            #expect(mutation.statusRaw == MutationStatus.quarantined.rawValue)
            #expect(mutation.payloadJSON == originalPayload)
        }
    }

    // MARK: - UserDataWipe

    @Suite("UserDataWipe")
    struct UserDataWipeTests {
        @MainActor
        @Test("wipes only the signed-out user's rows; other users' rows survive")
        func wipesOnlyTargetUser() throws {
            let context = try OfflineSchemaTests().freshContext()

            // Two users each get a CachedBook, CachedManifest, and PendingMutation.
            context.insert(try CachedBook.from(sampleBook, userId: "user-A"))
            context.insert(try CachedBook.from(sampleBook, userId: "user-B"))
            context.insert(try CachedManifest.from(sampleManifest, userId: "user-A"))
            context.insert(try CachedManifest.from(sampleManifest, userId: "user-B"))
            context.insert(
                PendingMutation(
                    mutationId: UUID().uuidString,
                    userId: "user-A",
                    kindRaw: MutationKind.progressCursor.rawValue,
                    payloadJSON: "{}"
                )
            )
            context.insert(
                PendingMutation(
                    mutationId: UUID().uuidString,
                    userId: "user-B",
                    kindRaw: MutationKind.progressCursor.rawValue,
                    payloadJSON: "{}"
                )
            )
            try context.save()

            try UserDataWipe.wipe(userId: "user-A", context: context)

            let booksA = try context.fetch(
                FetchDescriptor<CachedBook>(predicate: #Predicate { $0.userId == "user-A" })
            )
            #expect(booksA.isEmpty)
            let mutationsA = try context.fetch(
                FetchDescriptor<PendingMutation>(predicate: #Predicate { $0.userId == "user-A" })
            )
            #expect(mutationsA.isEmpty)

            let booksB = try context.fetch(
                FetchDescriptor<CachedBook>(predicate: #Predicate { $0.userId == "user-B" })
            )
            #expect(booksB.count == 1)
            let mutationsB = try context.fetch(
                FetchDescriptor<PendingMutation>(predicate: #Predicate { $0.userId == "user-B" })
            )
            #expect(mutationsB.count == 1)
        }
    }

    // MARK: - V7 schema boot

    @Suite("PersistenceSchemaV7")
    struct PersistenceSchemaV7Tests {
        @MainActor
        @Test("V7 container boots with all 12 offline @Model types including download tracking")
        func containerBoots() throws {
            let context = try OfflineSchemaTests().freshContext()

            context.insert(try CachedBook.from(sampleBook, userId: "u"))
            context.insert(try CachedChapter.from(sampleChapter, userId: "u", bookId: "book-1"))
            context.insert(try CachedManifest.from(sampleManifest, userId: "u"))
            context.insert(try CachedProgress.from(sampleProgress, userId: "u", bookId: "book-1"))
            context.insert(try CachedBookState.from(sampleBookState, userId: "u", bookId: "book-1"))
            context.insert(
                try CachedQuizState.from(sampleQuiz, userId: "u", bookId: "book-1", chapterNumber: 3)
            )
            context.insert(try CachedNotebookEntry.from(sampleNotebookEntry, userId: "u"))
            context.insert(try CachedHighlight.from(sampleHighlightEntry, userId: "u"))
            context.insert(try CachedReviewCard.from(sampleFsrsCard, userId: "u"))
            context.insert(
                PendingMutation(
                    mutationId: UUID().uuidString,
                    userId: "u",
                    kindRaw: MutationKind.readingSession.rawValue,
                    payloadJSON: "{\"minutes\":15}"
                )
            )
            context.insert(CachedBookDownload(
                rowId: CachedBookDownload.makeRowId(userId: "u", bookId: "book-1"),
                userId: "u",
                bookId: "book-1",
                title: "Test Book"
            ))
            context.insert(CachedDownloadedSegment(
                segmentId: "seg-1",
                bookId: "book-1",
                chapterNumber: 1,
                userId: "u",
                fileSize: 1024
            ))
            try context.save()

            #expect(try context.fetchCount(FetchDescriptor<CachedBook>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CachedChapter>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CachedManifest>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CachedProgress>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CachedBookState>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CachedQuizState>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CachedNotebookEntry>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CachedHighlight>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CachedReviewCard>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<PendingMutation>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CachedBookDownload>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CachedDownloadedSegment>()) == 1)
        }
    }

    // MARK: - CachedBookDownload

    @Suite("CachedBookDownload")
    struct CachedBookDownloadTests {
        @MainActor
        @Test("round-trips all fields")
        func roundTrip() throws {
            let context = try OfflineSchemaTests().freshContext()
            let rowId = CachedBookDownload.makeRowId(userId: "u", bookId: "b-1")
            let record = CachedBookDownload(
                rowId: rowId, userId: "u", bookId: "b-1", title: "My Book"
            )
            record.chapterCount = 5
            record.downloadedChapterCount = 3
            record.audioSegmentCount = 10
            record.downloadedAudioSegmentCount = 7
            record.totalBytes = 5_000_000
            record.status = .downloading
            context.insert(record)
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<CachedBookDownload>())
            #expect(fetched.count == 1)
            #expect(fetched[0].rowId == rowId)
            #expect(fetched[0].bookId == "b-1")
            #expect(fetched[0].title == "My Book")
            #expect(fetched[0].status == .downloading)
            #expect(fetched[0].chapterCount == 5)
            #expect(fetched[0].downloadedChapterCount == 3)
            #expect(fetched[0].totalBytes == 5_000_000)
        }

        @Test("fractionCompleted reflects chapter + audio progress")
        func fractionCompleted() {
            let record = CachedBookDownload(
                rowId: "u:b", userId: "u", bookId: "b", title: "T"
            )
            record.chapterCount = 4
            record.downloadedChapterCount = 2
            record.audioSegmentCount = 4
            record.downloadedAudioSegmentCount = 2
            #expect(record.fractionCompleted == 0.5)
        }

        @Test("status defaults to downloading on init")
        func defaultStatus() {
            let record = CachedBookDownload(
                rowId: "u:b", userId: "u", bookId: "b", title: "T"
            )
            #expect(record.status == .downloading)
        }
    }

    // MARK: - CachedDownloadedSegment

    @Suite("CachedDownloadedSegment")
    struct CachedDownloadedSegmentTests {
        @MainActor
        @Test("round-trips segmentId, bookId, chapterNumber, userId, fileSize")
        func roundTrip() throws {
            let context = try OfflineSchemaTests().freshContext()
            context.insert(CachedDownloadedSegment(
                segmentId: "seg-abc",
                bookId: "book-1",
                chapterNumber: 3,
                userId: "user-1",
                fileSize: 512_000
            ))
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<CachedDownloadedSegment>())
            #expect(fetched.count == 1)
            #expect(fetched[0].segmentId == "seg-abc")
            #expect(fetched[0].bookId == "book-1")
            #expect(fetched[0].chapterNumber == 3)
            #expect(fetched[0].userId == "user-1")
            #expect(fetched[0].fileSize == 512_000)
        }

        @Test("fileStoreKey prefixes with audio_")
        func fileStoreKey() {
            let key = CachedDownloadedSegment.fileStoreKey(segmentId: "seg-xyz")
            #expect(key == "audio_seg-xyz")
        }
    }

    // MARK: - Migration plan counts

    @Suite("MigrationPlan")
    struct MigrationPlanTests {
        @Test("plan contains 8 schemas and 7 migration stages")
        func schemaAndStageCounts() {
            #expect(PersistenceMigrationPlan.schemas.count == 8)
            #expect(PersistenceMigrationPlan.stages.count == 7)
        }

        @Test("final schema version identifier is 8.0.0")
        func finalVersionId() {
            #expect(PersistenceSchemaV8.versionIdentifier == Schema.Version(8, 0, 0))
        }
    }
}
