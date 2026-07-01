#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// Sign-up form: name, email, password with strength bar.
public struct SignUpView: View {
    @Bindable var model: AuthFlowModel

    public init(model: AuthFlowModel) {
        self.model = model
    }

    private var strength: PasswordStrength { model.passwordStrength(model.signUpPassword) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .cfSpacing24) {
                // Header
                VStack(alignment: .leading, spacing: .cfSpacing8) {
                    Text("Create account")
                        .font(.cfLargeTitle)
                        .foregroundStyle(Color.cfLabel)
                    Text("Start your reading journey.")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
                .padding(.top, .cfSpacing8)

                // Form fields
                VStack(spacing: .cfSpacing16) {
                    AuthTextField(
                        label: "Name",
                        placeholder: "Your name",
                        text: $model.signUpName,
                        textContentType: .name,
                        autocapitalization: .words
                    )

                    AuthTextField(
                        label: "Email",
                        placeholder: "you@example.com",
                        text: $model.signUpEmail,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress
                    )

                    VStack(spacing: .cfSpacing8) {
                        AuthSecureField(
                            label: "Password",
                            placeholder: "At least 8 characters",
                            text: $model.signUpPassword,
                            textContentType: .newPassword
                        )
                        if !model.signUpPassword.isEmpty {
                            PasswordStrengthBar(strength: strength)
                                .padding(.horizontal, .cfSpacing4)
                        }
                    }
                }

                // Terms
                Text("By creating an account, you agree to our Terms of Service and Privacy Policy.")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfTertiaryLabel)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: .cfSpacing40)

                CFPrimaryButton(
                    label: "Create Account",
                    isLoading: model.isLoading
                ) {
                    Task { await model.performSignUp() }
                }
                .accessibilityHint("Submit your details to create a new account.")
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

#Preview("Sign Up — Idle") {
    NavigationStack {
        SignUpView(model: AuthFlowModel(authService: previewAuthService()))
    }
}

#Preview("Sign Up — Loading") {
    let m = AuthFlowModel(authService: previewAuthService())
    m.isLoading = true
    m.signUpName = "Jane Austen"
    m.signUpEmail = "jane@example.com"
    m.signUpPassword = "Hunter2!"
    return NavigationStack { SignUpView(model: m) }
}

#Preview("Sign Up — Error") {
    let m = AuthFlowModel(authService: previewAuthService())
    m.toastMessage = "An account with this email already exists."
    return NavigationStack { SignUpView(model: m) }
}
#endif
