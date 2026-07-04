import Testing
import Foundation
import CoreKit
import Persistence
import Networking
@testable import OnboardingFeature

// MARK: - Module smoke test

@Suite("OnboardingFeature")
struct OnboardingFeatureModuleTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(OnboardingFeature.moduleName == "OnboardingFeature")
    }

    @Test("defaultInterestCategories has 12 entries with unique IDs")
    func interestCategoriesUnique() {
        let ids = defaultInterestCategories.map(\.id)
        #expect(ids.count == 12)
        #expect(Set(ids).count == ids.count)
    }
}

// MARK: - OnboardingStep

@Suite("OnboardingStep")
struct OnboardingStepTests {
    @Test("rawValues round-trip to enum cases")
    func rawValueRoundTrip() {
        let cases: [(OnboardingStep, String)] = [
            (.welcome, "welcome"),
            (.interests, "interests"),
            (.readingPrefs, "readingPrefs"),
            (.dailyGoal, "dailyGoal"),
            (.notifications, "notifications"),
            (.completed, "completed"),
        ]
        for (step, raw) in cases {
            #expect(step.rawValue == raw)
            #expect(OnboardingStep(rawValue: raw) == step)
        }
    }

    @Test("unknown raw value returns nil")
    func unknownRawValue() {
        #expect(OnboardingStep(rawValue: "notAStep") == nil)
    }

    @Test("allCases covers every step")
    func allCasesCount() {
        #expect(OnboardingStep.allCases.count == 6)
    }
}

// MARK: - ChapterOrder

@Suite("ChapterOrder")
struct ChapterOrderTests {
    @Test("summaryFirst has correct raw value")
    func summaryFirstRawValue() {
        #expect(ChapterOrder.summaryFirst.rawValue == "summary_first")
    }

    @Test("scenariosFirst has correct raw value")
    func scenariosFirstRawValue() {
        #expect(ChapterOrder.scenariosFirst.rawValue == "scenarios_first")
    }

    @Test("allCases has exactly two entries")
    func allCasesCount() {
        #expect(ChapterOrder.allCases.count == 2)
    }
}

// MARK: - OnboardingModel

@Suite("OnboardingModel")
@MainActor
struct OnboardingModelTests {

    private struct ModelFixture {
        let model: OnboardingModel
        let repo: MockOnboardingRepository
        let prefs: AppPreferences
        let goalStore: DailyGoalStore
    }

    private func makeModel(
        progress: OnboardingServerProgress? = nil,
        preferences: AppPreferences? = nil
    ) -> ModelFixture {
        let suite = "com.cf.tests.onboarding.\(UUID().uuidString)"
        let goalSuite = "com.cf.tests.onboarding.goal.\(UUID().uuidString)"
        let prefs = preferences ?? AppPreferences(defaults: UserDefaults(suiteName: suite)!)
        let goalStore = DailyGoalStore(defaults: UserDefaults(suiteName: goalSuite)!)
        let repo = MockOnboardingRepository(stubbedProgress: progress)
        let model = OnboardingModel(preferences: prefs, repository: repo, goalStore: goalStore)
        return ModelFixture(model: model, repo: repo, prefs: prefs, goalStore: goalStore)
    }

    // MARK: - Initialisation

    @Test("starts at welcome step")
    func startsAtWelcome() {
        let fix = makeModel(); let model = fix.model
        #expect(model.currentStep == .welcome)
    }

    @Test("seeds selections from AppPreferences and DailyGoalStore")
    func seedsFromPreferences() {
        let suite = "com.cf.tests.onboarding-seed.\(UUID().uuidString)"
        let goalSuite = "com.cf.tests.onboarding-seed-goal.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let goalDefaults = UserDefaults(suiteName: goalSuite)!
        let prefs = AppPreferences(defaults: defaults)
        let goalStore = DailyGoalStore(defaults: goalDefaults)
        prefs.readingTone = .competitive
        prefs.interestIds = ["business", "science"]
        goalStore.dailyGoalMinutes = 20

        let repo = MockOnboardingRepository()
        let model = OnboardingModel(preferences: prefs, repository: repo, goalStore: goalStore)
        #expect(model.readingTone == .competitive)
        #expect(model.dailyGoalMinutes == 20)
        #expect(model.selectedInterestIds == ["business", "science"])

        defaults.removePersistentDomain(forName: suite)
        goalDefaults.removePersistentDomain(forName: goalSuite)
    }

    // MARK: - Progress loading

    @Test("loadProgress with nil server data leaves step at welcome")
    func loadProgressNilData() async {
        let fix = makeModel(progress: nil); let model = fix.model
        await model.loadProgress()
        #expect(model.currentStep == .welcome)
    }

    @Test("loadProgress with completed=true marks preferences complete")
    func loadProgressCompleted() async {
        let completed = OnboardingServerProgress(
            step: "completed",
            completed: true,
            interests: nil,
            chapterOrder: nil,
            tone: nil,
            dailyGoal: nil,
            reminderHour: nil,
            reminderMinute: nil
        )
        let fix = makeModel(progress: completed); let model = fix.model; let prefs = fix.prefs
        await model.loadProgress()
        #expect(prefs.onboardingCompleted == true)
    }

    @Test("loadProgress resumes from saved step and restores choices")
    func loadProgressResumes() async {
        let progress = OnboardingServerProgress(
            step: "dailyGoal",
            completed: false,
            interests: ["business", "psychology"],
            chapterOrder: "scenarios_first",
            tone: "competitive",
            dailyGoal: 20,
            reminderHour: 7,
            reminderMinute: 30
        )
        let fix = makeModel(progress: progress); let model = fix.model
        await model.loadProgress()

        #expect(model.currentStep == .dailyGoal)
        #expect(model.selectedInterestIds.contains("business"))
        #expect(model.selectedInterestIds.contains("psychology"))
        #expect(model.chapterOrder == .scenariosFirst)
        #expect(model.readingTone == .competitive)
        #expect(model.dailyGoalMinutes == 20)
        #expect(model.reminderHour == 7)
        #expect(model.reminderMinute == 30)
    }

    @Test("loadProgress ignores dailyGoal values outside the canonical tiers")
    func loadProgressIgnoresInvalidGoal() async {
        let progress = OnboardingServerProgress(
            step: "dailyGoal",
            completed: false,
            interests: nil,
            chapterOrder: nil,
            tone: nil,
            dailyGoal: 99,
            reminderHour: nil,
            reminderMinute: nil
        )
        let fix = makeModel(progress: progress); let model = fix.model
        let initialGoal = model.dailyGoalMinutes
        await model.loadProgress()
        // 99 is not a valid tier; goal should stay unchanged
        #expect(model.dailyGoalMinutes == initialGoal)
    }

    @Test("loadProgress with unknown step stays at welcome")
    func loadProgressUnknownStep() async {
        let progress = OnboardingServerProgress(
            step: "unknownFutureStep",
            completed: false,
            interests: nil,
            chapterOrder: nil,
            tone: nil,
            dailyGoal: nil,
            reminderHour: nil,
            reminderMinute: nil
        )
        let fix = makeModel(progress: progress); let model = fix.model
        await model.loadProgress()
        #expect(model.currentStep == .welcome)
    }

    // MARK: - Advance

    @Test("advance from welcome moves to interests without server call")
    func advanceFromWelcome() async {
        let fix = makeModel(); let model = fix.model; let repo = fix.repo
        await model.advance()
        #expect(model.currentStep == .interests)
        let bodies = await repo.savedProgressBodies
        #expect(bodies.isEmpty)
    }

    @Test("advance from interests saves progress and moves to readingPrefs")
    func advanceFromInterests() async {
        let fix = makeModel(); let model = fix.model; let repo = fix.repo
        model.selectedInterestIds = ["business"]
        model.currentStep = .interests
        await model.advance()

        #expect(model.currentStep == .readingPrefs)
        let bodies = await repo.savedProgressBodies
        #expect(bodies.count == 1)
        #expect(bodies.first?.step == "readingPrefs")
        #expect(bodies.first?.interests?.contains("business") == true)
    }

    @Test("advance from readingPrefs posts chapterOrder and tone with correct server field names")
    func advanceFromReadingPrefs() async {
        let fix = makeModel(); let model = fix.model; let repo = fix.repo
        model.chapterOrder = .scenariosFirst
        model.readingTone = .competitive
        model.currentStep = .readingPrefs
        await model.advance()

        #expect(model.currentStep == .dailyGoal)
        let bodies = await repo.savedProgressBodies
        #expect(bodies.first?.chapterOrder == "scenarios_first")
        #expect(bodies.first?.tone == "competitive")
    }

    @Test("advance from notifications calls complete and sets onboardingCompleted")
    func advanceFromNotifications() async {
        let fix = makeModel(); let model = fix.model; let repo = fix.repo; let prefs = fix.prefs
        model.currentStep = .notifications
        await model.advance()

        #expect(prefs.onboardingCompleted == true)
        let completeBodies = await repo.completeBodies
        #expect(completeBodies.count == 1)
    }

    // MARK: - Skip

    @Test("skip sets onboardingCompleted and calls complete endpoint")
    func skipSetsCompleted() async {
        let fix = makeModel(); let model = fix.model; let repo = fix.repo; let prefs = fix.prefs
        await model.skip()

        #expect(prefs.onboardingCompleted == true)
        let completeBodies = await repo.completeBodies
        #expect(completeBodies.count == 1)
    }

    @Test("skip writes choices to stores before completing")
    func skipWritesPreferences() async {
        let fix = makeModel(); let model = fix.model; let prefs = fix.prefs; let goalStore = fix.goalStore
        model.selectedInterestIds = ["science"]
        model.chapterOrder = .summaryFirst
        model.readingTone = .gentle
        model.dailyGoalMinutes = 20
        await model.skip()

        #expect(prefs.interestIds.contains("science"))
        #expect(prefs.readingTone == .gentle)
        #expect(goalStore.dailyGoalMinutes == 20)
    }

    // MARK: - Goal round-trip

    @Test("completing onboarding writes dailyGoalMinutes to DailyGoalStore")
    func goalRoundTrip() async {
        let fix = makeModel(); let model = fix.model; let goalStore = fix.goalStore
        model.dailyGoalMinutes = 30
        model.currentStep = .notifications
        await model.advance()

        #expect(goalStore.dailyGoalMinutes == 30)
    }

    @Test("complete body posts dailyGoal field with minutes value")
    func completeBodyFieldNames() async {
        let fix = makeModel(); let model = fix.model; let repo = fix.repo
        model.dailyGoalMinutes = 20
        model.chapterOrder = .summaryFirst
        model.readingTone = .direct
        model.selectedInterestIds = ["business"]
        model.currentStep = .notifications
        await model.advance()

        let bodies = await repo.completeBodies
        #expect(bodies.first?.dailyGoal == 20)
        #expect(bodies.first?.chapterOrder == "summary_first")
        #expect(bodies.first?.tone == "direct")
        #expect(bodies.first?.interests.contains("business") == true)
    }

    // MARK: - Network failure resilience

    @Test("loadProgress with throw still starts flow at welcome")
    func loadProgressThrowIsNonFatal() async {
        let fix = makeModel(); let model = fix.model; let repo = fix.repo
        await repo.setFetchShouldThrow(AppError.offline)
        await model.loadProgress()
        #expect(model.currentStep == .welcome)
    }

    @Test("advance: server save failure still navigates forward")
    func advanceSaveFailureStillNavigates() async {
        let fix = makeModel(); let model = fix.model; let repo = fix.repo
        await repo.setSaveShouldThrow(AppError.offline)
        model.currentStep = .interests
        await model.advance()
        #expect(model.currentStep == .readingPrefs)
    }
}

// MARK: - MockOnboardingRepository extras for tests

extension MockOnboardingRepository {
    func setFetchShouldThrow(_ error: any Error) {
        fetchShouldThrow = error
    }

    func setSaveShouldThrow(_ error: any Error) {
        saveShouldThrow = error
    }
}
