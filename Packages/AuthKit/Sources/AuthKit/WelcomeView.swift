#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// The entry point of the auth flow. Shows the app identity and routes the
/// user to sign up with email or log in.
public struct WelcomeView: View {
    @Bindable var model: AuthFlowModel

    public init(model: AuthFlowModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            Color.cfBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App identity mark
                VStack(spacing: .cfSpacing16) {
                    ZStack {
                        Circle()
                            .fill(Color.cfAccent.opacity(0.12))
                            .frame(width: 96, height: 96)
                        Text("CF")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.cfAccent)
                    }
                    .accessibilityHidden(true)

                    VStack(spacing: .cfSpacing8) {
                        Text("ChapterFlow")
                            .font(.cfLargeTitle)
                            .foregroundStyle(Color.cfLabel)

                        Text("Learn smarter. One chapter at a time.")
                            .font(.cfSubheadline)
                            .foregroundStyle(Color.cfSecondaryLabel)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                // Action area
                VStack(spacing: .cfSpacing12) {
                    // Continue with Apple — stub; P1.2 will wire Sign-in with Apple
                    Button {
                        model.toastMessage = "Sign in with Apple is coming soon."
                    } label: {
                        HStack(spacing: .cfSpacing8) {
                            Image(systemName: "apple.logo")
                                .font(.cfHeadline)
                            Text("Continue with Apple")
                                .font(.cfHeadline)
                        }
                        .foregroundStyle(Color.cfLabel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: .cfRadius16)
                                .fill(Color.cfSecondaryBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: .cfRadius16)
                                        .strokeBorder(Color.cfSeparator, lineWidth: 1)
                                )
                        )
                    }
                    .accessibilityLabel("Continue with Apple")
                    .accessibilityHint("Sign in with your Apple ID. Coming soon.")

                    CFPrimaryButton(label: "Sign up with email") {
                        model.navigateTo(.signUp)
                    }
                    .accessibilityHint("Create a new ChapterFlow account using your email address.")

                    CFTextButton(label: "Log in") {
                        model.navigateTo(.logIn)
                    }
                    .accessibilityHint("Sign in to your existing ChapterFlow account.")
                }
                .padding(.horizontal, .cfSpacing24)
                .padding(.bottom, .cfSpacing32)
            }
        }
        .cfToast(model.toastMessage)
        .navigationBarHidden(true)
    }
}

// MARK: - Previews

#Preview("Welcome — Idle") {
    NavigationStack {
        WelcomeView(model: AuthFlowModel(authService: previewAuthService()))
    }
}
#endif
