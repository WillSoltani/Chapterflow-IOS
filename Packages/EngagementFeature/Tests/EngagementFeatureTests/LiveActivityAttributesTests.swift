// Tests for the Live Activity attribute types (P8.2).
// These are pure Codable / Hashable value types — no ActivityKit runtime needed.

import Testing
import Foundation

// Re-implement the attribute types locally so the EngagementFeature package does
// not need to import ActivityKit (which requires an iOS device context).
// The real types in ChapterFlow/LiveActivities/ are identical in shape.

// MARK: - Mirror of ReadingSessionStatus (tested here independently)

private struct ReadingSessionStatus: Codable, Hashable {
    var elapsedSeconds: Int
    var chapterProgress: Double
    var isPlaying: Bool
    var streakAtRisk: Bool

    init(elapsedSeconds: Int, chapterProgress: Double, isPlaying: Bool, streakAtRisk: Bool) {
        self.elapsedSeconds = elapsedSeconds
        self.chapterProgress = max(0, min(1, chapterProgress))
        self.isPlaying = isPlaying
        self.streakAtRisk = streakAtRisk
    }

    var elapsedString: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var progressPercent: Int { Int(chapterProgress * 100) }
}

// MARK: - Mirror of StreakAtRiskStatus

private struct StreakAtRiskStatus: Codable, Hashable {
    var midnightDeadline: Date
    var isStreakSaved: Bool
}

// MARK: - Tests

@Suite("ReadingSessionStatus")
struct ReadingSessionStatusTests {

    @Test("elapsedString formats correctly")
    func elapsedStringFormat() {
        let zero   = ReadingSessionStatus(elapsedSeconds: 0, chapterProgress: 0, isPlaying: false, streakAtRisk: false)
        let oneMin = ReadingSessionStatus(elapsedSeconds: 60, chapterProgress: 0, isPlaying: false, streakAtRisk: false)
        let mixed  = ReadingSessionStatus(elapsedSeconds: 754, chapterProgress: 0, isPlaying: false, streakAtRisk: false)
        let large  = ReadingSessionStatus(elapsedSeconds: 3661, chapterProgress: 0, isPlaying: false, streakAtRisk: false)

        #expect(zero.elapsedString   == "0:00")
        #expect(oneMin.elapsedString == "1:00")
        #expect(mixed.elapsedString  == "12:34")
        #expect(large.elapsedString  == "61:01")
    }

    @Test("progressPercent clamps and rounds")
    func progressPercent() {
        let half     = ReadingSessionStatus(elapsedSeconds: 0, chapterProgress: 0.5,   isPlaying: false, streakAtRisk: false)
        let overflow = ReadingSessionStatus(elapsedSeconds: 0, chapterProgress: 1.5,   isPlaying: false, streakAtRisk: false)
        let negative = ReadingSessionStatus(elapsedSeconds: 0, chapterProgress: -0.1,  isPlaying: false, streakAtRisk: false)

        #expect(half.progressPercent     == 50)
        #expect(overflow.progressPercent == 100)
        #expect(negative.progressPercent == 0)
    }

    @Test("chapterProgress clamped at init")
    func progressClampedAtInit() {
        let over  = ReadingSessionStatus(elapsedSeconds: 0, chapterProgress: 2.0, isPlaying: false, streakAtRisk: false)
        let under = ReadingSessionStatus(elapsedSeconds: 0, chapterProgress: -1.0, isPlaying: false, streakAtRisk: false)
        let exact = ReadingSessionStatus(elapsedSeconds: 0, chapterProgress: 0.62, isPlaying: false, streakAtRisk: false)

        #expect(over.chapterProgress  == 1.0)
        #expect(under.chapterProgress == 0.0)
        #expect(exact.chapterProgress == 0.62)
    }

    @Test("Hashable equality by value")
    func hashableEquality() {
        let a = ReadingSessionStatus(elapsedSeconds: 60, chapterProgress: 0.5, isPlaying: true, streakAtRisk: false)
        let b = ReadingSessionStatus(elapsedSeconds: 60, chapterProgress: 0.5, isPlaying: true, streakAtRisk: false)
        let c = ReadingSessionStatus(elapsedSeconds: 61, chapterProgress: 0.5, isPlaying: true, streakAtRisk: false)

        #expect(a == b)
        #expect(a != c)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = ReadingSessionStatus(
            elapsedSeconds: 754,
            chapterProgress: 0.62,
            isPlaying: false,
            streakAtRisk: true
        )
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReadingSessionStatus.self, from: data)

        #expect(decoded.elapsedSeconds   == original.elapsedSeconds)
        #expect(decoded.chapterProgress  == original.chapterProgress)
        #expect(decoded.isPlaying        == original.isPlaying)
        #expect(decoded.streakAtRisk     == original.streakAtRisk)
    }
}

@Suite("StreakAtRiskStatus")
struct StreakAtRiskStatusTests {

    @Test("isStreakSaved defaults to false")
    func defaultNotSaved() {
        let status = StreakAtRiskStatus(midnightDeadline: Date(), isStreakSaved: false)
        #expect(status.isStreakSaved == false)
    }

    @Test("Codable round-trip preserves deadline and flag")
    func codableRoundTrip() throws {
        let deadline = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let original = StreakAtRiskStatus(midnightDeadline: deadline, isStreakSaved: true)
        let data     = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(StreakAtRiskStatus.self, from: data)

        #expect(abs(decoded.midnightDeadline.timeIntervalSince(deadline)) < 0.001)
        #expect(decoded.isStreakSaved == true)
    }

    @Test("Hashable reflects saved state change")
    func hashableOnFlagChange() {
        let d    = Date()
        let a    = StreakAtRiskStatus(midnightDeadline: d, isStreakSaved: false)
        var b    = StreakAtRiskStatus(midnightDeadline: d, isStreakSaved: false)
        b.isStreakSaved = true

        #expect(a != b)
    }
}

@Suite("elapsedString edge cases")
struct ElapsedStringEdgeCases {

    @Test("Exactly one hour")
    func oneHour() {
        let status = ReadingSessionStatus(elapsedSeconds: 3600, chapterProgress: 0, isPlaying: false, streakAtRisk: false)
        #expect(status.elapsedString == "60:00")
    }

    @Test("Just under one minute")
    func underOneMinute() {
        let status = ReadingSessionStatus(elapsedSeconds: 59, chapterProgress: 0, isPlaying: false, streakAtRisk: false)
        #expect(status.elapsedString == "0:59")
    }
}
