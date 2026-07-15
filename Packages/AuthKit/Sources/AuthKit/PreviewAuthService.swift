import CoreKit
import Foundation

// MARK: - Preview support

/// Returns a stub `AuthService` configured with dummy values for use in
/// SwiftUI `#Preview` contexts. Amplify is never configured, so auth
/// operations will throw — but previews only render UI, not execute flows.
@MainActor
func previewAuthService() -> AuthService {
    AuthService(config: AppConfig(
        apiBaseURL: "https://preview.example.com",
        cognitoRegion: "us-east-1",
        cognitoUserPoolID: "us-east-1_preview",
        cognitoClientID: "previewClientId"
    ))
}

@MainActor
func previewAuthFlowModel() -> AuthFlowModel {
    let service = previewAuthService()
    return AuthFlowModel(
        authService: service,
        sessionManager: SessionManager(authService: service)
    )
}
