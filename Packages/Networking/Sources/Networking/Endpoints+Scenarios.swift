import Foundation

// MARK: - Endpoints+Scenarios

/// Endpoint factory methods for the apply-it Scenarios feature.
///
/// `GET|POST /book/me/books/{bookId}/chapters/{n}/scenarios`
public extension Endpoints {

    /// `GET /book/me/books/{bookId}/chapters/{n}/scenarios`
    /// → `{ scenarios: [...], community?: [...] }`.
    static func getScenarios(bookId: String, chapterNumber: Int) -> Endpoint {
        Endpoint(
            method: .get,
            path: "/book/me/books/\(bookId)/chapters/\(chapterNumber)/scenarios",
            requiresAuth: true
        )
    }

    /// `POST /book/me/books/{bookId}/chapters/{n}/scenarios`
    /// → `{ scenario: UserScenario }`.
    ///
    /// Use ``ScenarioPostBody`` to bundle the seven fields that would otherwise
    /// exceed the five-parameter SwiftLint threshold.
    static func postScenario(bookId: String, chapterNumber: Int, body: ScenarioPostBody) throws -> Endpoint {
        try Endpoint(
            method: .post,
            path: "/book/me/books/\(bookId)/chapters/\(chapterNumber)/scenarios",
            body: body
        )
    }
}

// MARK: - ScenarioPostBody

/// The request body for `POST .../scenarios`.
public struct ScenarioPostBody: Encodable, Sendable {
    public let title: String
    public let scenario: String
    public let whatToDo: String
    public let whyItMatters: String
    public let scope: String

    public init(
        title: String,
        scenario: String,
        whatToDo: String,
        whyItMatters: String,
        scope: String
    ) {
        self.title = title
        self.scenario = scenario
        self.whatToDo = whatToDo
        self.whyItMatters = whyItMatters
        self.scope = scope
    }
}
