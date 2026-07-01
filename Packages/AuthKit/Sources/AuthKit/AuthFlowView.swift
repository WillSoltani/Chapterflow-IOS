#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// Root view for the entire authentication flow.
///
/// Hosts a `NavigationStack` with `WelcomeView` as the root and dispatches
/// to each auth screen based on the `AuthFlowModel.Screen` enum pushed onto
/// `navigationPath`. Present this view as a `fullScreenCover` when the user
/// is not signed in.
public struct AuthFlowView: View {
    @State private var model: AuthFlowModel

    public init(authService: AuthService) {
        _model = State(initialValue: AuthFlowModel(authService: authService))
    }

    public var body: some View {
        NavigationStack(path: $model.navigationPath) {
            WelcomeView(model: model)
                .navigationDestination(for: AuthFlowModel.Screen.self) { screen in
                    switch screen {
                    case .signUp:
                        SignUpView(model: model)
                    case .verifyEmail(let email):
                        VerifyEmailView(model: model, email: email)
                    case .logIn:
                        LogInView(model: model)
                    case .forgotPasswordRequest:
                        ForgotPasswordRequestView(model: model)
                    case .forgotPasswordReset(let username):
                        ForgotPasswordResetView(model: model, username: username)
                    }
                }
        }
        .tint(Color.cfAccent)
    }
}

// MARK: - Preview

#Preview("Auth Flow") {
    AuthFlowView(authService: previewAuthService())
}
#endif
