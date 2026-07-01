import SwiftUI
import AuthenticationServices
import CoreKit

/// The Welcome / sign-in screen shown when `AuthState == .signedOut`.
///
/// **Primary path (INT-1):** "Continue with Apple"
///   → native Apple sheet → Cognito token exchange → `.signedIn`
///
/// `onDisplayName` is called after a successful sign-in with the display name
/// Apple discloses on first sign-in (subsequent sign-ins fall back to JWT claims).
public struct AuthFlowView: View {
    let sessionManager: SessionManager
    let cognitoClient: CognitoTokenClient
    var onDisplayName: ((String) -> Void)?

    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(
        sessionManager: SessionManager,
        cognitoClient: CognitoTokenClient,
        onDisplayName: ((String) -> Void)? = nil
    ) {
        self.sessionManager = sessionManager
        self.cognitoClient = cognitoClient
        self.onDisplayName = onDisplayName
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Brand mark
                VStack(spacing: 20) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.accentColor)
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

                Spacer().frame(height: 64)

                // Sign-in actions
                VStack(spacing: 16) {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task { await handleAppleResult(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(10)
                    .disabled(isLoading)
                    .accessibilityLabel("Continue with Apple")

                    if isLoading {
                        ProgressView()
                            .padding(.top, 4)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityLabel("Sign-in error: \(error)")
                    }
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 32)
            .navigationTitle("")
            .hideNavigationBar()
        }
    }

    // MARK: - Apple result handler

    @MainActor
    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        switch result {
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return  // user tapped Cancel — no message needed
            }
            errorMessage = "Sign in failed. Please try again."

        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let authCodeData = credential.authorizationCode else {
                errorMessage = "Could not complete sign in. Please try again."
                return
            }

            do {
                let (tokens, displayName) = try await cognitoClient.exchangeAppleCode(
                    authCodeData,
                    name: credential.fullName
                )
                sessionManager.didSignIn(idToken: tokens.idToken, refreshToken: tokens.refreshToken)
                if let name = displayName, !name.isEmpty {
                    // Persist for subsequent launches where Apple won't re-disclose.
                    UserDefaults.standard.set(name, forKey: "chapterflow.displayName")
                    onDisplayName?(name)
                }
            } catch {
                errorMessage = "Could not complete sign in. Please try again."
            }
        }
    }
}

// MARK: - Cross-platform helper

private extension View {
    @ViewBuilder
    func hideNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}

#Preview("Welcome") {
    AuthFlowView(
        sessionManager: SessionManager(tokenStore: InMemoryTokenStore()),
        cognitoClient: CognitoTokenClient(config: AppConfig(
            apiBaseURL: "",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "",
            cognitoClientID: "",
            cognitoDomain: ""
        ))
    )
}
