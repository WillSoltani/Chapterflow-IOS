import SwiftUI
import CoreKit

// MARK: - PasswordStrength

/// Simple heuristic password-strength scorer.
public struct PasswordStrength: Sendable {
    public let score: Int  // 0–4

    public var label: String {
        switch score {
        case 0, 1: return "Weak"
        case 2:    return "Fair"
        case 3:    return "Good"
        default:   return "Strong"
        }
    }

    public var fractionComplete: Double { Double(max(0, min(4, score))) / 4.0 }

    public var color: Color {
        switch score {
        case 0, 1: return .red
        case 2:    return .orange
        case 3:    return .yellow
        default:   return .green
        }
    }

    public static func evaluate(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else { return PasswordStrength(score: 0) }
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.contains(where: { $0.isUppercase }) { score += 1 }
        if password.contains(where: { $0.isNumber }) { score += 1 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { score += 1 }
        return PasswordStrength(score: score)
    }
}

// MARK: - AuthFlowModel

/// Observable model driving the entire auth navigation flow.
///
/// Owns all form state, navigation path, and async operations for sign-up,
/// log-in, email verification, and forgot-password. Injected into each auth
/// screen as a single source of truth.
@Observable
@MainActor
public final class AuthFlowModel {

    // MARK: - Screen enum

    public enum Screen: Hashable {
        case signUp
        case verifyEmail(email: String)
        case logIn
        case forgotPasswordRequest
        case forgotPasswordReset(username: String)
    }

    // MARK: - Navigation

    public var navigationPath: NavigationPath = NavigationPath()

    // MARK: - Loading / Toast

    public var isLoading: Bool = false
    public var toastMessage: String? = nil

    // MARK: - Sign-Up form

    public var signUpName: String = ""
    public var signUpEmail: String = ""
    public var signUpPassword: String = ""

    // MARK: - Verify Email

    public var verifyCode: String = ""
    public var resendSecondsRemaining: Int = 0

    // MARK: - Log In

    public var loginEmail: String = ""
    public var loginPassword: String = ""

    // MARK: - Forgot Password

    public var forgotEmail: String = ""
    public var resetCode: String = ""
    public var resetNewPassword: String = ""

    // MARK: - Private state

    /// The email/username being verified (set during sign-up or failed log-in).
    private var pendingEmail: String = ""
    /// The password last used during sign-up — needed to auto-sign-in after confirmation.
    private var pendingPassword: String = ""
    /// Whether the pending verification was triggered by sign-up (vs. unconfirmed login).
    private var isSignUpVerification: Bool = true

    private var resendTimerTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?

    // MARK: - Dependencies

    public let authService: AuthService

    // MARK: - Init

    public init(authService: AuthService) {
        self.authService = authService
    }

    // MARK: - Navigation helpers

    public func navigateTo(_ screen: Screen) {
        navigationPath.append(screen)
    }

    public func goBack() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    // MARK: - Sign-Up

    public func performSignUp() async {
        guard validate(name: signUpName, email: signUpEmail, password: signUpPassword) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let step = try await authService.signUp(
                username: signUpEmail,
                password: signUpPassword,
                email: signUpEmail,
                name: signUpName
            )
            if step == .confirmationRequired {
                pendingEmail = signUpEmail
                pendingPassword = signUpPassword
                isSignUpVerification = true
                verifyCode = ""
                startResendTimer()
                navigateTo(.verifyEmail(email: signUpEmail))
            }
            // .done: auth state updates automatically via AuthService
        } catch {
            showError(error)
        }
    }

    // MARK: - Email Verification

    public func performConfirmEmail() async {
        guard !verifyCode.isEmpty else {
            showToast("Please enter the 6-digit code.")
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.confirmSignUp(username: pendingEmail, code: verifyCode)
            // Auto-sign-in after confirmation
            let password = isSignUpVerification ? pendingPassword : loginPassword
            try await authService.signIn(username: pendingEmail, password: password)
        } catch let err as AppError {
            // If sign-in after confirmation fails due to unconfirmed (shouldn't happen, but guard)
            if case .invalidInput(let msg) = err, msg.lowercased().contains("verify") {
                showError(err)
            } else {
                showError(err)
            }
        } catch {
            showError(error)
        }
    }

    public func performResendCode() async {
        guard resendSecondsRemaining == 0 else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.resendCode(username: pendingEmail)
            showToast("A new code was sent to \(pendingEmail).")
            startResendTimer()
        } catch {
            showError(error)
        }
    }

    // MARK: - Log In

    public func performLogIn() async {
        guard !loginEmail.isEmpty, !loginPassword.isEmpty else {
            showToast("Please enter your email and password.")
            return
        }
        guard isValidEmail(loginEmail) else {
            showToast("Please enter a valid email address.")
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.signIn(username: loginEmail, password: loginPassword)
        } catch let err as AppError {
            if case .invalidInput(let msg) = err, msg.lowercased().contains("verify") {
                // Account not yet confirmed — route to verification
                pendingEmail = loginEmail
                pendingPassword = loginPassword
                isSignUpVerification = false
                verifyCode = ""
                startResendTimer()
                navigateTo(.verifyEmail(email: loginEmail))
            } else {
                showError(err)
            }
        } catch {
            showError(error)
        }
    }

    // MARK: - Forgot Password

    public func performForgotPasswordRequest() async {
        guard !forgotEmail.isEmpty, isValidEmail(forgotEmail) else {
            showToast("Please enter a valid email address.")
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.forgotPassword(username: forgotEmail)
            pendingEmail = forgotEmail
            navigateTo(.forgotPasswordReset(username: forgotEmail))
        } catch {
            showError(error)
        }
    }

    public func performConfirmPasswordReset() async {
        guard !resetCode.isEmpty else {
            showToast("Please enter the reset code.")
            return
        }
        let strength = PasswordStrength.evaluate(resetNewPassword)
        guard strength.score >= 2 else {
            showToast("Please choose a stronger password.")
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.confirmForgotPassword(
                username: pendingEmail,
                newPassword: resetNewPassword,
                code: resetCode
            )
            loginEmail = pendingEmail
            loginPassword = ""
            // Pop back to the log-in screen (remove forgotPasswordReset + forgotPasswordRequest)
            while !navigationPath.isEmpty {
                navigationPath.removeLast()
            }
            navigateTo(.logIn)
            showToast("Password reset! Please sign in.")
        } catch {
            showError(error)
        }
    }

    // MARK: - Validation helpers

    public func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    public func passwordStrength(_ password: String) -> PasswordStrength {
        PasswordStrength.evaluate(password)
    }

    // MARK: - Private helpers

    private func validate(name: String, email: String, password: String) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast("Please enter your name.")
            return false
        }
        guard isValidEmail(email) else {
            showToast("Please enter a valid email address.")
            return false
        }
        guard PasswordStrength.evaluate(password).score >= 2 else {
            showToast("Please choose a stronger password (at least Fair strength).")
            return false
        }
        return true
    }

    private func startResendTimer() {
        resendSecondsRemaining = 60
        resendTimerTask?.cancel()
        resendTimerTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                if self.resendSecondsRemaining > 0 {
                    self.resendSecondsRemaining -= 1
                } else {
                    break
                }
            }
        }
    }

    private func showError(_ error: Error) {
        let message = (error as? AppError)?.errorDescription ?? error.localizedDescription
        showToast(message)
    }

    private func showToast(_ message: String) {
        toastMessage = message
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }
}
