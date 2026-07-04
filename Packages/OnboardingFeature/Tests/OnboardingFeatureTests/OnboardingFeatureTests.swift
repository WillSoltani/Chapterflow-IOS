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

// MARK: - OnboardingModel

@Suite("OnboardingModel")
@MainActor
struct OnboardingModelTests {

    private struct ModelFixture {
        let model: OnboardingModel
        let repo: MockOnboardingRepository
        let prefs: AppPreferences
    }

    private func makeModel(
        progress: OnboardingServerProgress? = nil,
        preferences: AppPreferences? = nil
    ) -> ModelFixture {
        let suite = "com.cf.tests.onboarding.\(UUID().uuidString)"
        let prefs = preferences ?? AppPreferences(defaults: UserDefaults(suiteName: suite)!)
        let repo = MockOnboardingRepository(stubbedProgress: progress)
        let model = OnboardingModel(preferences: prefs, repository: repo)
        return ModelFixture(model: model, repo: repo, prefs: prefs)
    }

    // MARK: - Initialisation

    @Test("starts at welcome step")
    func startsAtWelcome() {
        let fix = makeModel(); let model = fix.model
        #expect(model.currentStep == .welcome)
    }

    @Test("seeds selections from AppPreferences")
    func seedsFromPreferences() {
        let suite = "com.cf.tests.onboarding-seed.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let prefs = AppPreferences(defaults: defaults)
        prefs.readingTone = .competitive
        prefs.depthVariant = .hard
        prefs.dailyGoalChapters = 3
        prefs.interestIds = ["business", "science"]

        let fix = makeModel(preferences: prefs); let model = fix.model
        #expect(model.readingTone == .competitive)
        #expect(model.depthVariant == .hard)
        #expect(model.dailyGoalChapters == 3)
        #expect(model.selectedInterestIds == ["business", "science"])

        defaults.removePersistentDomain(forName: suite)
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
            depthVariant: nil,
            toneKey: nil,
            dailyGoalChapters: nil,
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
            depthVariant: "hard",
            toneKey: "competitive",
            dailyGoalChapters: 4,
            reminderHour: 7,
            reminderMinute: 30
        )
        let fix = makeModel(progress: progress); let model = fix.model
        await model.loadProgress()

        #expect(model.currentStep == .dailyGoal)
        #expect(model.selectedInterestIds.contains("business"))
        #expect(model.selectedInterestIds.contains("psychology"))
        #expect(model.depthVariant == .hard)
        #expect(model.readingTone == .competitive)
        #expect(model.dailyGoalChapters == 4)
        #expect(model.reminderHour == 7)
        #expect(model.reminderMinute == 30)
    }

    @Test("loadProgress with unknown step stays at welcome")
    func loadProgressUnknownStep() async {
        let progress = OnboardingServerProgress(
            step: "unknownFutureStep",
            completed: false,
            interests: nil,
            depthVariant: nil,
            toneKey: nil,
            dailyGoalChapters: nil,
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
        model.currentStep = .interests  // simulate being on this step
        await model.advance()

        #expect(model.currentStep == .readingPrefs)
        let bodies = await repo.savedProgressBodies
        #expect(bodies.count == 1)
        #expect(bodies.first?.step == "readingPrefs")
        #expect(bodies.first?.interests?.contains("business") == true)
    }

    @Test("advance from readingPrefs persists depth and tone")
    func advanceFromReadingPrefs() async {
        let fix = makeModel(); let model = fix.model; let repo = fix.repo
        model.depthVariant = .hard
        model.readingTone = .competitive
        model.currentStep = .readingPrefs
        await model.advance()

        #expect(model.currentStep == .dailyGoal)
        let bodies = await repo.savedProgressBodies
        #expect(bodies.first?.depthVariant == "hard")
        #expect(bodies.first?.toneKey == "competitive")
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

    @Test("skip writes choices to preferences before completing")
    func skipWritesPreferences() async {
        let fix = makeModel(); let model = fix.model; let prefs = fix.prefs
        model.selectedInterestIds = ["science"]
        model.depthVariant = .easy
        model.readingTone = .gentle
        model.dailyGoalChapters = 2
        await model.skip()

        #expect(prefs.interestIds.contains("science"))
        #expect(prefs.depthVariant == .easy)
        #expect(prefs.readingTone == .gentle)
        #expect(prefs.dailyGoalChapters == 2)
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
        // Step should still advance despite save failure
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
