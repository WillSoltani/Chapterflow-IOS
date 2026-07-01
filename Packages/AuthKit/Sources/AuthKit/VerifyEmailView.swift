#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// Email verification screen: 6-digit OTP entry with resend countdown.
public struct VerifyEmailView: View {
    @Bindable var model: AuthFlowModel
    let email: String

    public init(model: AuthFlowModel, email: String) {
        self.model = model
        self.email = email
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: .cfSpacing24) {
                    // Header
                    VStack(alignment: .leading, spacing: .cfSpacing8) {
                        Text("Check your email")
                            .font(.cfLargeTitle)
                            .foregroundStyle(Color.cfLabel)
                        Text("We sent a 6-digit code to\n**\(email)**")
                            .font(.cfSubheadline)
                            .foregroundStyle(Color.cfSecondaryLabel)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.top, .cfSpacing8)

                    // Code entry
                    VerificationCodeField(code: $model.verifyCode) { _ in
                        Task { await model.performConfirmEmail() }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, .cfSpacing8)

                    Spacer(minLength: .cfSpacing40)
                }
                .padding(.horizontal, .cfSpacing24)
            }

            // Bottom action area — pinned above keyboard
            VStack(spacing: .cfSpacing16) {
                CFPrimaryButton(
                    label: "Verify",
                    isLoading: model.isLoading,
                    isEnabled: model.verifyCode.count == 6
                ) {
                    Task { await model.performConfirmEmail() }
                }
                .accessibilityHint("Confirm the 6-digit code and complete verification.")

                resendButton
            }
            .padding(.horizontal, .cfSpacing24)
            .padding(.bottom, .cfSpacing32)
            .padding(.top, .cfSpacing16)
        }
        .background(Color.cfBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .cfToast(model.toastMessage)
    }

    @ViewBuilder
    private var resendButton: some View {
        if model.resendSecondsRemaining > 0 {
            Text("Resend in \(model.resendSecondsRemaining)s")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
                .frame(minHeight: 44)
                .accessibilityLabel("Resend code available in \(model.resendSecondsRemaining) seconds")
        } else {
            HStack(spacing: .cfSpacing4) {
                Text("Didn't receive a code?")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                CFTextButton(label: "Resend") {
                    Task { await model.performResendCode() }
                }
                .accessibilityHint("Send a new verification code to \(email).")
            }
        }
    }
}

// MARK: - Previews

#Preview("Verify Email — Idle") {
    NavigationStack {
        VerifyEmailView(
            model: AuthFlowModel(authService: previewAuthService()),
            email: "jane@example.com"
        )
    }
}

#Preview("Verify Email — Countdown") {
    let m = AuthFlowModel(authService: previewAuthService())
    m.resendSecondsRemaining = 45
    return NavigationStack {
        VerifyEmailView(model: m, email: "jane@example.com")
    }
}

#Preview("Verify Email — Error") {
    let m = AuthFlowModel(authService: previewAuthService())
    m.toastMessage = "The verification code is incorrect. Please try again."
    return NavigationStack {
        VerifyEmailView(model: m, email: "jane@example.com")
    }
}
#endif
