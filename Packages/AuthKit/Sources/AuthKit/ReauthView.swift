import SwiftUI
import LocalAuthentication
import CoreKit

/// A modal sheet presented when the server returns `reauth_required`.
///
/// The user can re-confirm their identity with a password (stub — real Cognito
/// call wired in P1.5) or biometrics. On success, calls `sessionManager
/// .stepUpCompleted(idToken:refreshToken:)`, which resumes all suspended API
/// requests and returns the app to `.signedIn`. On cancel, calls
/// `stepUpCancelled()`, which signs the user out.
public struct ReauthView: View {
    let sessionManager: SessionManager

    @State private var password = ""
    @State private var isAuthenticating = false
    @State private var errorMessage: String?

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text("Verify It's You")
                        .font(.title2.weight(.semibold))

                    Text("For your security, confirm your identity to continue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 16) {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Password")

                    if let error = errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(error)")
                    }

                    Button {
                        Task { await confirmWithPassword() }
                    } label: {
                        Group {
                            if isAuthenticating {
                                ProgressView()
                            } else {
                                Text("Confirm")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty || isAuthenticating)
                    .accessibilityLabel("Confirm identity with password")
                }

                Divider()

                Button {
                    Task { await confirmWithBiometrics() }
                } label: {
                    Label("Use Face ID / Touch ID", systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .disabled(isAuthenticating)
                .accessibilityLabel("Authenticate with Face ID or Touch ID")

                Spacer()
            }
            .padding()
            .navigationTitle("Security Check")
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { sessionManager.stepUpCancelled() }
                        .accessibilityLabel("Cancel and sign out")
                }
            }
            .disabled(isAuthenticating)
        }
    }

    private func confirmWithPassword() async {
        guard !password.isEmpty else { return }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        // Stub: P1.5 replaces this with a real Cognito `initiateAuth` call
        // using PASSWORD_VERIFIER. Any non-empty password succeeds here so the
        // error-routing paths can be exercised in the simulator.
        try? await Task.sleep(for: .milliseconds(400))
        let fakeIdToken = "reauth-id-\(password.prefix(4))"
        let fakeRefreshToken = "reauth-refresh"
        sessionManager.stepUpCompleted(idToken: fakeIdToken, refreshToken: fakeRefreshToken)
    }

    private func confirmWithBiometrics() async {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        let context = LAContext()
        var nsError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &nsError) else {
            errorMessage = "Biometrics unavailable. Please enter your password."
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Confirm it's you to continue"
            )
            if success {
                sessionManager.stepUpCompleted(
                    idToken: "biometric-id-token",
                    refreshToken: "biometric-refresh"
                )
            } else {
                errorMessage = "Authentication failed. Try again."
            }
        } catch let laError as LAError where laError.code == .userCancel {
            // User cancelled — sheet stays visible.
        } catch {
            errorMessage = "Authentication failed. Try again."
        }
    }
}

#Preview("ReauthView") {
    ReauthView(sessionManager: SessionManager(tokenStore: InMemoryTokenStore(idToken: "tok")))
}
