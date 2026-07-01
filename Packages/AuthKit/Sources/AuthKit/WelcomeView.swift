#if os(iOS)
import SwiftUI
import AuthenticationServices

/// The brand landing screen — the root of the `AuthFlowView` navigation stack.
///
/// Three paths:
///   - Continue with Apple → native SIWA sheet → Cognito token exchange
///   - Create an account → `SignUpView`
///   - Log in → `LogInView`
public struct WelcomeView: View {
    @Bindable var model: AuthFlowModel

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Brand mark
            VStack(spacing: 20) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("ChapterFlow")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)

                    Text("Learn more from every book.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer().frame(height: 60)

            // Sign-in actions
            VStack(spacing: 14) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    model.performSignInWithApple(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .disabled(model.isLoading)
                .accessibilityLabel("Continue with Apple")

                HStack {
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundStyle(Color(uiColor: .quaternaryLabel))
                    Text("or")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundStyle(Color(uiColor: .quaternaryLabel))
                }
                .padding(.vertical, 4)

                CFPrimaryButton("Create an account") {
                    model.navigate(to: .signUp)
                }
                .disabled(model.isLoading)

                CFTextButton("Already have an account? Log in") {
                    model.navigate(to: .logIn)
                }
                .disabled(model.isLoading)
            }

            if model.isLoading {
                ProgressView()
                    .padding(.top, 12)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview("Welcome") {
    WelcomeView(model: AuthFlowModel(authService: previewAuthService()))
}
#endif // os(iOS)
