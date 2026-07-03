import Foundation

/// Pure, `Sendable` mapping between a single global chapter timeline and the
/// individual audio segments that compose it.
///
/// Build the timeline once segment durations are known (from server hints or
/// loaded `AVAsset` durations), then use `position(at:)` for scrubbing and
/// `globalTime(segmentIndex:localOffset:)` for the reverse mapping.
///
/// All operations are O(n) where n is the number of segments (typically 3–6).
///
/// Fully unit-tested in `AudioTimelineTests`.
public struct AudioTimeline: Sendable, Equatable {

    // MARK: - Segment mark

    /// The per-segment entry stored in the timeline.
    public struct Mark: Sendable, Equatable {
        public let segmentIndex: Int
        /// Global time (seconds) at which this segment begins.
        public let globalStart: Double
        /// Duration of this segment (seconds).
        public let duration: Double
        /// Global time at which this segment ends.
        public var globalEnd: Double { globalStart + duration }
    }

    // MARK: - Storage

    private let marks: [Mark]

    // MARK: - Init

    /// Constructs a timeline from an ordered list of segment durations (in seconds).
    ///
    /// - Parameter durations: One element per segment, in playback order.
    ///   Values ≤ 0 are clamped to a tiny epsilon so every segment occupies
    ///   a non-zero span (prevents divide-by-zero in downstream calculations).
    public init(durations: [Double]) {
        var accumulated: Double = 0
        marks = durations.enumerated().map { index, raw in
            let d = Swift.max(raw, 0.001)
            let mark = Mark(segmentIndex: index, globalStart: accumulated, duration: d)
            accumulated += d
            return mark
        }
    }

    // MARK: - Properties

    /// Total playback duration of all segments combined (seconds).
    public var totalDuration: Double { marks.last?.globalEnd ?? 0 }

    /// Number of segments in the timeline.
    public var segmentCount: Int { marks.count }

    /// Whether the timeline is empty (no segments loaded yet).
    public var isEmpty: Bool { marks.isEmpty }

    // MARK: - Queries

    /// Maps a global time to `(segmentIndex, localOffset)`.
    ///
    /// The global time is clamped to `0...totalDuration`. `localOffset` is
    /// clamped to the segment's duration so it never overshoots.
    ///
    /// Boundary case: a time exactly equal to a segment's `globalEnd` resolves
    /// to the *beginning* of the next segment (index+1, offset=0), unless it is
    /// also `totalDuration`, in which case it stays in the last segment.
    public func position(at globalTime: Double) -> (segmentIndex: Int, localOffset: Double) {
        guard !marks.isEmpty else { return (0, 0) }
        let clamped = Swift.max(0, Swift.min(totalDuration, globalTime))

        // Walk from the last mark backwards to find the first whose start ≤ clamped.
        for mark in marks.reversed() where clamped >= mark.globalStart {
            let offset = Swift.min(clamped - mark.globalStart, mark.duration)
            return (mark.segmentIndex, offset)
        }
        return (0, 0)
    }

    /// Converts `(segmentIndex, localOffset)` back to a global chapter time.
    ///
    /// If `segmentIndex` is out of range, returns `totalDuration`.
    public func globalTime(segmentIndex: Int, localOffset: Double) -> Double {
        guard segmentIndex < marks.count else { return totalDuration }
        return marks[segmentIndex].globalStart + Swift.max(0, localOffset)
    }

    /// Global start time of segment at `index`.
    public func globalStart(of index: Int) -> Double {
        guard index < marks.count else { return totalDuration }
        return marks[index].globalStart
    }

    /// Global end time of segment at `index`.
    public func globalEnd(of index: Int) -> Double {
        guard index < marks.count else { return totalDuration }
        return marks[index].globalEnd
    }

    /// The `Mark` for `index`, or `nil` when out of range.
    public func mark(at index: Int) -> Mark? {
        guard index >= 0, index < marks.count else { return nil }
        return marks[index]
    }

    /// `true` when `globalTime` falls within the given segment.
    public func isTime(_ globalTime: Double, inSegment index: Int) -> Bool {
        guard let mark = mark(at: index) else { return false }
        return globalTime >= mark.globalStart && globalTime < mark.globalEnd
    }

    /// Normalised 0…1 progress fraction of total duration.
    public func fraction(at globalTime: Double) -> Double {
        guard totalDuration > 0 else { return 0 }
        return Swift.max(0, Swift.min(1, globalTime / totalDuration))
    }

    /// All segment marks in order.
    public var allMarks: [Mark] { marks }
}
