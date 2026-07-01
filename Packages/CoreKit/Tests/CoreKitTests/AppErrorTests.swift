import Testing
import Foundation
@testable import CoreKit

@Suite("AppError")
struct AppErrorTests {
    @Test("every case has a non-empty user-facing description")
    func allCasesHaveMessages() {
        let cases: [AppError] = [
            .unauthenticated,
            .reauthRequired,
            .verifierUnavailable,
            .rateLimited(retryAfter: nil),
            .rateLimited(retryAfter: 30),
            .forbidden,
            .offline,
            .invalidInput("Title is required."),
            .notFound,
            .server(code: "E_SERVER", message: "Boom", requestId: "req-1"),
            .decoding(DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: "x")))
        ]
        for error in cases {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
        }
    }

    @Test("rate limited surfaces the retry-after seconds")
    func rateLimitedMessage() {
        let message = AppError.rateLimited(retryAfter: 30).errorDescription ?? ""
        #expect(message.contains("30"))
    }

    @Test("invalid input echoes its message verbatim")
    func invalidInputMessage() {
        let message = AppError.invalidInput("Email looks off.").errorDescription
        #expect(message == "Email looks off.")
    }

    @Test("server error prefers the server message, falls back when empty")
    func serverMessage() {
        #expect(AppError.server(code: "X", message: "Downstream failed", requestId: nil).errorDescription == "Downstream failed")
        let fallback = AppError.server(code: "X", message: "", requestId: nil).errorDescription ?? ""
        #expect(!fallback.isEmpty)
    }

    @Test("code is stable and non-empty for each case")
    func codes() {
        #expect(AppError.unauthenticated.code == "unauthenticated")
        #expect(AppError.rateLimited(retryAfter: nil).code == "rate_limited")
        #expect(AppError.server(code: "E_CUSTOM", message: "m", requestId: nil).code == "E_CUSTOM")
        #expect(AppError.server(code: "", message: "m", requestId: nil).code == "server")
        #expect(AppError.decoding(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))).code == "decoding")
    }

    @Test("auth failures are flagged")
    func authFlags() {
        #expect(AppError.unauthenticated.isAuthenticationFailure)
        #expect(AppError.reauthRequired.isAuthenticationFailure)
        #expect(!AppError.offline.isAuthenticationFailure)
    }

    @Test("retryable classification")
    func retryable() {
        #expect(AppError.offline.isRetryable)
        #expect(AppError.rateLimited(retryAfter: 1).isRetryable)
        #expect(!AppError.notFound.isRetryable)
        #expect(!AppError.invalidInput("x").isRetryable)
    }
}
