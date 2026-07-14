import Foundation
import Testing
@testable import CoreKit

struct RouteSanitizationCase: Sendable, CustomTestStringConvertible {
    let input: String
    let expected: String

    var testDescription: String { input }
}

let routeSanitizationCases: [RouteSanitizationCase] = [
    .init(
        input: "/book/books/atomic-habits",
        expected: "/book/books/:id"
    ),
    .init(
        input: "/book/books/atomic-habits/chapters/7",
        expected: "/book/books/:id/chapters/:number"
    ),
    .init(
        input: "/book/me/gifts/private-code",
        expected: "/book/me/gifts/:id"
    ),
    .init(
        input: "/book/users/550e8400-e29b-41d4-a716-446655440000/profile",
        expected: "/book/users/:id/profile"
    ),
    .init(
        input: "/book/users/alice@example.com/profile",
        expected: "/book/users/:id/profile"
    ),
    .init(
        input: "/book/me/pairs/accept/PAIR-PRIVATE-9X7K",
        expected: "/book/me/pairs/accept/:id"
    ),
    .init(
        input: "/book/users/alice%40example.com/profile",
        expected: "/book/users/:id/profile"
    ),
    .init(
        input: "/book/%62ooks/private-book-id/chapters/%37",
        expected: "/book/books/:id/chapters/:number"
    ),
    .init(
        input: "/book/books/private-book-id?token=secret#private-fragment",
        expected: "/book/books/:id"
    ),
    .init(input: "/auth/session", expected: "/auth/session"),
    .init(input: "/book/config/ios", expected: "/book/config/ios"),
]

@Suite("API route sanitizer")
struct APIRouteSanitizerTests {
    @Test("reviewed routes retain only safe static vocabulary", arguments: routeSanitizationCases)
    func sanitizesReviewedRoutes(_ testCase: RouteSanitizationCase) {
        #expect(APIRouteSanitizer.sanitize(testCase.input) == testCase.expected)
    }

    @Test("malformed and ambiguous paths fail to the generic route")
    func malformedPathsFailClosed() {
        let malformed = [
            "",
            "book/books/no-leading-slash",
            "/book//books/private-id",
            "/book/books/%ZZ",
            "/book/books/private%2Fidentifier",
            "/book/books/private%252Fidentifier",
            "/book/books/private%00identifier",
        ]

        for path in malformed {
            #expect(APIRouteSanitizer.sanitize(path) == "/unknown")
        }
    }

    @Test("dynamic values that collide with static vocabulary remain private")
    func staticVocabularyCollisionsRemainPrivate() {
        let collisions = [
            "/book/books/profile": "/book/books/:id",
            "/book/users/settings/profile": "/book/users/:id/profile",
            "/book/me/gifts/redeem": "/book/me/gifts/:id",
        ]

        for (path, expected) in collisions {
            #expect(APIRouteSanitizer.sanitize(path) == expected)
        }
    }

    @Test("segment count and input length are bounded")
    func routeBounds() {
        let tooManySegments = "/" + Array(repeating: "book", count: 20).joined(separator: "/")
        let tooLong = "/book/books/" + String(repeating: "private", count: 400)

        #expect(APIRouteSanitizer.sanitize(tooManySegments) == "/unknown")
        #expect(APIRouteSanitizer.sanitize(tooLong) == "/unknown")
    }

    @Test("large query data is discarded before bounded path sanitization")
    func largeQueryIsDiscarded() {
        let secret = String(repeating: "private-token", count: 400)
        let result = APIRouteSanitizer.sanitize("/book/books/private-id?token=\(secret)")

        #expect(result == "/book/books/:id")
        #expect(!result.contains(secret))
    }
}

@Suite("API request observation")
struct APIRequestObservationTests {
    @Test("event construction is typed, bounded, and privacy-safe")
    func eventConstructionIsSafe() {
        let event = APIRequestObservation(
            method: .get,
            route: "/book/books/private-book-id/chapters/7?token=private-token",
            attempt: 1,
            elapsed: .milliseconds(125),
            outcome: .decodingFailure,
            statusCode: 200,
            requestId: "req-observe1234567890",
            retryDisposition: .final
        )

        #expect(event.method == .get)
        #expect(event.route == "/book/books/:id/chapters/:number")
        #expect(event.attempt == 1)
        #expect(event.elapsed == .milliseconds(125))
        #expect(event.outcome == .decodingFailure)
        #expect(event.statusCode == 200)
        #expect(event.requestId == "req-observe1234567890")
        #expect(event.retryDisposition == .final)

        let reflected = String(reflecting: event)
        #expect(!reflected.contains("private-book-id"))
        #expect(!reflected.contains("private-token"))
    }

    @Test("unreviewed method and unsafe request identifier cannot enter the event")
    func unsafeScalarFieldsAreClosed() {
        let event = APIRequestObservation(
            method: APIRequestObservation.Method("PRIVATE-METHOD"),
            route: "/book/users/private-user/profile",
            attempt: -4,
            elapsed: .seconds(-5),
            outcome: .networkFailure,
            statusCode: 999,
            requestId: "alice@example.com/private-request",
            retryDisposition: .final
        )

        #expect(event.method == .unknown)
        #expect(event.route == "/book/users/:id/profile")
        #expect(event.attempt == 1)
        #expect(event.elapsed == .zero)
        #expect(event.statusCode == nil)
        #expect(event.requestId == nil)

        let reflected = String(reflecting: event)
        #expect(!reflected.contains("PRIVATE-METHOD"))
        #expect(!reflected.contains("private-user"))
        #expect(!reflected.contains("alice@example.com"))
        #expect(!reflected.contains("private-request"))
    }

    @Test("UUID and code-shaped request identifiers fail closed")
    func unsafeRequestIdentifiersFailClosed() {
        let unsafeRequestIds = [
            "550e8400-e29b-41d4-a716-446655440000",
            "PAIR-PRIVATE-9X7K",
            "req-shortcode",
            "req-550e8400-e29b-41d4-a716-446655440000",
            "req-550e8400e29b41d4a716446655440000",
        ]

        for requestId in unsafeRequestIds {
            let event = APIRequestObservation(
                method: .get,
                route: "/book/books/private-book-id",
                attempt: 1,
                elapsed: .milliseconds(1),
                outcome: .httpFailure,
                statusCode: 500,
                requestId: requestId,
                retryDisposition: .final
            )

            #expect(event.requestId == nil)
            #expect(!String(reflecting: event).contains(requestId))
        }
    }
}
