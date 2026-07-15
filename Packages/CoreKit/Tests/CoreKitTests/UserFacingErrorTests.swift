import Foundation
import Testing
@testable import CoreKit

@Suite("UserFacingError privacy boundary")
struct UserFacingErrorTests {
    @Test("AppError cases map to closed reviewed categories")
    func mapsClosedCategories() throws {
        #expect(try mapped(.offline).category == .connection)
        #expect(try mapped(.unauthenticated).category == .authentication)
        #expect(try mapped(.reauthRequired).category == .authentication)
        #expect(try mapped(.forbidden).category == .permission)
        #expect(try mapped(.notFound).category == .contentUnavailable)
        #expect(try mapped(.decoding(TestFailure())).category == .unexpectedResponse)
        #expect(try mapped(.verifierUnavailable).category == .serviceUnavailable)
        #expect(try mapped(.rateLimited(retryAfter: 42)).category == .serviceUnavailable)
        #expect(try mapped(.invalidInput("private input")).category == .serviceUnavailable)
        #expect(try mapped(.server(code: "private", message: "private", requestId: nil)).category == .serviceUnavailable)
    }

    @Test("cancellation remains cancellation and is not renderable")
    func cancellationIsNotMapped() {
        #expect(UserFacingError.mapping(CancellationError()) == nil)
    }

    @Test("server and arbitrary errors retain no technical or private text")
    func technicalDetailsAreDiscarded() throws {
        let secretMessage = "token=private-token book=private-book https://example.test/path?user=private"
        let server = try #require(UserFacingError.mapping(AppError.server(
            code: "PRIVATE_SERVER_CODE",
            message: secretMessage,
            requestId: "alice@example.com/private-request"
        )))
        let arbitrary = try #require(UserFacingError.mapping(NSError(
            domain: secretMessage,
            code: 99,
            userInfo: [NSLocalizedDescriptionKey: secretMessage]
        )))

        for rendered in [String(reflecting: server), String(reflecting: arbitrary)] {
            #expect(!rendered.contains("private-token"))
            #expect(!rendered.contains("private-book"))
            #expect(!rendered.contains("example.test"))
            #expect(!rendered.contains("PRIVATE_SERVER_CODE"))
            #expect(!rendered.contains("alice@example.com"))
        }
        #expect(server.requestId == nil)
    }

    @Test("only an allowlisted correlation ID survives")
    func requestIdIsSanitized() throws {
        let safe = "req-observe1234567890"
        let mappedSafe = try #require(UserFacingError.mapping(
            AppError.server(code: "ignored", message: "ignored", requestId: safe)
        ))
        #expect(mappedSafe.requestId == safe)

        let unsafe = [
            "req-shortcode",
            "550e8400-e29b-41d4-a716-446655440000",
            "req-550e8400e29b41d4a716446655440000",
            "req-private/book-id-1234",
        ]
        for requestId in unsafe {
            let error = UserFacingError(category: .serviceUnavailable, requestId: requestId)
            #expect(error.requestId == nil)
            #expect(!String(reflecting: error).contains(requestId))
        }
    }

    @Test("copy and support codes are fixed by category")
    func fixedCopyAndCodes() {
        let compatibility = UserFacingError.compatibility
        #expect(compatibility.title == "Reading Status Unavailable")
        #expect(compatibility.supportCode.rawValue == "CF-BD-COMPAT-001")
        #expect(!compatibility.message.isEmpty)
        #expect(compatibility.recovery == .retry)
    }

    private func mapped(_ error: AppError) throws -> UserFacingError {
        try #require(UserFacingError.mapping(error))
    }
}

private struct TestFailure: Error {}
