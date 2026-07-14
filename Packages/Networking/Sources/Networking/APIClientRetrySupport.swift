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
