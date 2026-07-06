import Foundation
import SwiftData

#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - UserDefaults keys

/// Shared key namespace used by both ``SharedStateWriter`` and ``SharedStateReader``.
public enum SharedStateKeys {
    public static let streakDays          = "shared.streakDays"
    public static let longestStreak       = "shared.longestStreak"
    public static let streakShieldsHeld   = "shared.streakShieldsHeld"
    public static let streakAtRisk        = "shared.streakAtRisk"
    public static let dueReviewCount      = "shared.dueReviewCount"
    public static let dailyGoalMinutes    = "shared.dailyGoalMinutes"
    public static let goalProgressMinutes = "shared.goalProgressMinutes"
    public static let continueBookId          = "shared.continueBookId"
    public static let continueBookTitle       = "shared.continueBookTitle"
    public static let continueBookCoverEmoji  = "shared.continueBookCoverEmoji"
    public static let continueBookCoverColor  = "shared.continueBookCoverColor"
    public static let continueChapterNumber   = "shared.continueChapterNumber"
    public static let continueProgress        = "shared.continueProgress"
    public static let lastUpdated             = "shared.lastUpdated"
}

// MARK: - SharedStateWriter

/// Publishes compact app-state snapshots to the App Group so widgets, Live
/// Activities, and the watch app can read current state offline.
///
/// ### Storage
/// Every flush writes to two backing stores:
/// 1. **App-Group `UserDefaults`** — fast, synchronous key/value for every primitive field.
/// 2. **App-Group SwiftData snapshot store** — one ``AppGroupContinueRecord`` row
///    for the richer continue-reading context (accessible to widget extensions).
///
/// ### Debouncing
/// ``publish(_:)`` coalesces rapid changes (e.g. streak + goal updating in the same
/// call-site) into a single disk write and a single `WidgetCenter.reloadAllTimelines()`
/// call. The default debounce window is 0.5 seconds. ``publishImmediately(_:)``
/// bypasses it for app-background or scene-resign-active deadlines.
///
/// ### RF4 compliance
/// This actor runs **only** in the main app process and is the sole producer of the
/// App Group snapshot. Extensions read via ``SharedStateReader`` or the SwiftData
/// ``AppGroupSnapshotContainer`` — they never open the main `ChapterFlow.store`.
///
/// ### Configuration
/// Call ``configure(snapshotContainer:)`` once at app startup:
/// ```swift
/// let container = try AppGroupSnapshotContainer.make()
/// await SharedStateWriter.shared.configure(snapshotContainer: container)
/// ```
public actor SharedStateWriter {

    // MARK: Shared instance

    public static let shared = SharedStateWriter()

    // MARK: State

    private let defaults: UserDefaults
    private var snapshotContainer: ModelContainer?
    private let debounceInterval: TimeInterval

    private var pendingSnapshot: SharedAppStateSnapshot = SharedAppStateSnapshot()
    private var debounceTask: Task<Void, Never>?

    // MARK: Init

    /// Creates a writer backed by the given `UserDefaults` suite name.
    ///
    /// - Parameters:
    ///   - suiteName: Override for tests/previews; uses the App Group suite by default.
    ///   - debounceInterval: Seconds to wait before flushing. Default 0.5 s.
    public init(suiteName: String? = nil, debounceInterval: TimeInterval = 0.5) {
        self.defaults = UserDefaults(suiteName: suiteName ?? AppGroup.identifier) ?? .standard
        self.debounceInterval = debounceInterval
    }

    // MARK: - Configuration

    /// Attaches the App Group snapshot `ModelContainer`.
    ///
    /// Call once at app startup before the first `publish` call.
    /// Passing `nil` disables SwiftData writes (UserDefaults still updates).
    public func configure(snapshotContainer: ModelContainer?) {
        self.snapshotContainer = snapshotContainer
    }

    // MARK: - Publish API

    /// Schedules a debounced write of `snapshot` to the App Group stores.
    ///
    /// Rapid successive calls within ``debounceInterval`` are coalesced into a
    /// single flush.
    public func publish(_ snapshot: SharedAppStateSnapshot) {
        pendingSnapshot = snapshot
        scheduleDebouncedFlush()
    }

    /// Updates only the goal and today's reading progress fields, preserving
    /// all other fields from the last-published snapshot, then flushes immediately.
    ///
    /// Call from `DailyGoalModel.setGoal(_:)` when the goal changes without
    /// triggering a full dashboard refresh. Uses an immediate flush (no debounce)
    /// because goal changes are infrequent and must be reflected in widgets at once.
    public func updateGoalState(goalMinutes: Int, progressMinutes: Int) async {
        let snapped = DailyGoalStore.tiers.min(by: { abs($0 - goalMinutes) < abs($1 - goalMinutes) })
            ?? DailyGoalStore.defaultGoalMinutes
        pendingSnapshot.dailyGoalMinutes = snapped
        pendingSnapshot.goalProgressMinutes = max(0, progressMinutes)
        pendingSnapshot.lastUpdated = Date()
        debounceTask?.cancel()
        debounceTask = nil
        await flush()
    }

    /// Bypasses the debounce and writes immediately.
    ///
    /// Use for app-resign-active or background-task deadlines where you must
    /// persist before the process is suspended.
    public func publishImmediately(_ snapshot: SharedAppStateSnapshot) async {
        pendingSnapshot = snapshot
        debounceTask?.cancel()
        debounceTask = nil
        await flush()
    }

    // MARK: - Private

    private func scheduleDebouncedFlush() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(debounceInterval))
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    private func flush() async {
        let snapshot = pendingSnapshot
        writeToUserDefaults(snapshot)
        writeToSwiftData(snapshot)
        triggerWidgetReload()
    }

    // MARK: - UserDefaults write

    private func writeToUserDefaults(_ snapshot: SharedAppStateSnapshot) {
        defaults.set(snapshot.streakDays, forKey: SharedStateKeys.streakDays)
        defaults.set(snapshot.longestStreak, forKey: SharedStateKeys.longestStreak)
        defaults.set(snapshot.streakShieldsHeld, forKey: SharedStateKeys.streakShieldsHeld)
        defaults.set(snapshot.streakAtRisk, forKey: SharedStateKeys.streakAtRisk)
        defaults.set(snapshot.dueReviewCount, forKey: SharedStateKeys.dueReviewCount)
        defaults.set(snapshot.dailyGoalMinutes, forKey: SharedStateKeys.dailyGoalMinutes)
        defaults.set(snapshot.goalProgressMinutes, forKey: SharedStateKeys.goalProgressMinutes)
        defaults.set(snapshot.continueBookId, forKey: SharedStateKeys.continueBookId)
        defaults.set(snapshot.continueBookTitle, forKey: SharedStateKeys.continueBookTitle)
        defaults.set(snapshot.continueBookCoverEmoji, forKey: SharedStateKeys.continueBookCoverEmoji)
        defaults.set(snapshot.continueBookCoverColor, forKey: SharedStateKeys.continueBookCoverColor)
        if let chapter = snapshot.continueChapterNumber {
            defaults.set(chapter, forKey: SharedStateKeys.continueChapterNumber)
        } else {
            defaults.removeObject(forKey: SharedStateKeys.continueChapterNumber)
        }
        if let progress = snapshot.continueProgress {
            defaults.set(progress, forKey: SharedStateKeys.continueProgress)
        } else {
            defaults.removeObject(forKey: SharedStateKeys.continueProgress)
        }
        defaults.set(snapshot.lastUpdated.timeIntervalSince1970, forKey: SharedStateKeys.lastUpdated)
    }

    // MARK: - SwiftData write

    private func writeToSwiftData(_ snapshot: SharedAppStateSnapshot) {
        guard let container = snapshotContainer else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let existing = (try? context.fetch(FetchDescriptor<AppGroupContinueRecord>())) ?? []

        if let bookId = snapshot.continueBookId,
           let title = snapshot.continueBookTitle,
           let chapter = snapshot.continueChapterNumber {
            let progress = snapshot.continueProgress ?? 0.0
            if let record = existing.first {
                record.bookId = bookId
                record.bookTitle = title
                record.coverEmoji = snapshot.continueBookCoverEmoji
                record.coverColor = snapshot.continueBookCoverColor
                record.chapterNumber = chapter
                record.progress = progress
                record.updatedAt = snapshot.lastUpdated
                for extra in existing.dropFirst() { context.delete(extra) }
            } else {
                context.insert(AppGroupContinueRecord(
                    bookId: bookId,
                    bookTitle: title,
                    coverEmoji: snapshot.continueBookCoverEmoji,
                    coverColor: snapshot.continueBookCoverColor,
                    chapterNumber: chapter,
                    progress: progress,
                    updatedAt: snapshot.lastUpdated
                ))
            }
        } else {
            for record in existing { context.delete(record) }
        }

        try? context.save()
    }

    // MARK: - Widget reload

    private func triggerWidgetReload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
