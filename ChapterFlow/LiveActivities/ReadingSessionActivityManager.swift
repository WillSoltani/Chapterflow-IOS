@preconcurrency import ActivityKit
import Foundation

// MARK: - ReadingSessionActivityManager
//
// App-target only. Manages the lifecycle of the reading-session Live Activity.
// Call `startSession(...)` when a reading or audio session begins; call
// `update(...)` on progress changes; call `endSession()` when done.
//
// `@MainActor` is required because ActivityAttributes conformances are
// main-actor-isolated in ActivityKit's Swift 6 API surface.

@available(iOS 16.1, *)
@MainActor
final class ReadingSessionActivityManager {

    // MARK: - Singleton

    static let shared = ReadingSessionActivityManager()
    private init() {}

    // MARK: - State

    private var currentActivity: Activity<ReadingSessionAttributes>?

    // MARK: - Session request type

    struct SessionRequest: Sendable {
        let bookTitle: String
        let bookEmoji: String
        let bookColor: String
        let chapterNumber: Int
        let chapterTitle: String
        let sessionKind: ReadingSessionAttributes.SessionKind
        let streakAtRisk: Bool
    }

    // MARK: - Session start

    /// Starts a Live Activity for a reading or audio session.
    func startSession(_ request: SessionRequest) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any stale activity first.
        Task { await self.endSession() }

        let attributes = ReadingSessionAttributes(
            bookTitle: request.bookTitle,
            bookEmoji: request.bookEmoji,
            bookColor: request.bookColor,
            chapterNumber: request.chapterNumber,
            chapterTitle: request.chapterTitle,
            sessionKind: request.sessionKind
        )
        let initialState = ReadingSessionStatus(
            elapsedSeconds: 0,
            chapterProgress: 0,
            isPlaying: request.sessionKind == .audio,
            streakAtRisk: request.streakAtRisk
        )
        let content = ActivityContent(
            state: initialState,
            staleDate: Calendar.current.date(byAdding: .hour, value: 4, to: Date()),
            relevanceScore: 100
        )
        do {
            currentActivity = try Activity<ReadingSessionAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            // Live Activities require a real device — swallow errors silently on unsupported sims.
        }
    }

    // MARK: - Progress update

    /// Updates the Live Activity with the latest session state.
    func update(
        elapsedSeconds: Int,
        chapterProgress: Double,
        isPlaying: Bool,
        streakAtRisk: Bool
    ) async {
        guard let activity = currentActivity else { return }
        let state = ReadingSessionStatus(
            elapsedSeconds: elapsedSeconds,
            chapterProgress: chapterProgress,
            isPlaying: isPlaying,
            streakAtRisk: streakAtRisk
        )
        let content = ActivityContent(
            state: state,
            staleDate: Calendar.current.date(byAdding: .minute, value: 5, to: Date()),
            relevanceScore: 100
        )
        await activity.update(content)
    }

    // MARK: - Session end

    /// Ends and dismisses the Live Activity.
    func endSession() async {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        let finalState = activity.contentState
        let finalContent = ActivityContent(state: finalState, staleDate: Date())
        await activity.end(finalContent, dismissalPolicy: .after(Date().addingTimeInterval(5)))
    }
}

// MARK: - StreakAtRiskActivityManager

@available(iOS 16.1, *)
@MainActor
final class StreakAtRiskActivityManager {

    // MARK: - Singleton

    static let shared = StreakAtRiskActivityManager()
    private init() {}

    private var currentActivity: Activity<StreakAtRiskAttributes>?

    // MARK: - Start

    /// Shows the streak-at-risk countdown in the evening when the streak is at risk.
    func startIfNeeded(streakDays: Int, midnightDeadline: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard currentActivity == nil else { return }

        let attributes = StreakAtRiskAttributes(streakDays: streakDays)
        let state = StreakAtRiskStatus(midnightDeadline: midnightDeadline)
        let content = ActivityContent(
            state: state,
            staleDate: midnightDeadline,
            relevanceScore: 50
        )
        do {
            currentActivity = try Activity<StreakAtRiskAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            // Silently swallow if activities not available.
        }
    }

    // MARK: - Dismiss (streak saved)

    /// Dismisses the activity after the user reads and saves their streak.
    func markStreakSaved() async {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        var saved = activity.contentState
        saved.isStreakSaved = true
        let content = ActivityContent(state: saved, staleDate: Date())
        await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(3)))
    }

    // MARK: - Auto-dismiss at midnight

    /// Ends the activity (streak lost / midnight passed).
    func dismissAtMidnight() async {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        await activity.end(
            ActivityContent(state: activity.contentState, staleDate: Date()),
            dismissalPolicy: .immediate
        )
    }
}
