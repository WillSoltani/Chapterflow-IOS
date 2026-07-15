import Foundation
import CoreKit

struct APIClientObservationAttempt {
    let number: Int
    let started: ContinuousClock.Instant
    let context: APIObservationContext
}

struct APIClientRetryState {
    var backoffAttempt = 0
    var didRefreshToken = false
    var didStepUp = false
}

enum APIClientTransportAttemptResult {
    case response(Data, HTTPURLResponse)
    case retry(nextBackoffAttempt: Int)
}

enum APIClientTerminalTransportFailurePolicy {
    case mapToOffline
    case preserveURLError
}

struct APIClientTransportRetryPlan {
    let backoffAttempt: Int
    let retryLimit: Int
    let terminalFailurePolicy: APIClientTerminalTransportFailurePolicy
}

struct APIClientSuccessfulHTTPAttempt {
    let data: Data
    let response: HTTPURLResponse
    let request: URLRequest
    let observation: APIClientObservationAttempt
}

struct APIClientEmptyResponseBodyError: Error {}

enum APIClientRetryPreparation {
    case refreshToken
    case stepUp
    case backoff(Int)
}

struct APIClientFailedHTTPAttempt {
    let request: URLRequest
    let number: Int
    let elapsed: Duration
    let statusCode: Int
    let requestId: String?
    let observationContext: APIObservationContext
}

extension APIClient {
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        guard let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)),
              seconds.isFinite,
              seconds >= 0 else {
            return nil
        }
        return seconds
    }

    static func serverDate(from response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "Date") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.timeZone = TimeZone(identifier: "GMT")
        return formatter.date(from: value)
    }

    static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .networkConnectionLost,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    func elapsedSince(_ started: ContinuousClock.Instant) -> Duration {
        started.duration(to: observationNow())
    }

    func recordObservation(
        request: URLRequest,
        observation: APIClientObservationAttempt,
        outcome: APIRequestObservation.Outcome,
        statusCode: Int? = nil,
        requestId: String? = nil,
        retryDisposition: APIRequestObservation.RetryDisposition = .final
    ) {
        recordObservation(
            request: request,
            attempt: observation.number,
            elapsed: elapsedSince(observation.started),
            outcome: outcome,
            statusCode: statusCode,
            requestId: requestId,
            retryDisposition: retryDisposition,
            context: observation.context
        )
    }

    func recordObservation(
        request: URLRequest,
        attempt: Int,
        elapsed: Duration,
        outcome: APIRequestObservation.Outcome,
        statusCode: Int? = nil,
        requestId: String? = nil,
        retryDisposition: APIRequestObservation.RetryDisposition = .final,
        context: APIObservationContext
    ) {
        observer.record(
            APIRequestObservation(
                method: APIRequestObservation.Method(request.httpMethod),
                route: request.url?.path ?? APIRouteSanitizer.unknownRoute,
                attempt: attempt,
                elapsed: elapsed,
                outcome: outcome,
                statusCode: statusCode,
                requestId: requestId,
                retryDisposition: retryDisposition
            ),
            context: context
        )
    }

    func extractRequestId(from data: Data) -> String? {
        let envelope = try? JSONCoding.decoder.decode(APIErrorEnvelope.self, from: data)
        return envelope?.error.requestId
    }
}
