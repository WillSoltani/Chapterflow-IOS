import Testing
import Foundation
@testable import Models

// MARK: - Golden vector types (decoded from JSON)

private struct GoldenVectors: Decodable {
    let vectors: [GoldenVector]
}

private struct GoldenVector: Decodable {
    let id: String
    let description: String
    let input: GoldenInput
    let grade: Int
    let expected: GoldenExpected
}

private struct GoldenInput: Decodable {
    let state: String
    let stability: Double
    let difficulty: Double
    let reps: Int
    let lapses: Int
    let elapsedDays: Double
}

private struct GoldenExpected: Decodable {
    let stability: Double
    let difficulty: Double
    let scheduledDays: Int
    let newState: String
    let lapses: Int
}

// MARK: - Helpers

/// Tolerance for floating-point comparisons (0.005 = half a rounded 2dp unit).
private let fpTolerance = 0.005

private func loadGoldenVectors() throws -> [GoldenVector] {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: "fsrs_golden_vectors", withExtension: "json") else {
        throw TestError.missingResource("fsrs_golden_vectors.json")
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(GoldenVectors.self, from: data).vectors
}

private enum TestError: Error {
    case missingResource(String)
    case unknownGrade(Int)
    case unknownState(String)
}

// MARK: - Golden vector suite

@Suite("FSRSScheduler — server golden vectors")
struct FSRSSchedulerGoldenTests {

    /// Build a `FSRSScheduleInput` from a `GoldenInput`, pinning `lastReviewAt`
    /// so that the scheduler computes the desired `elapsedDays`.
    private func makeInput(_ raw: GoldenInput, now: Date) -> FSRSScheduleInput {
        let state = FsrsCardState(rawValue: raw.state)
        let lastReviewAt: Date? = (state == .new || raw.elapsedDays == 0)
            ? nil
            : now.addingTimeInterval(-raw.elapsedDays * 86400)
        return FSRSScheduleInput(
            stability:    raw.stability,
            difficulty:   raw.difficulty,
            reps:         raw.reps,
            lapses:       raw.lapses,
            state:        state,
            lastReviewAt: lastReviewAt
        )
    }

    @Test("all golden vectors reproduce server output")
    func allGoldenVectors() throws {
        let vectors = try loadGoldenVectors()
        let now = Date(timeIntervalSince1970: 1_750_291_200) // 2025-06-19 00:00:00 UTC (fixed)

        for vector in vectors {
            guard let gradeRaw = FSRSGrade(rawValue: vector.grade) else {
                throw TestError.unknownGrade(vector.grade)
            }

            let input  = makeInput(vector.input, now: now)
            let result = FSRSScheduler.schedule(input: input, grade: gradeRaw, now: now)
            let exp    = vector.expected

            #expect(
                abs(result.stability - exp.stability) < fpTolerance,
                "[\(vector.id)] stability: got \(result.stability), expected \(exp.stability)"
            )
            #expect(
                abs(result.difficulty - exp.difficulty) < fpTolerance,
                "[\(vector.id)] difficulty: got \(result.difficulty), expected \(exp.difficulty)"
            )
            #expect(
                result.scheduledDays == exp.scheduledDays,
                "[\(vector.id)] scheduledDays: got \(result.scheduledDays), expected \(exp.scheduledDays)"
            )
            let expectedState = FsrsCardState(rawValue: exp.newState)
            #expect(
                result.newState == expectedState,
                "[\(vector.id)] state: got \(result.newState.rawValue), expected \(exp.newState)"
            )
            #expect(
                result.lapses == exp.lapses,
                "[\(vector.id)] lapses: got \(result.lapses), expected \(exp.lapses)"
            )
        }
    }
}

// MARK: - Unit tests for core invariants

@Suite("FSRSScheduler — core invariants")
struct FSRSSchedulerInvariantTests {

    private let now = Date(timeIntervalSince1970: 1_750_291_200)

    // MARK: New card

    @Test("new card Again → learning state")
    func newCardAgainState() {
        let input = FSRSScheduleInput(stability: 0, difficulty: 0, reps: 0, lapses: 0, state: .new, lastReviewAt: nil)
        let result = FSRSScheduler.schedule(input: input, grade: .again, now: now)
        #expect(result.newState == .learning)
        #expect(result.lapses == 1)
    }

    @Test("new card non-Again → review (due) state")
    func newCardGoodState() {
        let input = FSRSScheduleInput(stability: 0, difficulty: 0, reps: 0, lapses: 0, state: .new, lastReviewAt: nil)
        let result = FSRSScheduler.schedule(input: input, grade: .good, now: now)
        #expect(result.newState == .due)
        #expect(result.lapses == 0)
    }

    // MARK: C4 lapse invariant

    @Test("C4: post-lapse stability never exceeds prior stability")
    func c4LapseNeverIncreases() {
        let prior = FSRSScheduleInput(
            stability: 2.0, difficulty: 1.0, reps: 4, lapses: 0, state: .due,
            lastReviewAt: now.addingTimeInterval(-365 * 86400)
        )
        let result = FSRSScheduler.schedule(input: prior, grade: .again, now: now)
        #expect(result.stability <= prior.stability,
                "post-lapse stability \(result.stability) exceeded prior \(prior.stability)")
        #expect(result.newState == .relearning)
        #expect(result.lapses == 1)
    }

    @Test("C4: post-lapse stability floored at 0.1")
    func c4LapseFloor() {
        let tinyStability = FSRSScheduleInput(
            stability: 0.05, difficulty: 1.0, reps: 2, lapses: 0, state: .due,
            lastReviewAt: now.addingTimeInterval(-1 * 86400)
        )
        let result = FSRSScheduler.schedule(input: tinyStability, grade: .again, now: now)
        #expect(result.stability >= 0.1,
                "lapse stability \(result.stability) not floored at 0.1")
    }

    // MARK: Retention target

    @Test("higher retention target produces shorter interval")
    func higherRetentionShorterInterval() {
        let input = FSRSScheduleInput(
            stability: 20, difficulty: 5, reps: 3, lapses: 0, state: .due,
            lastReviewAt: now
        )
        let at95 = FSRSScheduler.schedule(input: input, grade: .good, now: now, desiredRetention: 0.95)
        let at70 = FSRSScheduler.schedule(input: input, grade: .good, now: now, desiredRetention: 0.70)
        #expect(at95.scheduledDays < at70.scheduledDays,
                "95% interval \(at95.scheduledDays) should be < 70% interval \(at70.scheduledDays)")
    }

    @Test("default retention 0.9 matches explicit 0.9")
    func defaultRetentionMatchesExplicit() {
        let input = FSRSScheduleInput(
            stability: 20, difficulty: 5, reps: 3, lapses: 0, state: .due,
            lastReviewAt: now
        )
        let implicit = FSRSScheduler.schedule(input: input, grade: .good, now: now)
        let explicit  = FSRSScheduler.schedule(input: input, grade: .good, now: now, desiredRetention: 0.9)
        #expect(implicit.scheduledDays == explicit.scheduledDays)
    }

    // MARK: When elapsed == stability, r == 0.9

    @Test("retrievability is 0.9 when elapsed equals stability")
    func retrievabilityAtDesiredRetention() {
        let s = 10.0
        let r = FSRSScheduler.retrievability(elapsedDays: s, stability: s)
        #expect(abs(r - 0.9) < 1e-9, "r should be 0.9 when elapsed=stability, got \(r)")
    }

    // MARK: nextDueDate

    @Test("nextDueDate is scheduledDays after now")
    func nextDueDateCorrect() {
        let input = FSRSScheduleInput(stability: 0, difficulty: 0, reps: 0, lapses: 0, state: .new, lastReviewAt: nil)
        let result = FSRSScheduler.schedule(input: input, grade: .good, now: now)
        let expectedDue = now.addingTimeInterval(Double(result.scheduledDays) * 86400)
        #expect(abs(result.nextDueDate.timeIntervalSince(expectedDue)) < 1,
                "nextDueDate should be scheduledDays after now")
    }

    // MARK: Minimum interval

    @Test("interval is always at least 1 day")
    func minimumInterval() {
        for grade in FSRSGrade.allCases {
            let input = FSRSScheduleInput(stability: 0, difficulty: 0, reps: 0, lapses: 0, state: .new, lastReviewAt: nil)
            let result = FSRSScheduler.schedule(input: input, grade: grade, now: now)
            #expect(result.scheduledDays >= 1, "interval for grade \(grade) was < 1")
        }
    }
}

// MARK: - FSRSGrade tests

@Suite("FSRSGrade")
struct FSRSGradeTests {

    @Test("all cases have rawValues 1–4")
    func rawValues() {
        #expect(FSRSGrade.again.rawValue == 1)
        #expect(FSRSGrade.hard.rawValue  == 2)
        #expect(FSRSGrade.good.rawValue  == 3)
        #expect(FSRSGrade.easy.rawValue  == 4)
    }

    @Test("allCases has exactly 4 grades")
    func allCasesCount() {
        #expect(FSRSGrade.allCases.count == 4)
    }
}

// MARK: - FsrsCardState evolution (server "review" decodes as .due)

@Suite("FsrsCardState — server wire values")
struct FsrsCardStateWireTests {

    @Test("server value 'review' decodes to .due")
    func reviewDecodesToDue() {
        #expect(FsrsCardState(rawValue: "review") == .due)
    }

    @Test(".due encodes as 'review' (server canonical)")
    func dueEncodesAsReview() {
        #expect(FsrsCardState.due.rawValue == "review")
    }

    @Test("legacy 'due' also decodes to .due")
    func legacyDueDecodesToDue() {
        #expect(FsrsCardState(rawValue: "due") == .due)
    }
}
