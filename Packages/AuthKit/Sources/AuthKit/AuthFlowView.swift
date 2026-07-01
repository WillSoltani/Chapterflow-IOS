import SwiftUI

/// Placeholder sign-in / sign-up flow.
///
/// The structural shell is complete; the real Cognito `initiateAuth` call and
/// the sign-up / forgot-password paths are wired in P1.5. `AppRootView` presents
/// this whenever `SessionManager.authState == .signedOut`.
public struct AuthFlowView: View {
    let sessionManager: SessionManager

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
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
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
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
            .navigationBarHidden(true)
        }
    }

    private func signIn() async {
        isLoading = true
        defer { isLoading = false }
        // Stub: P1.5 replaces with real Cognito USER_PASSWORD_AUTH flow.
        try? await Task.sleep(for: .seconds(1))
        sessionManager.didSignIn(
            idToken: "stub-id-token",
            refreshToken: "stub-refresh-token"
        )
    }
}

#Preview("Sign In") {
    AuthFlowView(sessionManager: SessionManager())
}
