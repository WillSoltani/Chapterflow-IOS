#if os(iOS)
import SwiftUI
import CoreKit
import AuthKit
import DesignSystem

/// Presents the auth flow as a bottom sheet when a guest hits an auth gate.
///
/// Wraps `AuthFlowView` with the contextual value proposition from the
/// `AuthGateIntent`. The sheet is dismissed by `AppRootView` when
/// `authState` transitions to `.signedIn`.
struct AuthGateSheet: View {
    let authService: AuthService
    let intent: AuthGateIntent

    var body: some View {
        AuthFlowView(authService: authService, gateContext: intent.gateContext)
    }
}

// MARK: - Preview helper

@MainActor
private func makePreviewAuthService() -> AuthService {
    AuthService(config: AppConfig(
        apiBaseURL: "https://preview.example.com",
        cognitoRegion: "us-east-1",
        cognitoUserPoolID: "us-east-1_preview",
        cognitoClientID: "previewClientId"
    ))
}

// MARK: - Previews

#Preview("Auth gate — start book") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AuthGateSheet(
                authService: makePreviewAuthService(),
                intent: .startBook(bookId: "b-test", variantFamily: .emh)
            )
        }
}

#Preview("Auth gate — generic") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AuthGateSheet(
                authService: makePreviewAuthService(),
                intent: .none
            )
        }
}
#endif // os(iOS)
