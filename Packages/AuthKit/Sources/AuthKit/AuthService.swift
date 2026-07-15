@preconcurrency import Amplify
import AWSCognitoAuthPlugin
import CoreKit
import Foundation
import Persistence

/// Amplify-backed authentication operations.
///
/// `AuthService` proves session evidence but never publishes app auth state and
/// never writes the token mirror. `SessionManager` is the only lifecycle
/// authority and the only production mirror writer.
@MainActor
public final class AuthService {
    let tokenStore: any TokenStoring

    private let config: AppConfig
    private let sessionClient: any CognitoSessionClient

    public init(config: AppConfig, tokenStore: (any TokenStoring)? = nil) {
        self.config = config
        self.tokenStore = tokenStore ?? TokenStore()
        self.sessionClient = AmplifyCognitoSessionClient()
    }

    init(
        config: AppConfig,
        tokenStore: any TokenStoring,
        sessionClient: any CognitoSessionClient
    ) {
        self.config = config
        self.tokenStore = tokenStore
        self.sessionClient = sessionClient
    }

    /// Configures the one Amplify/Cognito session implementation.
    public func configure() throws {
        try AmplifyConfigurator.configure(with: config)
    }

    public func signUp(
        username: String,
        password: String,
        email: String,
        name: String? = nil
    ) async throws -> SignUpStep {
        do {
            var attributes = [AuthUserAttribute(.email, value: email)]
            if let name, !name.isEmpty {
                attributes.append(AuthUserAttribute(.name, value: name))
            }
            let options = AuthSignUpRequest.Options(userAttributes: attributes)
            let result = try await Amplify.Auth.signUp(
                username: username,
                password: password,
                options: options
            )
            return result.isSignUpComplete ? .done : .confirmationRequired
        } catch let error as AuthError {
            throw mapAmplifyError(error)
        }
    }

    public func confirmSignUp(username: String, code: String) async throws {
        do {
            _ = try await Amplify.Auth.confirmSignUp(
                for: username,
                confirmationCode: code
            )
        } catch let error as AuthError {
            throw mapAmplifyError(error)
        }
    }

    public func resendCode(username: String) async throws {
        do {
            _ = try await Amplify.Auth.resendSignUpCode(for: username)
        } catch let error as AuthError {
            throw mapAmplifyError(error)
        }
    }

    public func forgotPassword(username: String) async throws {
        do {
            _ = try await Amplify.Auth.resetPassword(for: username)
        } catch let error as AuthError {
            throw mapAmplifyError(error)
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
        } catch let error as AuthError {
            throw mapAmplifyError(error)
        }
    }

    /// The previous native authorization-code exchange created credentials
    /// outside Amplify and could not be restored or refreshed by the app's
    /// authoritative session. Apple remains unavailable until WP-AUTH-01B
    /// provides the signed provider, callback, linking, and revocation proof.
    public func signInWithApple(
        authorizationCode _: Data,
        name _: PersonNameComponents?
    ) async throws {
        throw AuthProviderError.unavailable(.apple)
    }

    // MARK: - Session operations consumed only by SessionManager

    func signIn(username: String, password: String) async throws -> VerifiedSession {
        do {
            switch try await sessionClient.signIn(username: username, password: password) {
            case .signedIn:
                return try await requireVerifiedSession(forceRefresh: false)
            case .resetPassword:
                throw AppError.invalidInput("Your password must be reset before signing in.")
            case .additionalStepRequired:
                throw AppError.server(
                    code: "sign_in_step_required",
                    message: "An additional step is required to complete sign-in.",
                    requestId: nil
                )
            }
        } catch {
            throw mapSessionError(error)
        }
    }

    func restoreSession() async throws -> VerifiedSession? {
        do {
            let snapshot = try await sessionClient.fetchSession(forceRefresh: false)
            guard snapshot.isSignedIn else { return nil }
            return try await verify(snapshot)
        } catch {
            throw mapSessionError(error)
        }
    }

    func refreshSession() async throws -> VerifiedSession {
        do {
            return try await requireVerifiedSession(forceRefresh: true)
        } catch {
            throw mapSessionError(error)
        }
    }

    func signOut() async -> CognitoSignOutOutcome {
        await sessionClient.signOut()
    }

    private func requireVerifiedSession(forceRefresh: Bool) async throws -> VerifiedSession {
        let snapshot = try await sessionClient.fetchSession(forceRefresh: forceRefresh)
        guard snapshot.isSignedIn else { throw AppError.unauthenticated }
        return try await verify(snapshot)
    }

    private func verify(_ snapshot: CognitoSessionSnapshot) async throws -> VerifiedSession {
        guard snapshot.isSignedIn, let tokens = snapshot.tokens,
              let tokenExpiry = cognitoTokenExpiry(from: tokens.idToken),
              tokenExpiry > Date(),
              abs(tokenExpiry.timeIntervalSince(tokens.expiresAt)) < 1,
              let profile = UserProfile.from(idToken: tokens.idToken),
              let tokenIdentity = SessionIdentity(
                  subject: profile.sub,
                  username: nil,
                  email: profile.email,
                  source: .cognitoUserPool
              ) else {
            throw AppError.unauthenticated
        }

        let currentUser = try await sessionClient.currentUser()
        guard let identity = SessionIdentity(
            subject: currentUser.userId,
            username: currentUser.username,
            email: currentUser.email ?? (profile.email.isEmpty ? nil : profile.email),
            source: .cognitoUserPool
        ), identity.subject == tokenIdentity.subject else {
            throw AppError.unauthenticated
        }

        return VerifiedSession(identity: identity, tokens: tokens)
    }
}

private func mapSessionError(_ error: Error) -> Error {
    if let appError = error as? AppError { return appError }
    if let providerError = error as? AuthProviderError { return providerError }
    if let authError = error as? AuthError { return mapAmplifyError(authError) }
    if error is CancellationError { return CancellationError() }
    return AppError.unauthenticated
}

func mapAmplifyError(_ error: AuthError) -> AppError {
    switch error {
    case .notAuthorized:
        return .invalidInput("The email or password is incorrect.")
    case .sessionExpired:
        return .reauthRequired
    case .signedOut:
        return .unauthenticated
    case .service(_, _, let underlying):
        let description = underlying?.localizedDescription ?? ""
        if description.contains("UserNotFoundException") || description.contains("User does not exist") {
            return .notFound
        }
        if description.contains("LimitExceededException") || description.contains("TooManyRequestsException") {
            return .rateLimited(retryAfter: nil)
        }
        if description.contains("CodeMismatchException") {
            return .invalidInput("The verification code is incorrect. Please try again.")
        }
        if description.contains("ExpiredCodeException") {
            return .invalidInput("The verification code has expired. Please request a new one.")
        }
        if description.contains("UsernameExistsException") {
            return .invalidInput("An account with this email already exists.")
        }
        if description.contains("UserNotConfirmedException") {
            return .invalidInput("Please verify your email before signing in.")
        }
        return .server(
            code: "auth_service",
            message: "We couldn't complete sign-in. Please try again.",
            requestId: nil
        )
    case .validation:
        return .invalidInput("Check your sign-in details and try again.")
    case .configuration:
        return .server(
            code: "amplify_config",
            message: "Sign-in is temporarily unavailable.",
            requestId: nil
        )
    default:
        return .server(
            code: "auth_error",
            message: "We couldn't complete sign-in. Please try again.",
            requestId: nil
        )
    }
}
