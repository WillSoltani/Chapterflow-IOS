import Testing
import Foundation
@testable import CoreKit

@Suite("AsyncRetry")
struct AsyncRetryTests {
    /// Thread-safe attempt counter for concurrency-clean tests.
    private actor Counter {
        private(set) var value = 0
        func increment() -> Int { value += 1; return value }
    }

    @Test("retries until success and reports the value")
    func retriesUntilSuccess() async throws {
        let counter = Counter()
        let result = try await withAsyncRetry(
            maxAttempts: 5,
            initialDelay: .milliseconds(1)
        ) {
            let attempt = await counter.increment()
            if attempt < 3 { throw AppError.offline }
            return "ok-\(attempt)"
        }
        #expect(result == "ok-3")
        #expect(await counter.value == 3)
    }

    @Test("gives up after maxAttempts and rethrows")
    func givesUp() async {
        let counter = Counter()
        await #expect(throws: AppError.self) {
            try await withAsyncRetry(maxAttempts: 2, initialDelay: .milliseconds(1)) {
                _ = await counter.increment()
                throw AppError.offline
            }
        }
        #expect(await counter.value == 2)
    }

    @Test("non-retryable errors are not retried")
    func nonRetryable() async {
        let counter = Counter()
        await #expect(throws: AppError.self) {
            try await withAsyncRetry(
                maxAttempts: 5,
                initialDelay: .milliseconds(1),
                shouldRetry: { _ in false }
            ) {
                _ = await counter.increment()
                throw AppError.notFound
            }
        }
        #expect(await counter.value == 1)
    }
}

@Suite("RelativeDate")
struct RelativeDateTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func compact(secondsAgo: Double) -> String {
        RelativeDate.compact(for: now.addingTimeInterval(-secondsAgo), relativeTo: now)
    }

    @Test("compact buckets read as expected")
    func compactBuckets() {
        #expect(compact(secondsAgo: 10) == "now")
        #expect(compact(secondsAgo: 300) == "5m")
        #expect(compact(secondsAgo: 7_200) == "2h")
        #expect(compact(secondsAgo: 259_200) == "3d")
        #expect(compact(secondsAgo: 1_209_600) == "2w")
        #expect(compact(secondsAgo: 5_184_000) == "2mo")
        #expect(compact(secondsAgo: 63_072_000) == "2y")
    }

    @Test("compact is symmetric for future dates")
    func compactFuture() {
        let future = now.addingTimeInterval(7_200)
        #expect(RelativeDate.compact(for: future, relativeTo: now) == "2h")
    }

    @Test("spelled-out string is non-empty")
    func spelledOut() {
        let string = RelativeDate.string(
            for: now.addingTimeInterval(-3_600),
            relativeTo: now,
            locale: Locale(identifier: "en_US")
        )
        #expect(!string.isEmpty)
    }
}

@Suite("Result async helpers")
struct ResultAsyncTests {
    @Test("captures success")
    func success() async {
        let result = await asyncResult { 42 }
        #expect(result.value == 42)
        #expect(result.failure == nil)
    }

    @Test("captures failure")
    func failure() async {
        let result = await asyncResult { throw AppError.offline }
        #expect(result.value == nil)
        #expect(result.failure != nil)
    }

    @Test("onSuccess / onFailure fire selectively")
    func sideEffects() async {
        var successHits = 0
        var failureHits = 0
        await asyncResult { 1 }.onSuccess { _ in successHits += 1 }.onFailure { _ in failureHits += 1 }
        #expect(successHits == 1)
        #expect(failureHits == 0)
    }
}

@Suite("AppLog redaction")
struct AppLogTests {
    @Test("redact masks all but the trailing characters")
    func redactMasks() {
        #expect(AppLog.redact("secret") == "••••••")
        #expect(AppLog.redact("secret", keepingLast: 2) == "••••et")
        #expect(AppLog.redact("") == "")
        #expect(AppLog.redact("ab", keepingLast: 10) == "ab")  // keep clamps to length
    }

    @Test("redactEmail keeps only the domain")
    func redactEmail() {
        #expect(AppLog.redactEmail("jane.doe@example.com") == "••••@example.com")
        // no @ falls back to full masking
        #expect(AppLog.redactEmail("notanemail") == "••••••••••")
    }
}

@MainActor
@Suite("Debouncer")
struct DebouncerTests {
    @Test("only the last call in a burst runs")
    func coalesces() async throws {
        let debouncer = Debouncer(interval: .milliseconds(40))
        var runs = 0
        var lastValue = 0

        for value in 1...5 {
            debouncer.call { runs += 1; lastValue = value }
        }
        try await Task.sleep(for: .milliseconds(150))

        #expect(runs == 1)
        #expect(lastValue == 5)
    }

    @Test("cancel prevents a pending action")
    func cancels() async throws {
        let debouncer = Debouncer(interval: .milliseconds(40))
        var runs = 0
        debouncer.call { runs += 1 }
        debouncer.cancel()
        try await Task.sleep(for: .milliseconds(120))
        #expect(runs == 0)
    }
}
