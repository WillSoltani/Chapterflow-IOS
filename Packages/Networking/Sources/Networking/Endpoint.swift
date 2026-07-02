import Foundation

/// The HTTP methods the API uses.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

/// A value-type description of a single API request, resolved against
/// `AppConfig.apiBaseURL` by the ``APIClient``.
///
/// `Endpoint` is `Sendable`: any request body is encoded to `Data` at
/// construction time (via ``JSONCoding``), so the value can cross actor
/// boundaries freely.
public struct Endpoint: Sendable, Equatable {
    /// The HTTP method.
    public let method: HTTPMethod
    /// The path appended to the API base URL, e.g. `/book/books`. Must begin
    /// with a leading slash.
    public let path: String
    /// Query items appended to the URL. Empty when there are none.
    public let query: [URLQueryItem]
    /// The pre-encoded JSON request body, or `nil` for bodyless requests.
    public let httpBody: Data?
    /// Whether the request must carry `Authorization: Bearer <id_token>`.
    public let requiresAuth: Bool

    /// Creates an endpoint with an already-encoded (or absent) body.
    public init(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        httpBody: Data? = nil,
        requiresAuth: Bool = true
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.httpBody = httpBody
        self.requiresAuth = requiresAuth
    }

    /// Creates an endpoint, encoding the given `Encodable` body with the shared
    /// ``JSONCoding/encoder``.
    public init<Body: Encodable>(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        body: Body,
        requiresAuth: Bool = true
    ) throws {
        self.init(
            method: method,
            path: path,
            query: query,
            httpBody: try JSONCoding.encoder.encode(body),
            requiresAuth: requiresAuth
        )
    }
}

/// A namespaced factory for the endpoints the app consumes. Feature packages
/// add more as they come online; this seed set covers the foundational flows.
///
/// Paths follow the catalog in `docs/PLAN.md` §3.3. Content GETs that the server
/// serves publicly (e.g. the book catalog) are marked `requiresAuth: false`.
public enum Endpoints {
    /// `GET /auth/session` → `{ loggedIn, user }`.
    public static func getSession() -> Endpoint {
        Endpoint(method: .get, path: "/auth/session", requiresAuth: true)
    }

    /// `GET /book/books` → `{ books: [...] }` (public, cacheable).
    public static func getBooks() -> Endpoint {
        Endpoint(method: .get, path: "/book/books", requiresAuth: false)
    }

    /// `GET /book/books/{bookId}` → book detail + manifest.
    public static func getBook(id: String) -> Endpoint {
        Endpoint(method: .get, path: "/book/books/\(id)", requiresAuth: true)
    }

    /// `GET /book/books/{bookId}/chapters/{n}` → `{ chapter, progress }`.
    /// - Parameter mode: an optional reading-depth variant (`?mode=`).
    public static func getChapter(bookId: String, n: Int, mode: String? = nil) -> Endpoint {
        Endpoint(
            method: .get,
            path: "/book/books/\(bookId)/chapters/\(n)",
            query: mode.map { [URLQueryItem(name: "mode", value: $0)] } ?? [],
            requiresAuth: true
        )
    }

    /// `GET /book/books/{bookId}/chapters/{n}/quiz` → `{ quiz, progress }`.
    /// - Parameter tone: an optional tone preference (`?tone=`).
    public static func getQuiz(bookId: String, n: Int, tone: String? = nil) -> Endpoint {
        Endpoint(
            method: .get,
            path: "/book/books/\(bookId)/chapters/\(n)/quiz",
            query: tone.map { [URLQueryItem(name: "tone", value: $0)] } ?? [],
            requiresAuth: true
        )
    }

    /// `GET /book/me/entitlements` → `{ entitlement, paywall }`.
    public static func getEntitlements() -> Endpoint {
        Endpoint(method: .get, path: "/book/me/entitlements", requiresAuth: true)
    }

    /// `GET /book/me/progress` → `{ progress: [...] }` — per-book reading progress overview.
    public static func getProgressOverview() -> Endpoint {
        Endpoint(method: .get, path: "/book/me/progress", requiresAuth: true)
    }

    /// `GET /book/me/saved` → `{ savedBookIds: [...] }` — the user's saved book IDs.
    public static func getSavedBooks() -> Endpoint {
        Endpoint(method: .get, path: "/book/me/saved", requiresAuth: true)
    }

    /// `POST /book/me/saved` → `{ savedBookIds: [...] }` — toggle a book's saved state.
    public static func toggleSaved(bookId: String, saved: Bool) throws -> Endpoint {
        struct Body: Encodable { let bookId: String; let saved: Bool }
        return try Endpoint(method: .post, path: "/book/me/saved",
                            body: Body(bookId: bookId, saved: saved))
    }

    /// `GET /book/me/books/{bookId}/state` → `{ state, applicationStates }`.
    public static func getBookState(bookId: String) -> Endpoint {
        Endpoint(method: .get, path: "/book/me/books/\(bookId)/state", requiresAuth: true)
    }

    /// `POST /book/me/books/{bookId}/start` — start/own a book (consumes a free slot or requires Pro).
    public static func startBook(bookId: String) throws -> Endpoint {
        struct Body: Encodable {}
        return try Endpoint(method: .post, path: "/book/me/books/\(bookId)/start", body: Body())
    }

    // MARK: - Engagement

    /// `GET /book/me/dashboard` → `{ dashboard: { ... } }`.
    public static func getDashboard() -> Endpoint {
        Endpoint(method: .get, path: "/book/me/dashboard", requiresAuth: true)
    }

    /// `GET /book/me/streak` → `{ streak: { ... } }`.
    public static func getStreak() -> Endpoint {
        Endpoint(method: .get, path: "/book/me/streak", requiresAuth: true)
    }

    /// `GET /book/me/flow-points` → `{ balance: Int }`.
    public static func getFlowPoints() -> Endpoint {
        Endpoint(method: .get, path: "/book/me/flow-points", requiresAuth: true)
    }

    /// `GET /book/me/badges` → `{ badges: [...] }`.
    public static func getBadges() -> Endpoint {
        Endpoint(method: .get, path: "/book/me/badges", requiresAuth: true)
    }
}
