import SwiftUI

/// Sign-in / sign-up flow entry point.
///
/// Currently presents the email + password form. The real Cognito
/// `USER_PASSWORD_AUTH` call is wired in P1.4; this view calls the stub.
/// `AppRootView` presents it whenever `launchState == .signedOut`.
///
/// `onSignIn` is invoked after `SessionManager.didSignIn` succeeds so the
/// composition root can hydrate the user profile via `AppModel.bootstrap()`.
public struct AuthFlowView: View {
    let sessionManager: SessionManager
    let onSignIn: (() -> Void)?

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false

    public init(sessionManager: SessionManager, onSignIn: (() -> Void)? = nil) {
        self.sessionManager = sessionManager
        self.onSignIn = onSignIn
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)

                    Text("ChapterFlow")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                }

                Spacer().frame(height: 48)

                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
#if canImport(UIKit)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled()
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Email address")

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Password")

                    Button {
                        Task { await signIn() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Sign In")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(email.isEmpty || password.isEmpty || isLoading)
                    .accessibilityLabel("Sign in")
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationTitle("")
#if canImport(UIKit)
            .navigationBarHidden(true)
#endif
        }
    }

    private func signIn() async {
        isLoading = true
        defer { isLoading = false }
        // Stub: P1.4 replaces with real Cognito USER_PASSWORD_AUTH flow.
        try? await Task.sleep(for: .seconds(1))
        sessionManager.didSignIn(
            idToken: "stub-id-token",
            refreshToken: "stub-refresh-token"
        )
        onSignIn?()
    }
}

#Preview("Sign In") {
    AuthFlowView(sessionManager: SessionManager())
}
