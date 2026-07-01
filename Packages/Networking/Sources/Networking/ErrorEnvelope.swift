import Foundation
import CoreKit

/// The error envelope shape the API returns on any non-2xx response:
/// `{ "error": { "code", "message", "requestId", "details"? } }`.
struct APIErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
        let requestId: String?
        let details: Details?

        private enum CodingKeys: String, CodingKey {
            case code, message, requestId, details
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = (try? container.decodeIfPresent(String.self, forKey: .code)) ?? ""
            message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
            requestId = try? container.decodeIfPresent(String.self, forKey: .requestId)
            // `details` is free-form on the wire; decode the one field we care
            // about defensively so a non-object payload never fails the decode.
            details = try? container.decodeIfPresent(Details.self, forKey: .details)
        }
    }

    /// The subset of `details` the client acts on.
    struct Details: Decodable {
        let reauth: Bool?
    }

    let error: Body
}

/// Maps an HTTP error response (status + decoded envelope + headers) to the
/// canonical `AppError`. This is the single source of truth for turning server
/// error codes into typed client errors.
enum ErrorMapper {
    /// - Parameters:
    ///   - status: the HTTP status code (guaranteed non-2xx by the caller).
    ///   - data: the raw response body; decoded as an `APIErrorEnvelope` when possible.
    ///   - retryAfter: the parsed `Retry-After` header value in seconds, if any.
    static func map(status: Int, data: Data, retryAfter: TimeInterval?) -> AppError {
        let envelope = try? JSONCoding.decoder.decode(APIErrorEnvelope.self, from: data)
        let code = envelope?.error.code ?? ""
        let message = envelope?.error.message ?? ""
        let requestId = envelope?.error.requestId
        let reauth = envelope?.error.details?.reauth ?? false

        switch status {
        case 401:
            // A valid-but-stale token asks for a fresh login; a missing/invalid
            // token just routes to sign-in.
            if reauth || code == "reauth_required" {
                return .reauthRequired
            }
            return .unauthenticated
        case 403:
            // Includes `forbidden_origin` (the web CSRF guard) and any other 403.
            return .forbidden
        case 404:
            return .notFound
        case 429:
            return .rateLimited(retryAfter: retryAfter)
        case 503 where code == "verifier_unavailable":
            return .verifierUnavailable
        case 400 where code.hasPrefix("invalid"):
            // `invalid_*` validation errors — surface the server's message.
            return .invalidInput(message.isEmpty ? "The request was invalid." : message)
        default:
            return .server(code: code, message: message, requestId: requestId)
        }
    }
}
