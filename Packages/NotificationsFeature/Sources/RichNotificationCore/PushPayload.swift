import Foundation

/// Parsed, type-safe representation of a ChapterFlow push notification payload.
///
/// All fields are optional because any field may be absent in a real push.
/// RF2: tolerant — missing keys produce `nil`, never a crash.
public struct PushPayload: Sendable, Equatable {
    /// Raw `"type"` string from the payload (e.g. `"badge_earned"`).
    public let typeRaw: String
    /// Image URL to download and attach as a `UNNotificationAttachment`.
    /// Only `https://` URLs are accepted; others are discarded.
    public let imageURL: URL?
    /// Badge key for `badge_earned` pushes (e.g. `"first_chapter"`).
    public let badgeKey: String?
    /// Human-readable badge display name.
    public let badgeName: String?
    /// Book identifier, used to synthesise chapter deep links.
    public let bookId: String?
    /// Chapter number, used to synthesise chapter deep links.
    public let chapterNumber: Int?
    /// Pre-formed `chapterflow://` deep link. Preferred over synthesised links.
    public let deepLink: URL?

    public init(
        typeRaw: String,
        imageURL: URL?,
        badgeKey: String?,
        badgeName: String?,
        bookId: String?,
        chapterNumber: Int?,
        deepLink: URL?
    ) {
        self.typeRaw = typeRaw
        self.imageURL = imageURL
        self.badgeKey = badgeKey
        self.badgeName = badgeName
        self.bookId = bookId
        self.chapterNumber = chapterNumber
        self.deepLink = deepLink
    }
}
