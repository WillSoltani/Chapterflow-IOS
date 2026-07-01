import SwiftUI
import DesignSystem

/// Full-screen loading view shown during app bootstrap while the session is
/// validated and the user's identity is being hydrated.
public struct SplashView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundStyle(Color.cfAccent)
                    .accessibilityHidden(true)

                Text("ChapterFlow")
                    .font(.cfLargeTitle)
                    .foregroundStyle(Color.cfLabel)
            }

            Spacer()

            ProgressView()
                .tint(Color.cfSecondaryLabel)
                .padding(.bottom, 52)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cfBackground)
    }
}

#Preview("Splash") {
    SplashView()
}
