import SwiftUI
import Persistence
import Networking
import UserNotifications
import CoreKit

// MARK: - OnboardingModel

/// The view model that drives the first-run onboarding flow.
///
/// Responsibilities:
/// - Load existing server progress on startup (enables resume after interruption).
/// - Track the current step and the user's accumulated selections.
/// - Persist each step's choices to the server, to `AppPreferences`, and to `DailyGoalStore`.
/// - Advance through steps, completing or skipping the flow.
@Observable
@MainActor
public final class OnboardingModel {

    // MARK: Flow state

    /// The step currently displayed to the user.
    /// Internal setter allows tests (via `@testable import`) to seed a specific step.
    public internal(set) var currentStep: OnboardingStep = .welcome

    /// `true` while a server request is in flight.
    public private(set) var isLoading: Bool = false

    // MARK: User selections

    /// Interest categories the user has toggled on (step 2).
    public var selectedInterestIds: Set<String> = []

    /// Chapter-reading order (step 3).
    public var chapterOrder: ChapterOrder = .summaryFirst

    /// Teaching tone for default reader sessions (step 3).
    public var readingTone: ReadingTone = .direct

    /// Number of minutes the user wants to read per day (step 4).
    /// Always one of 10 | 20 | 30.
    public var dailyGoalMinutes: Int = DailyGoalStore.defaultGoalMinutes

    /// Hour component of the daily reminder time, 0–23 (step 4).
    public var reminderHour: Int = 20

    /// Minute component of the daily reminder time, 0–59 (step 4).
    public var reminderMinute: Int = 0

    // MARK: Dependencies

    @ObservationIgnored private let repository: any OnboardingRepository
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let goalStore: DailyGoalStore
    @ObservationIgnored private let workPermit: SessionWorkPermit
    @ObservationIgnored private let analytics: any AnalyticsClient

    // MARK: Init

    public init(
        preferences: AppPreferences,
        repository: any OnboardingRepository,
        goalStore: DailyGoalStore,
        workPermit: SessionWorkPermit,
        analytics: any AnalyticsClient = NoopAnalyticsClient()
    ) {
        self.preferences = preferences
        self.repository = repository
        self.goalStore = goalStore
        self.workPermit = workPermit
        self.analytics = analytics

        // Seed from persisted stores so the user sees their last-saved values.
        self.readingTone = preferences.readingTone
        self.dailyGoalMinutes = goalStore.dailyGoalMinutes
        self.reminderHour = preferences.reminderHour
        self.reminderMinute = preferences.reminderMinute
        self.selectedInterestIds = Set(preferences.interestIds)
    }

    // MARK: Lifecycle

    /// Fetches the server's progress record and resumes from the saved step.
    /// Non-fatal: a network failure silently starts the flow from `.welcome`.
    public func loadProgress() async {
        guard let ticket = try? workPermit.begin() else { return }
        isLoading = true
        defer {
            if (try? workPermit.validate(ticket)) != nil {
                isLoading = false
            }
        }

        do {
            guard let progress = try await repository.fetchProgress() else { return }
            try workPermit.commit(ticket) {
                if progress.completed {
                    preferences.onboardingCompleted = true
                    return
                }

                if let ids = progress.interests { selectedInterestIds = Set(ids) }
                if let c = progress.chapterOrder { chapterOrder = ChapterOrder(rawValue: c) ?? .summaryFirst }
                if let t = progress.tone { readingTone = ReadingTone(rawValue: t) ?? .direct }
                if let g = progress.dailyGoal, DailyGoalStore.tiers.contains(g) { dailyGoalMinutes = g }
                if let h = progress.reminderHour { reminderHour = h }
                if let m = progress.reminderMinute { reminderMinute = m }
                if let step = OnboardingStep(rawValue: progress.step) { currentStep = step }
            }
        } catch is CancellationError {
            return
        } catch {
            // Non-fatal: start from the beginning.
        }
    }

    // MARK: Navigation

    /// Advances to the next step, saving progress to the server.
    public func advance() async {
        guard let ticket = try? workPermit.begin() else { return }
        switch currentStep {
        case .welcome:
            moveToStep(.interests, ticket: ticket)
        case .interests:
            await saveProgressAndMove(to: .readingPrefs, ticket: ticket)
        case .readingPrefs:
            await saveProgressAndMove(to: .dailyGoal, ticket: ticket)
        case .dailyGoal:
            await saveProgressAndMove(to: .notifications, ticket: ticket)
        case .notifications, .completed:
            await completeOnboarding(ticket: ticket)
        }
    }

    /// Skips the remaining steps and marks onboarding complete.
    public func skip() async {
        guard let ticket = try? workPermit.begin() else { return }
        await completeOnboarding(ticket: ticket)
    }

    /// Requests iOS notification authorization and then advances.
    /// Must be called from the Notifications step.
    public func requestNotificationsAndAdvance() async {
        guard let ticket = try? workPermit.begin() else { return }
        do {
            let center = UNUserNotificationCenter.current()
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch is CancellationError {
            return
        } catch {
            // Non-fatal: proceed regardless.
        }
        guard (try? workPermit.validate(ticket)) != nil else { return }
        await completeOnboarding(ticket: ticket)
    }

    // MARK: Private helpers

    private func moveToStep(_ step: OnboardingStep, ticket: UInt64) {
        try? workPermit.commit(ticket) {
            analytics.track(.onboardingStep(index: OnboardingStep.allCases.firstIndex(of: step) ?? 0))
            withAnimation(.easeInOut(duration: 0.35)) {
                currentStep = step
            }
        }
    }

    private func saveProgressAndMove(to step: OnboardingStep, ticket: UInt64) async {
        isLoading = true
        defer {
            if (try? workPermit.validate(ticket)) != nil {
                isLoading = false
            }
        }

        do {
            try applyChoicesToStores(ticket: ticket)
        } catch is CancellationError {
            return
        } catch {
            return
        }

        let body = OnboardingProgressBody(
            step: step.rawValue,
            interests: Array(selectedInterestIds),
            chapterOrder: chapterOrder.rawValue,
            tone: readingTone.rawValue,
            dailyGoal: dailyGoalMinutes,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute
        )
        do {
            try await repository.saveProgress(body)
        } catch is CancellationError {
            return
        } catch {
            // Non-fatal: local stores are already written above.
        }

        moveToStep(step, ticket: ticket)
    }

    private func completeOnboarding(ticket: UInt64) async {
        isLoading = true
        defer {
            if (try? workPermit.validate(ticket)) != nil {
                isLoading = false
            }
        }

        do {
            try applyChoicesToStores(ticket: ticket)
        } catch {
            return
        }

        let body = OnboardingCompleteBody(
            interests: Array(selectedInterestIds),
            chapterOrder: chapterOrder.rawValue,
            tone: readingTone.rawValue,
            dailyGoal: dailyGoalMinutes,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute
        )
        do {
            try await repository.complete(body)
        } catch is CancellationError {
            return
        } catch {
            // The server is authoritative for completion. Keep the flow visible
            // so a retry cannot become a false local success.
            return
        }

        // Setting this flag on AppPreferences dismisses the fullScreenCover in AppRootView.
        try? workPermit.commit(ticket) {
            preferences.onboardingCompleted = true
        }
    }

    private func applyChoicesToStores(ticket: UInt64) throws {
        try workPermit.commit(ticket) {
            preferences.readingTone = readingTone
            preferences.reminderHour = reminderHour
            preferences.reminderMinute = reminderMinute
            preferences.interestIds = Array(selectedInterestIds)
            goalStore.dailyGoalMinutes = dailyGoalMinutes
        }
    }
}
