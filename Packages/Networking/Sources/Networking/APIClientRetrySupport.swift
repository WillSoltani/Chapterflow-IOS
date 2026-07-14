import Foundation

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
}
