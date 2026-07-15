#if os(iOS)
import SwiftUI

public struct VerifyEmailView: View {
    @Bindable var model: AuthFlowModel

    public var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text("Check Your Email")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)

                    Text("We sent a 6-digit code to\n**\(model.pendingUsername)**")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                VerificationCodeField(code: $model.verifyCode)

                CFPrimaryButton("Verify Email", isLoading: model.isLoading) {
                    model.performConfirmEmail()
                }
                .disabled(model.verifyCode.count < 6 || model.isLoading)

                VStack(spacing: 4) {
                    Text("Didn't receive a code?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    CFTextButton("Resend code") {
                        model.performResendCode()
                    }
                    .disabled(model.isLoading)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .navigationTitle("Verify Email")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Verify Email") {
    let m = previewAuthFlowModel()
    NavigationStack {
        VerifyEmailView(model: m)
            .onAppear { m.pendingUsername = "you@example.com" }
    }
}
#endif // os(iOS)
