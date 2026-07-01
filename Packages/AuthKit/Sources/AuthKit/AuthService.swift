@preconcurrency import Amplify
@preconcurrency import AWSPluginsCore
import AWSCognitoAuthPlugin
import CoreKit
import Persistence
import Observation
import Foundation

// MARK: - TokenRefreshing

/// Abstraction for forcing a Cognito token refresh. Injected into
/// `AuthTokenProvider` so the refresh path can be tested without Amplify.
public protocol TokenRefreshing: Sendable {
    func performRefresh() async throws -> StoredTokens
}

// MARK: - AuthService

/// The main authentication service. Wraps Amplify Auth and acts as the source
/// of truth for `AuthState`. Must be created and used on the `@MainActor`.
@MainActor
@Observable
public final class AuthService: TokenRefreshing {

    // MARK: Public API

    public private(set) var authState: AuthState = .unknown
    public let authEvents: AsyncStream<AuthEvent>

    // MARK: Internal (accessible to AuthTokenProvider)

    let tokenStore: any TokenStoring

    // MARK: Private

    private let config: AppConfig
    private let eventsContinuation: AsyncStream<AuthEvent>.Continuation

    // MARK: Init

    public init(config: AppConfig, tokenStore: (any TokenStoring)? = nil) {
        self.config = config
        self.tokenStore = tokenStore ?? TokenStore()
        (authEvents, eventsContinuation) = AsyncStream.makeStream(
            of: AuthEvent.self,
            bufferingPolicy: .bufferingNewest(32)
        )
    }

    deinit {
        eventsContinuation.finish()
    }

    // MARK: - Lifecycle

    /// Configures Amplify and resolves the initial auth state. Call once at app launch.
    public func configure() throws {
        try AmplifyConfigurator.configure(with: config)
        Task { [weak self] in await self?.syncAuthState() }
    }

    // MARK: - Auth Operations

    /// Creates a new Cognito user. Returns `.confirmationRequired` when email
    /// verification is needed (the typical path).
    public func signUp(
        username: String,
        password: String,
        email: String
    ) async throws -> SignUpStep {
        do {
            let opts = AuthSignUpRequest.Options(
                userAttributes: [AuthUserAttribute(.email, value: email)]
            )
            let result = try await Amplify.Auth.signUp(
                username: username,
                password: password,
                options: opts
            )
            return result.isSignUpComplete ? .done : .confirmationRequired
        } catch let err as AuthError {
            throw mapAuthError(err)
        }
    }

    /// Confirms sign-up using the verification code sent to the user's email.
    public func confirmSignUp(username: String, code: String) async throws {
        do {
            _ = try await Amplify.Auth.confirmSignUp(
                for: username,
                confirmationCode: code
            )
        } catch let err as AuthError {
            throw mapAuthError(err)
        }
    }

    /// Resends the verification code to the given username.
    public func resendCode(username: String) async throws {
        do {
            _ = try await Amplify.Auth.resendSignUpCode(for: username)
        } catch let err as AuthError {
            throw mapAuthError(err)
        }
    }

    /// Signs in and updates `authState` to `.signedIn` on success.
    /// Throws an `AppError` on failure (wrong credentials, unconfirmed user, etc.).
    public func signIn(username: String, password: String) async throws {
        do {
            let result = try await Amplify.Auth.signIn(
                username: username,
                password: password
            )
            guard result.isSignedIn else {
                // MFA / password-reset step — surface a typed error for the UI.
                switch result.nextStep {
                case .resetPassword:
                    throw AppError.invalidInput("Your password must be reset before signing in.")
                default:
                    throw AppError.server(
                        code: "sign_in_step_required",
                        message: "An additional step is required to complete sign-in.",
                        requestId: nil
                    )
                }
            }
            try await handleSuccessfulAuth()
        } catch let err as AuthError {
            throw mapAuthError(err)
        }
    }

    /// Signs out locally and clears the stored tokens.
    public func signOut() async {
        _ = await Amplify.Auth.signOut()
        try? tokenStore.delete()
        authState = .signedOut
        eventsContinuation.yield(.signedOut)
    }

    /// Initiates a password-reset flow (sends a verification code to the user's email).
    public func forgotPassword(username: String) async throws {
        do {
            _ = try await Amplify.Auth.resetPassword(for: username)
        } catch let err as AuthError {
            throw mapAuthError(err)
        }
    }

    /// Completes the password-reset flow.
    public func confirmForgotPassword(
        username: String,
        newPassword: String,
        code: String
    ) async throws {
        do {
            try await Amplify.Auth.confirmResetPassword(
                for: username,
                with: newPassword,
                confirmationCode: code
            )
        } catch let err as AuthError {
            throw mapAuthError(err)
        }
    }

    // MARK: - TokenRefreshing

    /// Forces a Cognito token refresh and persists the new tokens. Called by
    /// `AuthTokenProvider` when the id_token is near expiry.
    public func performRefresh() async throws -> StoredTokens {
        do {
            let session = try await Amplify.Auth.fetchAuthSession(
                options: AuthFetchSessionRequest.Options(forceRefresh: true)
            )
            let tokens = try Self.extractTokens(from: session)
            try tokenStore.save(tokens)
            eventsContinuation.yield(.tokenRefreshed)
            return tokens
        } catch let err as AuthError {
            throw mapAuthError(err)
        }
    }

    // MARK: - Private Helpers

    private func syncAuthState() async {
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            if session.isSignedIn, let tokens = try? Self.extractTokens(from: session) {
                try? tokenStore.save(tokens)
                let user = (try? await fetchUserSummary()) ?? UserSummary(
                    userId: "",
                    username: "",
                    email: nil
                )
                authState = .signedIn(user)
                return
            }
        } catch {}
        try? tokenStore.delete()
        authState = .signedOut
    }

    private func handleSuccessfulAuth() async throws {
        let session = try await Amplify.Auth.fetchAuthSession()
        let tokens = try Self.extractTokens(from: session)
        try tokenStore.save(tokens)
        let user = try await fetchUserSummary()
        authState = .signedIn(user)
        eventsContinuation.yield(.signedIn(user))
    }

    private func fetchUserSummary() async throws -> UserSummary {
        do {
            let user = try await Amplify.Auth.getCurrentUser()
            return UserSummary(userId: user.userId, username: user.username, email: nil)
        } catch {
            throw AppError.unauthenticated
        }
    }

    // MARK: - Token Extraction

    /// Extracts tokens from an `AuthSession` returned by Amplify and decodes
    /// the JWT `exp` claim to determine the accurate expiry date.
    static func extractTokens(from session: AuthSession) throws -> StoredTokens {
        guard let provider = session as? AuthCognitoTokensProvider else {
            throw AppError.unauthenticated
        }
        let amplifyTokens = try provider.getCognitoTokens()
            .mapError { mapAmplifyError($0) }
            .get()

        let expiresAt = jwtExpiry(from: amplifyTokens.idToken)
            ?? Date().addingTimeInterval(3_600)

        return StoredTokens(
            idToken: amplifyTokens.idToken,
            accessToken: amplifyTokens.accessToken,
            refreshToken: amplifyTokens.refreshToken,
            expiresAt: expiresAt
        )
    }

    // MARK: - JWT Expiry

    /// Decodes the `exp` claim from a JWT without verifying the signature.
    private static func jwtExpiry(from token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
        let rem = payload.count % 4
        if rem != 0 { payload += String(repeating: "=", count: 4 - rem) }
        guard
            let data = Data(base64Encoded: payload),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let exp = json["exp"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

// MARK: - Error Mapping

private func mapAuthError(_ error: AuthError) -> AppError {
    mapAmplifyError(error)
}

func mapAmplifyError(_ error: AuthError) -> AppError {
    switch error {
    case .notAuthorized(let msg, _, _):
        return .invalidInput(msg)
    case .sessionExpired:
        return .reauthRequired
    case .signedOut:
        return .unauthenticated
    case .service(let msg, _, let underlying):
        // Map known Cognito exception names to typed errors.
        let desc = underlying?.localizedDescription ?? msg
        if desc.contains("UserNotFoundException") || desc.contains("User does not exist") {
            return .notFound
        }
        if desc.contains("LimitExceededException") || desc.contains("TooManyRequestsException") {
            return .rateLimited(retryAfter: nil)
        }
        if desc.contains("CodeMismatchException") {
            return .invalidInput("The verification code is incorrect. Please try again.")
        }
        if desc.contains("ExpiredCodeException") {
            return .invalidInput("The verification code has expired. Please request a new one.")
        }
        if desc.contains("UsernameExistsException") {
            return .invalidInput("An account with this email already exists.")
        }
        if desc.contains("UserNotConfirmedException") {
            return .invalidInput("Please verify your email before signing in.")
        }
        return .invalidInput(msg)
    case .validation(_, let msg, _, _):
        return .invalidInput(msg)
    case .configuration(let msg, _, _):
        return .server(code: "amplify_config", message: msg, requestId: nil)
    default:
        return .server(code: "auth_error", message: error.errorDescription, requestId: nil)
    }
}
