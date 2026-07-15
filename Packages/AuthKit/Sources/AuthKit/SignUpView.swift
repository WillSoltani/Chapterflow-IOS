#if os(iOS)
import SwiftUI

public struct SignUpView: View {
    @Bindable var model: AuthFlowModel

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Create Account")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Join ChapterFlow and start learning.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                VStack(spacing: 16) {
                    AuthTextField(
                        "Full name",
                        text: $model.signUpName,
                        textContentType: .name,
                        autocapitalization: .words
                    )

                    AuthTextField(
                        "Email",
                        text: $model.signUpEmail,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never
                    )

                    AuthSecureField(
                        "Password",
                        text: $model.signUpPassword,
                        textContentType: .newPassword
                    )
                    .onChange(of: model.signUpPassword) { model.updatePasswordStrength() }

                    if !model.signUpPassword.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            PasswordStrengthBar(model.signUpPasswordStrength)
                            Text(model.signUpPasswordStrength.label)
                                .font(.caption)
                                .foregroundStyle(model.signUpPasswordStrength.color)
                        }
                    }
                }

                CFPrimaryButton("Create Account", isLoading: model.isLoading) {
                    model.performSignUp()
                }
                .disabled(
                    !AuthFlowModel.isValidEmail(model.signUpEmail)
                        || model.signUpPassword.count < 8
                        || model.isLoading
                )

                CFTextButton("Already have an account? Log in") {
                    model.navigationPath = [.logIn]
                }
                .disabled(model.isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Sign Up") {
    NavigationStack {
        SignUpView(model: previewAuthFlowModel())
    }
}
#endif // os(iOS)
