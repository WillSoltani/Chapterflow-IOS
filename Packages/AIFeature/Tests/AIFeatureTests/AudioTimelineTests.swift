import Testing
import Foundation
@testable import AIFeature

// MARK: - AudioTimeline unit tests

@Suite("AudioTimeline")
struct AudioTimelineTests {

    // MARK: - Basic construction

    @Test("empty timeline has zero duration and zero segments")
    func emptyTimeline() {
        let t = AudioTimeline(durations: [])
        #expect(t.totalDuration == 0)
        #expect(t.segmentCount == 0)
        #expect(t.isEmpty)
        let pos = t.position(at: 0)
        #expect(pos.segmentIndex == 0)
        #expect(pos.localOffset == 0)
    }

    @Test("single segment timeline")
    func singleSegment() {
        let t = AudioTimeline(durations: [60])
        #expect(t.totalDuration == 60)
        #expect(t.segmentCount == 1)

        // Start
        let posStart = t.position(at: 0)
        #expect(posStart.segmentIndex == 0)
        #expect(posStart.localOffset == 0)

        // Mid
        let posMid = t.position(at: 30)
        #expect(posMid.segmentIndex == 0)
        #expect(abs(posMid.localOffset - 30) < 0.001)

        // End
        let posEnd = t.position(at: 60)
        #expect(posEnd.segmentIndex == 0)
        #expect(abs(posEnd.localOffset - 60) < 0.001)
    }

    @Test("three segment timeline — basic positions")
    func threeSegments() {
        // greeting 12s | body 180s | takeaway 48s  → total 240s
        let t = AudioTimeline(durations: [12, 180, 48])
        #expect(abs(t.totalDuration - 240) < 0.001)

        // Inside first segment
        let pos0 = t.position(at: 6)
        #expect(pos0.segmentIndex == 0)
        #expect(abs(pos0.localOffset - 6) < 0.001)

        // Exactly at boundary between 0 and 1 → resolves to start of segment 1
        let posAt12 = t.position(at: 12)
        #expect(posAt12.segmentIndex == 1)
        #expect(abs(posAt12.localOffset - 0) < 0.001)

        // Inside second segment
        let pos1 = t.position(at: 100)
        #expect(pos1.segmentIndex == 1)
        #expect(abs(pos1.localOffset - 88) < 0.001)  // 100 - 12 = 88

        // Exactly at boundary between 1 and 2 → start of segment 2
        let posAt192 = t.position(at: 192)   // 12 + 180
        #expect(posAt192.segmentIndex == 2)
        #expect(abs(posAt192.localOffset - 0) < 0.001)

        // Inside third segment
        let pos2 = t.position(at: 220)
        #expect(pos2.segmentIndex == 2)
        #expect(abs(pos2.localOffset - 28) < 0.001)  // 220 - 192 = 28
    }

    @Test("globalTime round-trip accuracy")
    func globalTimeRoundTrip() {
        let t = AudioTimeline(durations: [12, 180, 48])
        let testTimes: [Double] = [0, 5, 12, 50, 100, 192, 210, 240]

        for globalTime in testTimes {
            let (seg, offset) = t.position(at: globalTime)
            let recovered = t.globalTime(segmentIndex: seg, localOffset: offset)
            #expect(abs(recovered - min(globalTime, t.totalDuration)) < 0.001,
                    "Round-trip failed for globalTime=\(globalTime): got \(recovered)")
        }
    }

    @Test("clamping — negative time resolves to segment 0, offset 0")
    func clampNegative() {
        let t = AudioTimeline(durations: [60, 120])
        let pos = t.position(at: -10)
        #expect(pos.segmentIndex == 0)
        #expect(pos.localOffset == 0)
    }

    @Test("clamping — time beyond totalDuration resolves to end of last segment")
    func clampBeyondEnd() {
        let t = AudioTimeline(durations: [60, 120])
        let pos = t.position(at: 9999)
        #expect(pos.segmentIndex == 1)
        // local offset should equal the segment duration (clamped)
        #expect(abs(pos.localOffset - 120) < 0.001)
    }

    @Test("fraction is 0 at start and 1 at end")
    func fractionBounds() {
        let t = AudioTimeline(durations: [30, 60, 10])
        #expect(t.fraction(at: 0) == 0)
        #expect(abs(t.fraction(at: 100) - 1.0) < 0.001)
    }

    @Test("fraction mid-chapter")
    func fractionMid() {
        let t = AudioTimeline(durations: [100])
        #expect(abs(t.fraction(at: 50) - 0.5) < 0.001)
        #expect(abs(t.fraction(at: 25) - 0.25) < 0.001)
    }

    @Test("globalStart and globalEnd of each segment are correct")
    func segmentBoundaries() {
        let t = AudioTimeline(durations: [10, 20, 30])
        #expect(t.globalStart(of: 0) == 0)
        #expect(t.globalEnd(of: 0) == 10)
        #expect(t.globalStart(of: 1) == 10)
        #expect(t.globalEnd(of: 1) == 30)
        #expect(t.globalStart(of: 2) == 30)
        #expect(t.globalEnd(of: 2) == 60)
    }

    @Test("globalTime with out-of-range segmentIndex returns totalDuration")
    func globalTimeOutOfRange() {
        let t = AudioTimeline(durations: [10, 20])
        #expect(t.globalTime(segmentIndex: 99, localOffset: 0) == t.totalDuration)
    }

    @Test("isTime correctly identifies segment membership")
    func isTimeInSegment() {
        let t = AudioTimeline(durations: [10, 20, 30])
        // Segment 0: 0..<10
        #expect(t.isTime(5, inSegment: 0) == true)
        #expect(t.isTime(10, inSegment: 0) == false)  // boundary belongs to next

        // Segment 1: 10..<30
        #expect(t.isTime(10, inSegment: 1) == true)
        #expect(t.isTime(29.9, inSegment: 1) == true)
        #expect(t.isTime(30, inSegment: 1) == false)

        // Segment 2: 30..<60
        #expect(t.isTime(30, inSegment: 2) == true)
        #expect(t.isTime(59, inSegment: 2) == true)
    }

    @Test("15-second skip forward crosses segment boundary")
    func skipForwardCrossesSegment() {
        // Segment 0: 0..<12, segment 1: 12..<192
        let t = AudioTimeline(durations: [12, 180, 48])

        // Position 9s into segment 0 — skip 15s → should land in segment 1
        let before = 9.0
        let after = before + 15  // = 24
        let pos = t.position(at: after)
        #expect(pos.segmentIndex == 1)
        #expect(abs(pos.localOffset - 12) < 0.001)  // 24 - 12 = 12s into segment 1
    }

    @Test("15-second skip back crosses segment boundary")
    func skipBackwardCrossesSegment() {
        // Segment 0: 0..<12, segment 1: 12..<192, segment 2: 192..<240
        let t = AudioTimeline(durations: [12, 180, 48])

        // Position 5s into segment 1 (globalTime = 17) — skip back 15s → should land in segment 0
        let before = 17.0
        let after = before - 15  // = 2
        let pos = t.position(at: after)
        #expect(pos.segmentIndex == 0)
        #expect(abs(pos.localOffset - 2) < 0.001)
    }

    @Test("durations of zero or negative are clamped to epsilon")
    func zeroDurationClamping() {
        let t = AudioTimeline(durations: [0, -5, 10])
        // Should not crash and totalDuration should be > 0
        #expect(t.totalDuration > 0)
        #expect(t.segmentCount == 3)
    }

    @Test("real chapter plan durations — greeting 12.5 / body 187.3 / body 154.2 / takeaway 45.8")
    func realChapterPlanTimeline() {
        let t = AudioTimeline(durations: [12.5, 187.3, 154.2, 45.8])
        let expected = 12.5 + 187.3 + 154.2 + 45.8
        #expect(abs(t.totalDuration - expected) < 0.01)

        // Seeking 1s before takeaway start → still in body-2
        let takeawayStart = 12.5 + 187.3 + 154.2
        let pos = t.position(at: takeawayStart - 1)
        #expect(pos.segmentIndex == 2)

        // Exactly at takeaway start → segment 3
        let posAtTakeaway = t.position(at: takeawayStart)
        #expect(posAtTakeaway.segmentIndex == 3)
        #expect(abs(posAtTakeaway.localOffset - 0) < 0.001)
    }
}
