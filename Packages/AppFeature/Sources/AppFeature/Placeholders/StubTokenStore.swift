import Foundation
import Networking

/// A trivial, in-memory `TokenProviding` used to boot the app before real auth
/// exists.
///
/// > Placeholder: the production token store (Keychain-backed, App-Group shared)
/// > lands with **Persistence (P0.4)** and the Cognito refresh logic with
/// > **AuthKit (P1)**. Both conform to `Networking.TokenProviding`, so swapping
/// > this out is a one-line change in ``Dependencies/live()``.
///
/// It seeds a non-empty placeholder token by default so the app launches
/// straight into the tab shell (there is no sign-in screen to satisfy yet). The
/// stubbed `AuthFlowView` uses ``set(_:)`` to toggle the signed-in state.
public actor StubTokenStore: TokenProviding {
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func validToken() async throws -> String? {
        token
    }

    public func refresh() async throws {
        // No real refresh yet; AuthKit (P1) implements this against Cognito.
    }

    /// Sets or clears the current token (used by the stubbed auth flow).
    public func set(_ token: String?) {
        self.token = token
    }
}
