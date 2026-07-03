import Foundation

/// The role a segment plays in the chapter narrative.
///
/// Conforms to tolerant decoding (RF2): unrecognised raw values decode to
/// `.unknown(rawValue)` instead of throwing. Every `switch` must handle
/// `.unknown` explicitly.
public enum AudioSegmentKind: Codable, Sendable, Equatable, Hashable {
    case greeting
    case body
    case takeaway
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "greeting": self = .greeting
        case "body":     self = .body
        case "takeaway": self = .takeaway
        default:         self = .unknown(raw)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .greeting:         try c.encode("greeting")
        case .body:             try c.encode("body")
        case .takeaway:         try c.encode("takeaway")
        case .unknown(let raw): try c.encode(raw)
        }
    }
}

/// A single narration segment — one presigned audio asset within a chapter plan.
///
/// Segments are played in array order. Each has a stable `segmentId` used as a
/// `FileStore` key for offline caching; the `url` is a short-lived presigned URL
/// that may expire mid-playback (P6.2 expiry-recovery handles this case).
public struct AudioSegment: Codable, Sendable, Identifiable, Equatable {
    /// Stable identifier — used as the FileStore key for offline caching.
    public let segmentId: String
    /// The segment's role in the chapter narrative.
    public let kind: AudioSegmentKind
    /// Presigned asset URL. Short-lived — may expire during long listening sessions.
    public let url: URL
    /// Server-provided duration hint (seconds). Use for initial timeline estimation
    /// before AVAsset finishes loading; actual duration comes from the loaded asset.
    public let durationSeconds: Double?

    public var id: String { segmentId }

    public init(segmentId: String, kind: AudioSegmentKind, url: URL, durationSeconds: Double? = nil) {
        self.segmentId = segmentId
        self.kind = kind
        self.url = url
        self.durationSeconds = durationSeconds
    }
}

/// A personalised narration plan for a single chapter.
///
/// Returned by `GET /book/books/{bookId}/chapters/{n}/audio`.
/// The plan contains one greeting segment (personalised to the current time-of-day),
/// one or more body segments, and one takeaway segment.
/// Segments must be played in array order for a coherent narrative.
public struct AudioNarrationPlan: Codable, Sendable, Equatable {
    /// The owning book identifier.
    public let bookId: String
    /// 1-based chapter number.
    public let chapterNumber: Int
    /// Chapter title for Now Playing info (matches `Chapter.title`).
    public let chapterTitle: String?
    /// Book title for Now Playing info.
    public let bookTitle: String?
    /// Cover emoji for Now Playing artwork (from `BookCatalogItem.cover.emoji`).
    public let coverEmoji: String?
    /// Cover hex color for Now Playing artwork (from `BookCatalogItem.cover.color`).
    public let coverColor: String?
    /// Ordered segments — play in array order for the complete chapter narrative.
    public let segments: [AudioSegment]

    public init(
        bookId: String,
        chapterNumber: Int,
        chapterTitle: String?,
        bookTitle: String?,
        coverEmoji: String?,
        coverColor: String?,
        segments: [AudioSegment]
    ) {
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.bookTitle = bookTitle
        self.coverEmoji = coverEmoji
        self.coverColor = coverColor
        self.segments = segments
    }
}

/// Top-level response wrapper for `GET /book/books/{bookId}/chapters/{n}/audio`.
public struct AudioNarrationResponse: Codable, Sendable {
    public let plan: AudioNarrationPlan

    public init(plan: AudioNarrationPlan) {
        self.plan = plan
    }
}
