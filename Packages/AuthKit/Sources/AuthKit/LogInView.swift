#if os(iOS)
import SwiftUI

public struct LogInView: View {
    @Bindable var model: AuthFlowModel

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Welcome Back")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Sign in to continue reading.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                VStack(spacing: 16) {
                    AuthTextField(
                        "Email",
                        text: $model.logInEmail,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never
                    )

                    AuthSecureField(
                        "Password",
                        text: $model.logInPassword,
                        textContentType: .password
                    )
                }

                CFPrimaryButton("Log In", isLoading: model.isLoading) {
                    model.performLogIn()
                }
                .disabled(
                    model.logInEmail.isEmpty
                        || model.logInPassword.isEmpty
                        || model.isLoading
                )

                CFTextButton("Forgot password?") {
                    model.navigate(to: .forgotPassword)
                }
                .disabled(model.isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .navigationTitle("Log In")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Log In") {
    NavigationStack {
        LogInView(model: AuthFlowModel(authService: previewAuthService()))
    }
}
#endif // os(iOS)
