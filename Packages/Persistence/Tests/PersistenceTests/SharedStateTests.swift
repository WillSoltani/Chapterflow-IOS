import Foundation
import SwiftData
import Testing
@testable import Persistence

// MARK: - SharedAppStateSnapshot

@Suite("SharedAppStateSnapshot")
struct SharedAppStateSnapshotTests {
    @Test("default initialiser provides safe zero-state")
    func defaultValues() {
        let snapshot = SharedAppStateSnapshot()
        #expect(snapshot.streakDays == 0)
        #expect(snapshot.streakAtRisk == false)
        #expect(snapshot.continueBookId == nil)
        #expect(snapshot.continueBookTitle == nil)
        #expect(snapshot.continueBookCoverEmoji == nil)
        #expect(snapshot.continueBookCoverColor == nil)
        #expect(snapshot.continueChapterNumber == nil)
        #expect(snapshot.continueProgress == nil)
        #expect(snapshot.dueReviewCount == 0)
        #expect(snapshot.dailyGoalMinutes == DailyGoalStore.defaultGoalMinutes)
        #expect(snapshot.goalProgressMinutes == 0)
        #expect(snapshot.lastUpdated == .distantPast)
    }

    @Test("goalFraction is capped at 1.0 when over goal")
    func goalFractionCapped() {
        let snapshot = SharedAppStateSnapshot(dailyGoalMinutes: 10, goalProgressMinutes: 999)
        #expect(snapshot.goalFraction == 1.0)
        #expect(snapshot.isDailyGoalMet == true)
    }

    @Test("goalFraction is accurate at half progress")
    func goalFractionHalf() {
        let snapshot = SharedAppStateSnapshot(dailyGoalMinutes: 20, goalProgressMinutes: 10)
        #expect(abs(snapshot.goalFraction - 0.5) < 0.001)
        #expect(snapshot.isDailyGoalMet == false)
    }

    @Test("goalFraction returns 0 when goal is zero")
    func goalFractionZeroGoal() {
        let snapshot = SharedAppStateSnapshot(dailyGoalMinutes: 0, goalProgressMinutes: 5)
        #expect(snapshot.goalFraction == 0.0)
    }

    @Test("hasContinueReading reflects bookId presence")
    func hasContinueReading() {
        var snapshot = SharedAppStateSnapshot()
        #expect(snapshot.hasContinueReading == false)
        snapshot.continueBookId = "book-1"
        #expect(snapshot.hasContinueReading == true)
    }

    @Test("round-trips through Codable encoding")
    func codableRoundTrip() throws {
        let original = SharedAppStateSnapshot(
            streakDays: 42,
            streakAtRisk: true,
            continueBookId: "book-abc",
            continueBookTitle: "Thinking, Fast and Slow",
            continueBookCoverEmoji: "🧠",
            continueBookCoverColor: "#3A86FF",
            continueChapterNumber: 7,
            continueProgress: 0.65,
            dueReviewCount: 3,
            dailyGoalMinutes: 20,
            goalProgressMinutes: 14,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SharedAppStateSnapshot.self, from: data)
        #expect(decoded == original)
    }

    @Test("decodes with extra unknown fields (server-evolution tolerance)")
    func decodesWithExtraFields() throws {
        let json = """
        {
          "streakDays": 5,
          "streakAtRisk": false,
          "dueReviewCount": 2,
          "dailyGoalMinutes": 20,
          "goalProgressMinutes": 8,
          "lastUpdated": 0,
          "unknownFutureField": "ignored"
        }
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(SharedAppStateSnapshot.self, from: json)
        #expect(snapshot.streakDays == 5)
        #expect(snapshot.dueReviewCount == 2)
    }
}

// MARK: - SharedStateReader

@Suite("SharedStateReader")
struct SharedStateReaderTests {

    private func makeSuite() -> String {
        "com.chapterflow.tests.sharedstate.\(UUID().uuidString)"
    }

    @Test("returns all-defaults snapshot on a fresh store")
    func freshStoreDefaults() {
        let suite = makeSuite()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let reader = SharedStateReader(suiteName: suite)
        let snapshot = reader.load()
        #expect(snapshot.streakDays == 0)
        #expect(snapshot.streakAtRisk == false)
        #expect(snapshot.continueBookId == nil)
        #expect(snapshot.dueReviewCount == 0)
        #expect(snapshot.dailyGoalMinutes == DailyGoalStore.defaultGoalMinutes)
        #expect(snapshot.goalProgressMinutes == 0)
        #expect(snapshot.lastUpdated == .distantPast)
    }

    @Test("reads streak days and atRisk flag")
    func readsStreakFields() {
        let suite = makeSuite()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(14, forKey: SharedStateKeys.streakDays)
        defaults.set(true, forKey: SharedStateKeys.streakAtRisk)
        let snapshot = SharedStateReader(suiteName: suite).load()
        #expect(snapshot.streakDays == 14)
        #expect(snapshot.streakAtRisk == true)
    }

    @Test("reads continue-reading fields")
    func readsContinueReadingFields() {
        let suite = makeSuite()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("book-xyz", forKey: SharedStateKeys.continueBookId)
        defaults.set("Atomic Habits", forKey: SharedStateKeys.continueBookTitle)
        defaults.set("⚛️", forKey: SharedStateKeys.continueBookCoverEmoji)
        defaults.set("#FF6B6B", forKey: SharedStateKeys.continueBookCoverColor)
        defaults.set(3, forKey: SharedStateKeys.continueChapterNumber)
        defaults.set(0.42, forKey: SharedStateKeys.continueProgress)
        let snapshot = SharedStateReader(suiteName: suite).load()
        #expect(snapshot.continueBookId == "book-xyz")
        #expect(snapshot.continueBookTitle == "Atomic Habits")
        #expect(snapshot.continueBookCoverEmoji == "⚛️")
        #expect(snapshot.continueBookCoverColor == "#FF6B6B")
        #expect(snapshot.continueChapterNumber == 3)
        #expect(abs((snapshot.continueProgress ?? 0) - 0.42) < 0.001)
    }

    @Test("reads goal and progress fields")
    func readsGoalFields() {
        let suite = makeSuite()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(20, forKey: SharedStateKeys.dailyGoalMinutes)
        defaults.set(12, forKey: SharedStateKeys.goalProgressMinutes)
        defaults.set(3, forKey: SharedStateKeys.dueReviewCount)
        let snapshot = SharedStateReader(suiteName: suite).load()
        #expect(snapshot.dailyGoalMinutes == 20)
        #expect(snapshot.goalProgressMinutes == 12)
        #expect(snapshot.dueReviewCount == 3)
    }

    @Test("snaps invalid dailyGoalMinutes to default tier")
    func snapInvalidGoalToDefault() {
        let suite = makeSuite()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(99, forKey: SharedStateKeys.dailyGoalMinutes)
        let snapshot = SharedStateReader(suiteName: suite).load()
        #expect(snapshot.dailyGoalMinutes == DailyGoalStore.defaultGoalMinutes)
    }

    @Test("clamps negative streakDays to zero")
    func clampNegativeStreak() {
        let suite = makeSuite()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(-5, forKey: SharedStateKeys.streakDays)
        #expect(SharedStateReader(suiteName: suite).load().streakDays == 0)
    }

    @Test("clamps continueProgress outside 0–1 to valid range")
    func clampProgress() {
        let suite = makeSuite()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(3.5, forKey: SharedStateKeys.continueProgress)
        #expect((SharedStateReader(suiteName: suite).load().continueProgress ?? 0) <= 1.0)

        defaults.set(-0.5, forKey: SharedStateKeys.continueProgress)
        #expect((SharedStateReader(suiteName: suite).load().continueProgress ?? 0) >= 0.0)
    }

    @Test("decodes lastUpdated timestamp correctly")
    func lastUpdatedTimestamp() {
        let suite = makeSuite()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let ts: Double = 1_700_000_000
        defaults.set(ts, forKey: SharedStateKeys.lastUpdated)
        let snapshot = SharedStateReader(suiteName: suite).load()
        #expect(abs(snapshot.lastUpdated.timeIntervalSince1970 - ts) < 0.001)
    }
}

// MARK: - SharedStateWriter

@Suite("SharedStateWriter")
struct SharedStateWriterTests {

    private func makeSuite() -> String {
        "com.chapterflow.tests.writer.\(UUID().uuidString)"
    }

    @Test("publishImmediately writes streak to UserDefaults")
    func writesStreakToUserDefaults() async {
        let suite = makeSuite()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let writer = SharedStateWriter(suiteName: suite, debounceInterval: 0)

        let snapshot = SharedAppStateSnapshot(
            streakDays: 21,
            streakAtRisk: true,
            dueReviewCount: 5,
            dailyGoalMinutes: 30,
            goalProgressMinutes: 18
        )
        await writer.publishImmediately(snapshot)

        #expect(defaults.integer(forKey: SharedStateKeys.streakDays) == 21)
        #expect(defaults.bool(forKey: SharedStateKeys.streakAtRisk) == true)
        #expect(defaults.integer(forKey: SharedStateKeys.dueReviewCount) == 5)
        #expect(defaults.integer(forKey: SharedStateKeys.dailyGoalMinutes) == 30)
        #expect(defaults.integer(forKey: SharedStateKeys.goalProgressMinutes) == 18)
    }

    @Test("publishImmediately writes continue-reading to UserDefaults")
    func writesContinueReadingToUserDefaults() async {
        let suite = makeSuite()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let writer = SharedStateWriter(suiteName: suite, debounceInterval: 0)

        let snapshot = SharedAppStateSnapshot(
            continueBookId: "b-1",
            continueBookTitle: "Deep Work",
            continueBookCoverEmoji: "📚",
            continueBookCoverColor: "#123456",
            continueChapterNumber: 4,
            continueProgress: 0.3
        )
        await writer.publishImmediately(snapshot)

        #expect(defaults.string(forKey: SharedStateKeys.continueBookId) == "b-1")
        #expect(defaults.string(forKey: SharedStateKeys.continueBookTitle) == "Deep Work")
        #expect(defaults.string(forKey: SharedStateKeys.continueBookCoverEmoji) == "📚")
        #expect(defaults.string(forKey: SharedStateKeys.continueBookCoverColor) == "#123456")
        #expect(defaults.integer(forKey: SharedStateKeys.continueChapterNumber) == 4)
        #expect(abs((defaults.object(forKey: SharedStateKeys.continueProgress) as? Double ?? 0) - 0.3) < 0.001)
    }

    @Test("publishImmediately removes continueChapterNumber when nil")
    func removesChapterWhenNil() async {
        let suite = makeSuite()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let writer = SharedStateWriter(suiteName: suite, debounceInterval: 0)

        await writer.publishImmediately(SharedAppStateSnapshot(continueChapterNumber: 5))
        #expect(defaults.object(forKey: SharedStateKeys.continueChapterNumber) != nil)

        await writer.publishImmediately(SharedAppStateSnapshot())
        #expect(defaults.object(forKey: SharedStateKeys.continueChapterNumber) == nil)
    }

    @Test("round-trip: writer → reader returns same snapshot")
    func writerReaderRoundTrip() async {
        let suite = makeSuite()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let writer = SharedStateWriter(suiteName: suite, debounceInterval: 0)
        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        let original = SharedAppStateSnapshot(
            streakDays: 7,
            streakAtRisk: false,
            continueBookId: "bk-99",
            continueBookTitle: "Sapiens",
            continueBookCoverEmoji: "🌍",
            continueBookCoverColor: "#00B4D8",
            continueChapterNumber: 2,
            continueProgress: 0.8,
            dueReviewCount: 1,
            dailyGoalMinutes: 10,
            goalProgressMinutes: 7,
            lastUpdated: ts
        )
        await writer.publishImmediately(original)

        let loaded = SharedStateReader(suiteName: suite).load()
        #expect(loaded.streakDays == original.streakDays)
        #expect(loaded.streakAtRisk == original.streakAtRisk)
        #expect(loaded.continueBookId == original.continueBookId)
        #expect(loaded.continueBookTitle == original.continueBookTitle)
        #expect(loaded.continueBookCoverEmoji == original.continueBookCoverEmoji)
        #expect(loaded.continueBookCoverColor == original.continueBookCoverColor)
        #expect(loaded.continueChapterNumber == original.continueChapterNumber)
        #expect(abs((loaded.continueProgress ?? 0) - 0.8) < 0.001)
        #expect(loaded.dueReviewCount == original.dueReviewCount)
        #expect(loaded.dailyGoalMinutes == original.dailyGoalMinutes)
        #expect(loaded.goalProgressMinutes == original.goalProgressMinutes)
        #expect(abs(loaded.lastUpdated.timeIntervalSince1970 - ts.timeIntervalSince1970) < 0.001)
    }

    @Test("updateGoalState merges into pending snapshot without losing streak")
    func updateGoalStateMerges() async {
        let suite = makeSuite()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let writer = SharedStateWriter(suiteName: suite, debounceInterval: 0)

        await writer.publishImmediately(SharedAppStateSnapshot(streakDays: 30, dueReviewCount: 8, dailyGoalMinutes: 10))
        await writer.updateGoalState(goalMinutes: 20, progressMinutes: 5)

        let loaded = SharedStateReader(suiteName: suite).load()
        #expect(loaded.streakDays == 30)
        #expect(loaded.dueReviewCount == 8)
        #expect(loaded.dailyGoalMinutes == 20)
        #expect(loaded.goalProgressMinutes == 5)
    }

    @Test("updateGoalState snaps invalid goal to nearest tier")
    func updateGoalStateSnaps() async {
        let suite = makeSuite()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let writer = SharedStateWriter(suiteName: suite, debounceInterval: 0)

        await writer.updateGoalState(goalMinutes: 25, progressMinutes: 0)
        #expect(SharedStateReader(suiteName: suite).load().dailyGoalMinutes == 20)
    }

    @Test("publishImmediately writes continue-reading to SwiftData")
    @MainActor
    func writesToSwiftData() async throws {
        let suite = makeSuite()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let writer = SharedStateWriter(suiteName: suite, debounceInterval: 0)
        let container = try AppGroupSnapshotContainer.make(inMemory: true)
        await writer.configure(snapshotContainer: container)

        let snapshot = SharedAppStateSnapshot(
            continueBookId: "sd-book",
            continueBookTitle: "The Lean Startup",
            continueBookCoverEmoji: "🚀",
            continueBookCoverColor: "#FF9F1C",
            continueChapterNumber: 6,
            continueProgress: 0.5,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
        )
        await writer.publishImmediately(snapshot)

        let context = container.mainContext
        let records = try context.fetch(FetchDescriptor<AppGroupContinueRecord>())
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.bookId == "sd-book")
        #expect(record.bookTitle == "The Lean Startup")
        #expect(record.coverEmoji == "🚀")
        #expect(record.chapterNumber == 6)
        #expect(abs(record.progress - 0.5) < 0.001)
    }

    @Test("publishImmediately clears SwiftData record when no continue-reading")
    @MainActor
    func clearsContinueReadingFromSwiftData() async throws {
        let suite = makeSuite()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let writer = SharedStateWriter(suiteName: suite, debounceInterval: 0)
        let container = try AppGroupSnapshotContainer.make(inMemory: true)
        await writer.configure(snapshotContainer: container)

        await writer.publishImmediately(SharedAppStateSnapshot(
            continueBookId: "book-temp", continueBookTitle: "Temp", continueChapterNumber: 1
        ))
        await writer.publishImmediately(SharedAppStateSnapshot())

        let records = try container.mainContext.fetch(FetchDescriptor<AppGroupContinueRecord>())
        #expect(records.isEmpty)
    }

    @Test("upserts the SwiftData record instead of inserting duplicates")
    @MainActor
    func upsertsContinueRecord() async throws {
        let suite = makeSuite()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let writer = SharedStateWriter(suiteName: suite, debounceInterval: 0)
        let container = try AppGroupSnapshotContainer.make(inMemory: true)
        await writer.configure(snapshotContainer: container)

        await writer.publishImmediately(SharedAppStateSnapshot(
            continueBookId: "b1", continueBookTitle: "Book One", continueChapterNumber: 1
        ))
        await writer.publishImmediately(SharedAppStateSnapshot(
            continueBookId: "b2", continueBookTitle: "Book Two", continueChapterNumber: 3
        ))

        let records = try container.mainContext.fetch(FetchDescriptor<AppGroupContinueRecord>())
        #expect(records.count == 1)
        #expect(records.first?.bookId == "b2")
        #expect(records.first?.chapterNumber == 3)
    }
}

// MARK: - AppGroupSnapshotContainer

@Suite("AppGroupSnapshotContainer")
struct AppGroupSnapshotContainerTests {
    @Test("makes an in-memory container that accepts AppGroupContinueRecord")
    @MainActor
    func inMemoryContainerBoots() throws {
        let container = try AppGroupSnapshotContainer.make(inMemory: true)
        let context = container.mainContext
        context.insert(AppGroupContinueRecord(
            bookId: "bk", bookTitle: "Title", coverEmoji: "📖",
            coverColor: "#fff", chapterNumber: 1, progress: 0.0
        ))
        try context.save()

        let records = try context.fetch(FetchDescriptor<AppGroupContinueRecord>())
        #expect(records.count == 1)
    }

    @Test("snapshot store does NOT appear in PersistenceMigrationPlan models")
    func notInMainMigrationPlan() {
        let planTypes = PersistenceSchemaV5.models.map { ObjectIdentifier($0) }
        let snapshotType = ObjectIdentifier(AppGroupContinueRecord.self)
        #expect(!planTypes.contains(snapshotType))
    }
}
