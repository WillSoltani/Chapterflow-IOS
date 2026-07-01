#if os(iOS)
import SwiftUI

/// Two-step forgot-password flow:
/// 1. Enter email → request a reset code (Cognito sends an email).
/// 2. Enter the code + new password → confirm the reset.
///
/// Both steps live in this single view driven by `model.isResetCodeSent`.
public struct ForgotPasswordView: View {
    @Bindable var model: AuthFlowModel

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if model.isResetCodeSent {
                    resetStep
                } else {
                    requestStep
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.isResetCodeSent = false }
    }

    // MARK: - Step 1: request

    private var requestStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("Forgot Password?")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)

                Text("Enter your email and we'll send a reset code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            AuthTextField(
                "Email",
                text: $model.forgotEmail,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never
            )

            CFPrimaryButton("Send Reset Code", isLoading: model.isLoading) {
                model.performForgotPasswordRequest()
            }
            .disabled(!AuthFlowModel.isValidEmail(model.forgotEmail) || model.isLoading)
        }
    }

    // MARK: - Step 2: reset

    private var resetStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("Enter Reset Code")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)

                Text("Check your email for the 6-digit code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            VerificationCodeField(code: $model.resetCode)

            AuthSecureField(
                "New password",
                text: $model.resetNewPassword,
                textContentType: .newPassword
            )

            CFPrimaryButton("Reset Password", isLoading: model.isLoading) {
                model.performConfirmPasswordReset()
            }
            .disabled(
                model.resetCode.count < 6
                    || model.resetNewPassword.count < 8
                    || model.isLoading
            )

            CFTextButton("Resend code") {
                model.performForgotPasswordRequest()
            }
            .disabled(model.isLoading)
        }
    }
}

#Preview("Forgot Password — request") {
    NavigationStack {
        ForgotPasswordView(model: AuthFlowModel(authService: previewAuthService()))
    }
}

#Preview("Forgot Password — reset") {
    let m = AuthFlowModel(authService: previewAuthService())
    NavigationStack {
        ForgotPasswordView(model: m)
            .onAppear {
                m.forgotEmail = "you@example.com"
                m.isResetCodeSent = true
            }
    }
}
#endif // os(iOS)
