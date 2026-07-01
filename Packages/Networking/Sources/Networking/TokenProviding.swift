import Foundation

/// The authentication hook the ``APIClient`` uses to obtain and refresh the
/// Cognito `id_token`.
///
/// `Networking` deliberately owns only this *protocol*; the concrete
/// implementation (Keychain-backed token store + Cognito refresh) lives in
/// `AuthKit` and is injected into the client. This keeps the networking layer
/// free of any auth-provider specifics and trivially testable with a fake.
public protocol TokenProviding: Sendable {
    /// Returns the current, presumed-valid `id_token`, or `nil` if the user is
    /// not authenticated. The client injects it as `Authorization: Bearer <token>`.
    func validToken() async throws -> String?

    /// Forces a token refresh (e.g. after the server rejects the current token
    /// with `401 unauthenticated`). After this returns, ``validToken()`` should
    /// yield the newly minted token.
    func refresh() async throws
}
