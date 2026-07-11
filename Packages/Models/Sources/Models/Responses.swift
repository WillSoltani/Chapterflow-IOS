/// Top-level response wrappers matching the API's success envelope shapes.
/// Success bodies are raw JSON objects, not nested under a generic wrapper.

/// Decodes the `books` array lossily — one malformed book is dropped and
/// logged while the rest of the catalog survives.
public struct CatalogResponse: Codable, Sendable {
    public let books: [BookCatalogItem]

    private enum CodingKeys: String, CodingKey { case books }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.books = try container.decodeLossy(BookCatalogItem.self, forKey: .books)
    }
}

// MARK: - Library

/// Per-book reading progress summary for the Home "Continue Reading" rail.
/// Returned by `GET /book/me/progress`.
///
/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed route's entries carry `completedChapters` (an array of chapter
/// numbers, from which the count is derived), no `totalChapters`, and
/// `lastOpenedAt`/`lastActiveAt`/`updatedAt` instead of `lastReadAt`. All are
/// accepted; encoding stays canonical.
public struct ProgressOverviewItem: Codable, Sendable, Identifiable {
    public let bookId: String
    public let currentChapterNumber: Int
    /// 0 when the server omits totals (deployed shape) — join with the
    /// catalog's `chapterCount` for display fractions in that case.
    public let totalChapters: Int
    public let completedChapterCount: Int
    /// ISO-8601 timestamp of the user's last reading session for this book.
    public let lastReadAt: String?

    public var id: String { bookId }

    /// 0…1 fraction of chapters completed.
    public var completionFraction: Double {
        guard totalChapters > 0 else { return 0 }
        return Double(completedChapterCount) / Double(totalChapters)
    }

    /// Like `completionFraction`, but falls back to `totalChapterHint`
    /// (e.g. the catalog's `chapterCount`) when the server omitted totals.
    public func completionFraction(totalChapterHint: Int?) -> Double {
        let total = totalChapters > 0 ? totalChapters : (totalChapterHint ?? 0)
        guard total > 0 else { return 0 }
        return min(1, Double(completedChapterCount) / Double(total))
    }

    public init(
        bookId: String,
        currentChapterNumber: Int,
        totalChapters: Int,
        completedChapterCount: Int,
        lastReadAt: String?
    ) {
        self.bookId = bookId
        self.currentChapterNumber = currentChapterNumber
        self.totalChapters = totalChapters
        self.completedChapterCount = completedChapterCount
        self.lastReadAt = lastReadAt
    }

    private enum WireKeys: String, CodingKey {
        case bookId
        case currentChapterNumber, totalChapters
        case completedChapterCount, completedChapters
        case lastReadAt, lastOpenedAt, lastActiveAt, updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        bookId = try c.decodeRequiredFirst(String.self, keys: [.bookId])
        currentChapterNumber = c.decodeFirst(Int.self, keys: [.currentChapterNumber]) ?? 1
        totalChapters = c.decodeFirst(Int.self, keys: [.totalChapters]) ?? 0
        if let count = c.decodeFirst(Int.self, keys: [.completedChapterCount]) {
            completedChapterCount = count
        } else if let completed = c.decodeFirst([Int].self, keys: [.completedChapters]) {
            completedChapterCount = completed.count
        } else {
            completedChapterCount = 0
        }
        lastReadAt = c.decodeFirst(
            String.self, keys: [.lastReadAt, .lastOpenedAt, .lastActiveAt, .updatedAt])
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: WireKeys.self)
        try c.encode(bookId, forKey: .bookId)
        try c.encode(currentChapterNumber, forKey: .currentChapterNumber)
        try c.encode(totalChapters, forKey: .totalChapters)
        try c.encode(completedChapterCount, forKey: .completedChapterCount)
        try c.encodeIfPresent(lastReadAt, forKey: .lastReadAt)
    }
}

/// Response wrapper for `GET /book/me/progress`.
/// Decodes the array lossily — one malformed item is dropped and logged while
/// the rest of the collection survives.
///
/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed route returns `{"summary": …, "books": […]}`; the canonical
/// shape is `{"progress": […]}`. Both decode; encoding stays canonical.
public struct ProgressOverviewResponse: Codable, Sendable {
    public let progress: [ProgressOverviewItem]

    public init(progress: [ProgressOverviewItem]) {
        self.progress = progress
    }

    private enum CodingKeys: String, CodingKey { case progress, books }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.progress) {
            self.progress = try container.decodeLossy(ProgressOverviewItem.self, forKey: .progress)
        } else if container.contains(.books) {
            self.progress = try container.decodeLossy(ProgressOverviewItem.self, forKey: .books)
        } else {
            self.progress = []
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(progress, forKey: .progress)
    }
}

/// Saved (bookmarked) book IDs for the current user.
/// Returned by `GET /book/me/saved` and `POST /book/me/saved`.
///
/// ## Wire-shape tolerance (contract reconciliation)
/// The deployed route responds `{"saved": [{"bookId": …, …}], "savedBookIds": […]}`
/// (`savedBookIds` was added 2026-07-11; before that the route sent only
/// `saved`, and the strict decode of it errored Home/Library on device).
/// Canonical `savedBookIds` wins when present; otherwise the ids derive from
/// `saved[].bookId` (lossily — rows without a bookId are dropped); a body with
/// neither key decodes as empty. Encoding stays canonical.
public struct SavedBooksResponse: Codable, Sendable {
    public let savedBookIds: [String]

    public init(savedBookIds: [String]) {
        self.savedBookIds = savedBookIds
    }

    private enum CodingKeys: String, CodingKey { case savedBookIds, saved }

    private struct SavedRow: Decodable {
        let bookId: String?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let ids = container.decodeFirst([String].self, keys: [.savedBookIds]) {
            self.savedBookIds = ids
        } else if let rows = container.decodeFirst(LossyArray<SavedRow>.self, keys: [.saved]) {
            self.savedBookIds = rows.elements.compactMap { $0.bookId }
        } else {
            self.savedBookIds = []
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(savedBookIds, forKey: .savedBookIds)
    }
}

public struct ChapterResponse: Codable, Sendable {
    public let chapter: Chapter
    public let progress: BookProgress

    public init(chapter: Chapter, progress: BookProgress) {
        self.chapter = chapter
        self.progress = progress
    }
}

public struct QuizResponse: Codable, Sendable {
    public let quiz: QuizClientSession
    public let progress: BookProgress

    public init(quiz: QuizClientSession, progress: BookProgress) {
        self.quiz = quiz
        self.progress = progress
    }
}

public struct EntitlementResponse: Codable, Sendable {
    public let entitlement: Entitlement
    public let paywall: Paywall?

    public init(entitlement: Entitlement, paywall: Paywall?) {
        self.entitlement = entitlement
        self.paywall = paywall
    }
}

public struct BookStateResponseEnvelope: Codable, Sendable {
    public let state: BookUserBookState
    public let applicationStates: [String: ChapterApplicationState]?
}

// MARK: - Flow-Points Shop

/// Response wrapper for `GET /book/me/shop`.
///
/// Decodes `items` lossily so one malformed shop item never corrupts the list.
public struct ShopResponse: Codable, Sendable {
    public let items: [ShopItem]

    public init(items: [ShopItem]) {
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case items }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try container.decodeLossy(ShopItem.self, forKey: .items)
    }
}

// MARK: - Journeys

/// Response from `GET /book/books/journeys`.
/// Decodes the `journeys` array lossily — one malformed journey is dropped and
/// logged while the rest of the collection survives.
public struct JourneysListResponse: Codable, Sendable {
    public let journeys: [JourneyCatalogItem]

    public init(journeys: [JourneyCatalogItem]) {
        self.journeys = journeys
    }

    private enum CodingKeys: String, CodingKey { case journeys }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.journeys = try container.decodeLossy(JourneyCatalogItem.self, forKey: .journeys)
    }
}

/// Response from `GET /book/me/journeys/{id}` and `POST /book/me/journeys/{id}/start`.
public struct UserJourneyResponse: Codable, Sendable {
    public let journey: UserJourney

    public init(journey: UserJourney) {
        self.journey = journey
    }
}

/// Response from `POST /book/me/flow-points/redeem`.
///
/// The server is authoritative: reflect this state in the UI, never grant locally.
public struct RedeemFlowPointsResponse: Codable, Sendable {
    /// Updated balance after the redemption.
    public let balance: Int
    /// The item that was redeemed/equipped, reflecting its new `isOwned` and `isEquipped` state.
    public let item: ShopItem?
    /// Updated equipped cosmetics after an equip action.
    public let equippedCosmetics: EquippedCosmetics?

    public init(balance: Int, item: ShopItem?, equippedCosmetics: EquippedCosmetics?) {
        self.balance = balance
        self.item = item
        self.equippedCosmetics = equippedCosmetics
    }
}
