import SwiftUI

/// A stand-in for the real authentication flow.
///
/// > Placeholder: **AuthKit (P1)** replaces this with the Cognito sign-in / sign-up
/// > / Sign-in-with-Apple experience. For P0.6 it exists only so the
/// > splash → signed-out → shell transition is wired and demonstrable: tapping
/// > "Continue" seeds the stub token and advances to the tab shell.
struct AuthFlowView: View {
    /// Invoked when the user completes the (stubbed) sign-in.
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "book.pages")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Welcome to ChapterFlow")
                    .font(.title2.weight(.semibold))
                Text("Sign in to start learning.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onSignIn) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Continue to sign in")
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
    }
}

#Preview("Auth flow (stub)") {
    AuthFlowView(onSignIn: {})
}
