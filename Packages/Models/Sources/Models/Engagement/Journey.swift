// MARK: - JourneyCatalogItem

/// A curated multi-book learning path available in the catalog.
///
/// Returned by `GET /book/books/journeys` as part of ``JourneysListResponse``.
public struct JourneyCatalogItem: Codable, Sendable, Identifiable {
    public let journeyId: String
    public let title: String
    public let description: String
    public let durationWeeks: Int
    /// Books in this journey, ordered by their position in the path.
    public let books: [JourneyBookEntry]
    public let completionBadge: JourneyBadge?
    public let bonusFlowPoints: Int?
    public let gradient: JourneyGradient?

    public var id: String { journeyId }

    public init(
        journeyId: String,
        title: String,
        description: String,
        durationWeeks: Int,
        books: [JourneyBookEntry],
        completionBadge: JourneyBadge?,
        bonusFlowPoints: Int?,
        gradient: JourneyGradient?
    ) {
        self.journeyId = journeyId
        self.title = title
        self.description = description
        self.durationWeeks = durationWeeks
        self.books = books
        self.completionBadge = completionBadge
        self.bonusFlowPoints = bonusFlowPoints
        self.gradient = gradient
    }
}

// MARK: - JourneyBookEntry

/// A single book entry within a journey, with its ordering and reason.
public struct JourneyBookEntry: Codable, Sendable, Identifiable {
    public let bookId: String
    public let title: String
    public let author: String?
    public let cover: Cover?
    /// Why this book belongs in the journey, surfaced in the detail view.
    public let reason: String?
    /// 1-based position in the journey sequence.
    public let order: Int

    public var id: String { bookId }

    public init(
        bookId: String,
        title: String,
        author: String?,
        cover: Cover?,
        reason: String?,
        order: Int
    ) {
        self.bookId = bookId
        self.title = title
        self.author = author
        self.cover = cover
        self.reason = reason
        self.order = order
    }
}

// MARK: - JourneyBadge

/// The completion badge awarded when a journey is finished.
public struct JourneyBadge: Codable, Sendable {
    public let badgeId: String
    public let name: String
    public let icon: String?

    public init(badgeId: String, name: String, icon: String?) {
        self.badgeId = badgeId
        self.name = name
        self.icon = icon
    }
}

// MARK: - JourneyGradient

/// A two-stop gradient (hex strings) used for the journey's visual cover.
public struct JourneyGradient: Codable, Sendable {
    public let startColor: String
    public let endColor: String

    public init(startColor: String, endColor: String) {
        self.startColor = startColor
        self.endColor = endColor
    }
}

// MARK: - UserJourney

/// The current user's enrollment and progress on a specific journey.
///
/// Returned by `GET /book/me/journeys/{id}` and
/// `POST /book/me/journeys/{id}/start`.
public struct UserJourney: Codable, Sendable {
    public let journeyId: String
    /// 0-based index of the book the user is currently working on.
    public let currentBookIndex: Int
    public let completedBookIds: [String]
    public let isCompleted: Bool
    public let startedAt: String?
    public let completedAt: String?

    public init(
        journeyId: String,
        currentBookIndex: Int,
        completedBookIds: [String],
        isCompleted: Bool,
        startedAt: String?,
        completedAt: String?
    ) {
        self.journeyId = journeyId
        self.currentBookIndex = currentBookIndex
        self.completedBookIds = completedBookIds
        self.isCompleted = isCompleted
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}
