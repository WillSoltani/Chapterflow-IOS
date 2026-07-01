#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// Log-in screen with email and password fields plus a forgot-password link.
public struct LogInView: View {
    @Bindable var model: AuthFlowModel

    public init(model: AuthFlowModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .cfSpacing24) {
                // Header
                VStack(alignment: .leading, spacing: .cfSpacing8) {
                    Text("Welcome back")
                        .font(.cfLargeTitle)
                        .foregroundStyle(Color.cfLabel)
                    Text("Sign in to continue reading.")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
                .padding(.top, .cfSpacing8)

                // Form fields
                VStack(spacing: .cfSpacing16) {
                    AuthTextField(
                        label: "Email",
                        placeholder: "you@example.com",
                        text: $model.loginEmail,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress
                    )

                    AuthSecureField(
                        label: "Password",
                        placeholder: "Your password",
                        text: $model.loginPassword,
                        textContentType: .password
                    )
                }

                // Forgot password link — right-aligned
                HStack {
                    Spacer()
                    CFTextButton(label: "Forgot password?") {
                        model.navigateTo(.forgotPasswordRequest)
                    }
                    .accessibilityHint("Start the password-reset flow.")
                }

                Spacer(minLength: .cfSpacing40)

                CFPrimaryButton(
                    label: "Log In",
                    isLoading: model.isLoading
                ) {
                    Task { await model.performLogIn() }
                }
                .accessibilityHint("Sign in to your ChapterFlow account.")
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

#Preview("Log In — Idle") {
    NavigationStack {
        LogInView(model: AuthFlowModel(authService: previewAuthService()))
    }
}

#Preview("Log In — Loading") {
    let m = AuthFlowModel(authService: previewAuthService())
    m.loginEmail = "jane@example.com"
    m.loginPassword = "Hunter2!"
    m.isLoading = true
    return NavigationStack { LogInView(model: m) }
}

#Preview("Log In — Error") {
    let m = AuthFlowModel(authService: previewAuthService())
    m.loginEmail = "jane@example.com"
    m.toastMessage = "Incorrect email or password."
    return NavigationStack { LogInView(model: m) }
}
#endif
