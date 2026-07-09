@preconcurrency import Amplify
@preconcurrency import AWSPluginsCore
import AWSCognitoAuthPlugin
import AuthenticationServices
import CoreKit
import Persistence
import Observation
import Foundation

/// The Amplify-based auth operations engine.
///
/// `AuthService` wraps all Cognito/Amplify operations and emits discrete events
/// via `authEvents` so `SessionManager` can observe state changes.
/// It is separate from `SessionManager` so the auth-flow UI (`AuthFlowModel`)
/// can drive sign-up/sign-in without coupling to session lifecycle concerns.
///
/// ## Token Ownership — Single Write Path
/// `AuthService` is the **sole writer** of `TokenStore` in production. All writes
/// happen through one of four paths, each triggered by an Amplify auth event:
///
/// | Path | Trigger | Write |
/// |------|---------|-------|
/// | `handleSuccessfulAuth()` | email/password sign-in succeeds | `save` |
/// | `signInWithApple(...)` | Apple credential exchanged | `save` |
/// | `performRefresh()` | Amplify force-refresh completes | `save` |
/// | `syncAuthState()` | app launch, Amplify already signed in | `save` |
/// | `signOut()` | user signs out | `delete` (clears both Amplify AND the mirror) |
///
/// No other component may call `tokenStore.save(_:)`. `AuthTokenProvider` reads the
/// mirror for fast token lookups and calls `performRefresh()` when near-expiry —
/// it does NOT write to the store directly.
@MainActor
@Observable
public final class AuthService: TokenRefreshing {

    // MARK: - Events

    public let authEvents: AsyncStream<AuthEvent>
    private let eventsContinuation: AsyncStream<AuthEvent>.Continuation

    // MARK: - Internal token store (shared with AuthTokenProvider)

    let tokenStore: any TokenStoring

    // MARK: - Private

    private let config: AppConfig

    // MARK: - Init

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

    /// Configures Amplify and resolves the initial auth state.
    /// Call once at app launch via `SessionManager.configure()`.
    public func configure() throws {
        try AmplifyConfigurator.configure(with: config)
        Task { [weak self] in await self?.syncAuthState() }
    }

    // MARK: - Auth Operations

    public func signUp(
        username: String,
        password: String,
        email: String,
        name: String? = nil
    ) async throws -> SignUpStep {
        do {
            var userAttributes = [AuthUserAttribute(.email, value: email)]
            if let name, !name.isEmpty {
                userAttributes.append(AuthUserAttribute(.name, value: name))
            }
            let opts = AuthSignUpRequest.Options(userAttributes: userAttributes)
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

    public func resendCode(username: String) async throws {
        do {
            _ = try await Amplify.Auth.resendSignUpCode(for: username)
        } catch let err as AuthError {
            throw mapAuthError(err)
        }
    }

    public func signIn(username: String, password: String) async throws {
        do {
            let result = try await Amplify.Auth.signIn(
                username: username,
                password: password
            )
            guard result.isSignedIn else {
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

    /// Signs in using a native Sign-in-with-Apple credential.
    /// Exchanges the Apple authorization code with Cognito's hosted-UI token endpoint.
    public func signInWithApple(
        authorizationCode: Data,
        name: PersonNameComponents?
    ) async throws {
        guard !config.cognitoDomain.isEmpty, !config.cognitoClientID.isEmpty else {
            throw AppError.unauthenticated
        }
        guard let codeString = String(data: authorizationCode, encoding: .utf8) else {
            throw AppError.unauthenticated
        }

        let tokenURL = URL(string: "https://\(config.cognitoDomain)/oauth2/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "grant_type": "authorization_code",
            "code": codeString,
            "redirect_uri": "chapterflow://auth/callback",
            "client_id": config.cognitoClientID,
        ]
        request.httpBody = params
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\(percentEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.unauthenticated
        }

        struct TokenResponse: Decodable {
            let id_token: String
            let access_token: String
            let refresh_token: String
            let expires_in: Int?
        }
        let tokenResponse: TokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AppError.decoding(error)
        }

        let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in ?? 3_600))
        let tokens = StoredTokens(
            idToken: tokenResponse.id_token,
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token,
            expiresAt: expiresAt
        )
        try tokenStore.save(tokens)

        // Resolve user summary from Apple name or JWT claims
        let resolvedName: String
        if let comps = name {
            let fmt = PersonNameComponentsFormatter().string(from: comps).trimmingCharacters(in: .whitespaces)
            resolvedName = fmt.isEmpty ? "Reader" : fmt
        } else {
            resolvedName = UserProfile.from(idToken: tokenResponse.id_token)?.displayName ?? "Reader"
        }

        let user = UserSummary(userId: "", username: resolvedName, email: nil)
        eventsContinuation.yield(.signedIn(user))
    }

    public func signOut() async {
        // Clear BOTH copies: Amplify's internal credential storage AND our Keychain mirror.
        // After this, Amplify.Auth.fetchAuthSession() will return isSignedIn == false
        // and tokenStore.load() will return nil. The session is fully wiped.
        _ = await Amplify.Auth.signOut()
        try? tokenStore.delete()
        eventsContinuation.yield(.signedOut)
    }

    public func forgotPassword(username: String) async throws {
        do {
            _ = try await Amplify.Auth.resetPassword(for: username)
        } catch let err as AuthError {
            throw mapAuthError(err)
        }
    }

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
        #if DEBUG
        // In UITest mode, skip Amplify entirely and emit .signedIn immediately.
        // CF_STUB_SERVER intercepts all network calls; no real Cognito session needed.
        if ProcessInfo.processInfo.environment["CF_UITEST_BYPASS_AUTH"] == "1" {
            let user = UserSummary(userId: "uitest-user-123", username: "uitest-user-123", email: nil)
            eventsContinuation.yield(.signedIn(user))
            return
        }
        #endif
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            if session.isSignedIn, let tokens = try? Self.extractTokens(from: session) {
                try? tokenStore.save(tokens)
                let user = (try? await fetchUserSummary()) ?? UserSummary(
                    userId: "", username: "", email: nil
                )
                eventsContinuation.yield(.signedIn(user))
                return
            }
        } catch {}
        try? tokenStore.delete()
        eventsContinuation.yield(.signedOut)
    }

    private func handleSuccessfulAuth() async throws {
        let session = try await Amplify.Auth.fetchAuthSession()
        let tokens = try Self.extractTokens(from: session)
        try tokenStore.save(tokens)
        let user = try await fetchUserSummary()
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

    private func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
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
