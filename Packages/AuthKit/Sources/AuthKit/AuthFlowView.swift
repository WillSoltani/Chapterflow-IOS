#if os(iOS)
import SwiftUI

/// Root of the unauthenticated navigation stack.
///
/// Creates an `AuthFlowModel` from the shared `AuthService` and manages a
/// `NavigationStack` over all auth screens. The stack is dismissed automatically
/// when `SessionManager.authState` transitions to `.signedIn` — `AppRootView`
/// stops rendering this view.
public struct AuthFlowView: View {
    @State private var model: AuthFlowModel

    public init(
        authService: AuthService,
        sessionManager: SessionManager,
        gateContext: String? = nil,
        onBrowseAsGuest: (() -> Void)? = nil
    ) {
        var m = AuthFlowModel(
            authService: authService,
            sessionManager: sessionManager,
            gateContext: gateContext
        )
        m.onBrowseAsGuest = onBrowseAsGuest
        _model = State(wrappedValue: m)
    }

    public var body: some View {
        NavigationStack(path: $model.navigationPath) {
            WelcomeView(model: model)
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .signUp:
                        SignUpView(model: model)
                    case .logIn:
                        LogInView(model: model)
                    case .verifyEmail:
                        VerifyEmailView(model: model)
                    case .forgotPassword:
                        ForgotPasswordView(model: model)
                    }
                }
        }
        .cfToast(message: model.toastMessage, isError: model.toastIsError)
    }
}

#Preview("Auth flow") {
    let service = previewAuthService()
    AuthFlowView(authService: service, sessionManager: SessionManager(authService: service))
}
#endif // os(iOS)
