import SwiftUI
import Persistence

/// Truthful recovery surface for a server-required fresh authentication.
///
/// ChapterFlow does not yet have a supported in-session Cognito step-up
/// challenge. Local biometrics and an unchecked password must not resume a
/// server request, so this surface ends the current session and returns the
/// user to the authoritative sign-in flow.
public struct ReauthView: View {
    let sessionManager: SessionManager
    @State private var isSigningOut = false

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("Sign In Again")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)

                    Text("Your session needs fresh verification. Sign in again to continue securely.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    isSigningOut = true
                    Task { await sessionManager.stepUpCancelled() }
                } label: {
                    Group {
                        if isSigningOut {
                            ProgressView()
                        } else {
                            Text("Sign In Again")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSigningOut)
                .accessibilityHint("Ends this session and opens the secure sign-in flow")

                Spacer()
            }
            .padding()
            .navigationTitle("Security Check")
            .toolbarTitleDisplayMode(.inline)
        }
    }
}

#Preview("ReauthView") {
    ReauthView(sessionManager: SessionManager(tokenStore: InMemoryTokenStore()))
}
