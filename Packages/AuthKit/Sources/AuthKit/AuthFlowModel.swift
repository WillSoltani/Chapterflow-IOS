import SwiftUI
import AuthenticationServices
import CoreKit
import Observation

// MARK: - Auth Route

public enum AuthRoute: Hashable, Sendable {
    case signUp
    case logIn
    case verifyEmail
    case forgotPassword
}

// MARK: - Password Strength

public struct PasswordStrength: Equatable, Sendable {
    public let level: Level

    public enum Level: Int, Sendable {
        case weak = 0, fair, strong, veryStrong
    }

    public var fraction: Double {
        Double(level.rawValue + 1) / 4.0
    }

    public var label: String {
        switch level {
        case .weak:       return "Weak"
        case .fair:       return "Fair"
        case .strong:     return "Strong"
        case .veryStrong: return "Very strong"
        }
    }

    public var color: Color {
        switch level {
        case .weak:       return .red
        case .fair:       return .orange
        case .strong:     return .yellow
        case .veryStrong: return .green
        }
    }

    /// Evaluates password strength from character composition and length.
    public static func evaluate(_ password: String) -> PasswordStrength {
        let length = password.count
        guard length >= 6 else { return PasswordStrength(level: .weak) }

        let hasUppercase  = password.contains(where: \.isUppercase)
        let hasLowercase  = password.contains(where: \.isLowercase)
        let hasDigit      = password.contains(where: \.isNumber)
        let hasSpecial    = password.contains(where: { "!@#$%^&*()_+-=[]{}|;':\",./<>?".contains($0) })
        let mixCount = [hasUppercase, hasLowercase, hasDigit, hasSpecial].filter { $0 }.count

        if length >= 12 && mixCount >= 3 { return PasswordStrength(level: .veryStrong) }
        if length >= 8  && mixCount >= 2 { return PasswordStrength(level: .strong) }
        return PasswordStrength(level: .fair)
    }
}

// MARK: - AuthFlowModel

/// Navigation and form state for the auth flow.
///
/// `AuthFlowModel` is intentionally decoupled from `SessionManager` — it only
/// knows about `AuthService` (Amplify operations). `SessionManager` observes
/// the same `authEvents` stream and updates `authState` independently.
@Observable
@MainActor
public final class AuthFlowModel {

    // MARK: - Navigation

    public var navigationPath: [AuthRoute] = []

    // MARK: - Guest browse mode

    /// Optional context string set when the flow is triggered from an auth gate
    /// (e.g. "Sign up free to start reading"). `WelcomeView` renders it as a
    /// contextual prompt above the sign-in buttons.
    public var gateContext: String? = nil

    /// Called when the user taps "Browse without account" on `WelcomeView`.
    /// Wired by `AppRootView` to `AppModel.enterGuestMode()`.
    public var onBrowseAsGuest: (() -> Void)?

    // MARK: - Loading / feedback

    public var isLoading = false
    public var toastMessage: String? = nil
    public var toastIsError = false

    // MARK: - Sign-up form

    public var signUpEmail = ""
    public var signUpPassword = ""
    public var signUpName = ""
    public var signUpPasswordStrength: PasswordStrength = PasswordStrength(level: .weak)

    // MARK: - Log-in form

    public var logInEmail = ""
    public var logInPassword = ""

    // MARK: - Verify-email form

    public var verifyCode = ""
    /// The username (email) whose verification code was just sent.
    public var pendingUsername = ""

    // MARK: - Forgot-password form

    public var forgotEmail = ""
    public var resetCode = ""
    public var resetNewPassword = ""
    public var isResetCodeSent = false

    private let authService: AuthService

    public init(authService: AuthService, gateContext: String? = nil) {
        self.authService = authService
        self.gateContext = gateContext
    }

    // MARK: - Navigation helpers

    public func navigate(to route: AuthRoute) {
        navigationPath.append(route)
    }

    public func popToRoot() {
        navigationPath = []
    }

    // MARK: - Sign up

    public func performSignUp() {
        Task { await _signUp() }
    }

    private func _signUp() async {
        guard !signUpEmail.isEmpty, !signUpPassword.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let step = try await authService.signUp(
                username: signUpEmail,
                password: signUpPassword,
                email: signUpEmail,
                name: signUpName.isEmpty ? nil : signUpName
            )
            pendingUsername = signUpEmail
            switch step {
            case .confirmationRequired:
                navigationPath.append(.verifyEmail)
            case .done:
                // Auto sign-in if pool skips verification
                try await authService.signIn(username: signUpEmail, password: signUpPassword)
            }
        } catch {
            showToast(userMessage(for: error), isError: true)
        }
    }

    // MARK: - Confirm email

    public func performConfirmEmail() {
        Task { await _confirmEmail() }
    }

    private func _confirmEmail() async {
        guard verifyCode.count == 6 else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.confirmSignUp(username: pendingUsername, code: verifyCode)
            // Auto sign-in after verification so the user lands directly in the app.
            try await authService.signIn(username: pendingUsername, password: signUpPassword)
        } catch {
            showToast(userMessage(for: error), isError: true)
        }
    }

    public func performResendCode() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                try await authService.resendCode(username: pendingUsername)
                showToast("Code resent to \(pendingUsername).", isError: false)
            } catch {
                showToast(userMessage(for: error), isError: true)
            }
        }
    }

    // MARK: - Log in

    public func performLogIn() {
        Task { await _logIn() }
    }

    private func _logIn() async {
        guard !logInEmail.isEmpty, !logInPassword.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.signIn(username: logInEmail, password: logInPassword)
            // On success, authService emits .signedIn → SessionManager → AppRootView switches.
        } catch {
            showToast(userMessage(for: error), isError: true)
        }
    }

    // MARK: - Forgot password

    public func performForgotPasswordRequest() {
        Task {
            guard !forgotEmail.isEmpty else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                try await authService.forgotPassword(username: forgotEmail)
                isResetCodeSent = true
            } catch {
                showToast(userMessage(for: error), isError: true)
            }
        }
    }

    public func performConfirmPasswordReset() {
        Task {
            guard !resetCode.isEmpty, !resetNewPassword.isEmpty else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                try await authService.confirmForgotPassword(
                    username: forgotEmail,
                    newPassword: resetNewPassword,
                    code: resetCode
                )
                showToast("Password reset. Please log in.", isError: false)
                popToRoot()
                // Navigate to log-in with email pre-filled
                logInEmail = forgotEmail
                navigate(to: .logIn)
            } catch {
                showToast(userMessage(for: error), isError: true)
            }
        }
    }

    // MARK: - Sign in with Apple

    public func performSignInWithApple(_ result: Result<ASAuthorization, Error>) {
        Task { await _signInWithApple(result) }
    }

    private func _signInWithApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            showToast("Sign in failed. Please try again.", isError: true)

        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let authCodeData = credential.authorizationCode
            else {
                showToast("Could not complete sign in. Please try again.", isError: true)
                return
            }

            // Persist name on first sign-in (Apple only discloses once).
            if let comps = credential.fullName {
                let name = PersonNameComponentsFormatter()
                    .string(from: comps)
                    .trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    UserDefaults.standard.set(name, forKey: "chapterflow.displayName")
                }
            }

            isLoading = true
            defer { isLoading = false }
            do {
                try await authService.signInWithApple(
                    authorizationCode: authCodeData,
                    name: credential.fullName
                )
            } catch {
                showToast(userMessage(for: error), isError: true)
            }
        }
    }

    // MARK: - Reactive helpers

    /// Updates `signUpPasswordStrength` — call from `onChange(of: signUpPassword)`.
    public func updatePasswordStrength() {
        signUpPasswordStrength = PasswordStrength.evaluate(signUpPassword)
    }

    // MARK: - Validation

    public nonisolated static func isValidEmail(_ email: String) -> Bool {
        let regex = /^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$/
        return email.wholeMatch(of: regex) != nil
    }

    // MARK: - Private helpers

    private func showToast(_ message: String, isError: Bool) {
        toastMessage = message
        toastIsError = isError
        Task {
            try? await Task.sleep(for: .seconds(4))
            if toastMessage == message { toastMessage = nil }
        }
    }

    private func userMessage(for error: Error) -> String {
        (error as? AppError)?.errorDescription
            ?? error.localizedDescription
    }
}
