#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - ForgotPasswordRequestView

/// Step 1: Enter email to receive a password-reset code.
public struct ForgotPasswordRequestView: View {
    @Bindable var model: AuthFlowModel

    public init(model: AuthFlowModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .cfSpacing24) {
                // Header
                VStack(alignment: .leading, spacing: .cfSpacing8) {
                    Text("Reset password")
                        .font(.cfLargeTitle)
                        .foregroundStyle(Color.cfLabel)
                    Text("Enter your email and we'll send you a reset code.")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .multilineTextAlignment(.leading)
                }
                .padding(.top, .cfSpacing8)

                AuthTextField(
                    label: "Email",
                    placeholder: "you@example.com",
                    text: $model.forgotEmail,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress
                )

                Spacer(minLength: .cfSpacing40)

                CFPrimaryButton(
                    label: "Send Reset Code",
                    isLoading: model.isLoading
                ) {
                    Task { await model.performForgotPasswordRequest() }
                }
                .accessibilityHint("Send a password-reset code to your email address.")
            }
            .padding(.horizontal, .cfSpacing24)
            .padding(.bottom, .cfSpacing32)
        }
        .background(Color.cfBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .cfToast(model.toastMessage)
    }
}

// MARK: - ForgotPasswordResetView

/// Step 2: Enter the reset code and choose a new password.
public struct ForgotPasswordResetView: View {
    @Bindable var model: AuthFlowModel
    let username: String

    public init(model: AuthFlowModel, username: String) {
        self.model = model
        self.username = username
    }

    private var strength: PasswordStrength { model.passwordStrength(model.resetNewPassword) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .cfSpacing24) {
                // Header
                VStack(alignment: .leading, spacing: .cfSpacing8) {
                    Text("Create new password")
                        .font(.cfLargeTitle)
                        .foregroundStyle(Color.cfLabel)
                    Text("Enter the code sent to **\(username)**.")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .multilineTextAlignment(.leading)
                }
                .padding(.top, .cfSpacing8)

                // Fields
                VStack(spacing: .cfSpacing16) {
                    AuthTextField(
                        label: "Reset Code",
                        placeholder: "6-digit code",
                        text: $model.resetCode,
                        keyboardType: .numberPad,
                        textContentType: .oneTimeCode
                    )

                    VStack(spacing: .cfSpacing8) {
                        AuthSecureField(
                            label: "New Password",
                            placeholder: "At least 8 characters",
                            text: $model.resetNewPassword,
                            textContentType: .newPassword
                        )
                        if !model.resetNewPassword.isEmpty {
                            PasswordStrengthBar(strength: strength)
                                .padding(.horizontal, .cfSpacing4)
                        }
                    }
                }

                Spacer(minLength: .cfSpacing40)

                CFPrimaryButton(
                    label: "Reset Password",
                    isLoading: model.isLoading
                ) {
                    Task { await model.performConfirmPasswordReset() }
                }
                .accessibilityHint("Submit the code and your new password to complete the reset.")
            }
            .padding(.horizontal, .cfSpacing24)
            .padding(.bottom, .cfSpacing32)
        }
        .background(Color.cfBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .cfToast(model.toastMessage)
    }
}

// MARK: - Previews

#Preview("Forgot Password — Request") {
    NavigationStack {
        ForgotPasswordRequestView(model: AuthFlowModel(authService: previewAuthService()))
    }
}

#Preview("Forgot Password — Reset") {
    let m = AuthFlowModel(authService: previewAuthService())
    m.forgotEmail = "jane@example.com"
    return NavigationStack {
        ForgotPasswordResetView(model: m, username: "jane@example.com")
    }
}

#Preview("Forgot Password — Reset with strength") {
    let m = AuthFlowModel(authService: previewAuthService())
    m.resetNewPassword = "Hunter2!"
    return NavigationStack {
        ForgotPasswordResetView(model: m, username: "jane@example.com")
    }
}
#endif
