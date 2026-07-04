import SwiftUI
import Persistence
import Networking
import UserNotifications

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

    // MARK: Init

    public init(
        preferences: AppPreferences,
        repository: any OnboardingRepository,
        goalStore: DailyGoalStore? = nil
    ) {
        self.preferences = preferences
        self.repository = repository
        self.goalStore = goalStore ?? DailyGoalStore.shared

        // Seed from persisted stores so the user sees their last-saved values.
        self.readingTone = preferences.readingTone
        self.dailyGoalMinutes = (goalStore ?? DailyGoalStore.shared).dailyGoalMinutes
        self.reminderHour = preferences.reminderHour
        self.reminderMinute = preferences.reminderMinute
        self.selectedInterestIds = Set(preferences.interestIds)
    }

    // MARK: Lifecycle

    /// Fetches the server's progress record and resumes from the saved step.
    /// Non-fatal: a network failure silently starts the flow from `.welcome`.
    public func loadProgress() async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let progress = try await repository.fetchProgress() else { return }

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
        } catch {
            // Non-fatal: start from the beginning.
        }
    }

    // MARK: Navigation

    /// Advances to the next step, saving progress to the server.
    public func advance() async {
        switch currentStep {
        case .welcome:
            moveToStep(.interests)
        case .interests:
            await saveProgressAndMove(to: .readingPrefs)
        case .readingPrefs:
            await saveProgressAndMove(to: .dailyGoal)
        case .dailyGoal:
            await saveProgressAndMove(to: .notifications)
        case .notifications, .completed:
            await completeOnboarding()
        }
    }

    /// Skips the remaining steps and marks onboarding complete.
    public func skip() async {
        await completeOnboarding()
    }

    /// Requests iOS notification authorization and then advances.
    /// Must be called from the Notifications step.
    public func requestNotificationsAndAdvance() async {
        do {
            let center = UNUserNotificationCenter.current()
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            // Non-fatal: proceed regardless.
        }
        await completeOnboarding()
    }

    // MARK: Private helpers

    private func moveToStep(_ step: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = step
        }
    }

    private func saveProgressAndMove(to step: OnboardingStep) async {
        isLoading = true
        defer { isLoading = false }

        applyChoicesToStores()

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
        } catch {
            // Non-fatal: local stores are already written above.
        }

        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = step
        }
    }

    private func completeOnboarding() async {
        isLoading = true
        defer { isLoading = false }

        applyChoicesToStores()

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
        } catch {
            // Non-fatal: mark complete locally regardless.
        }

        // Setting this flag on AppPreferences dismisses the fullScreenCover in AppRootView.
        preferences.onboardingCompleted = true
    }

    private func applyChoicesToStores() {
        preferences.readingTone = readingTone
        preferences.reminderHour = reminderHour
        preferences.reminderMinute = reminderMinute
        preferences.interestIds = Array(selectedInterestIds)
        goalStore.dailyGoalMinutes = dailyGoalMinutes
    }
}
