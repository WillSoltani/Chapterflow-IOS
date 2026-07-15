#if os(iOS)
import SwiftUI

/// The brand landing screen — the root of the `AuthFlowView` navigation stack.
///
/// Apple remains hidden until the signed provider path is proven in
/// WP-AUTH-01B. The available paths share the authoritative email session.
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

                    // When triggered from an auth gate, show contextual copy;
                    // otherwise show the generic tagline.
                    if let ctx = model.gateContext {
                        Text(ctx)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Learn more from every book.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer().frame(height: 60)

            // Sign-in actions
            VStack(spacing: 14) {
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

            // "Browse without account" — only shown on the initial welcome screen,
            // not when invoked from an auth gate (where the guest is already browsing).
            if let browse = model.onBrowseAsGuest, model.gateContext == nil {
                CFTextButton("Browse without account") {
                    browse()
                }
                .disabled(model.isLoading)
                .padding(.top, 8)
                .accessibilityLabel("Continue browsing without creating an account")
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
    WelcomeView(model: previewAuthFlowModel())
}
#endif // os(iOS)
