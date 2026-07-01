import Foundation
import CoreKit

/// The authentication hook the ``APIClient`` uses to obtain and refresh the
/// Cognito `id_token`.
///
/// `Networking` owns only this protocol; the concrete implementation
/// (Keychain-backed token store + Cognito refresh) lives in `AuthKit` and is
/// injected into the client. This keeps the networking layer free of any
/// auth-provider specifics and trivially testable with a fake.
public protocol TokenProviding: Sendable {
    /// Returns the current, presumed-valid `id_token`, or `nil` if the user is
    /// not authenticated. The client injects it as `Authorization: Bearer <token>`.
    func validToken() async throws -> String?

    /// Forces a token refresh (e.g. after the server rejects the current token
    /// with `401 unauthenticated`). After this returns, `validToken()` should
    /// yield the newly minted token.
    func refresh() async throws

    /// Performs step-up authentication when the server returns `reauth_required`.
    ///
    /// The `APIClient` suspends the in-flight request here until the provider
    /// signals completion or cancellation. On success the client retries the
    /// original request transparently; on failure it throws `.unauthenticated`.
    func stepUp() async throws

    /// Called when the client encounters a persistent non-recoverable session
    /// error (e.g. the Cognito verifier is unavailable after all retries).
    /// The provider can update app-wide state without interrupting the session.
    func reportSessionError(_ error: AppError) async
}
