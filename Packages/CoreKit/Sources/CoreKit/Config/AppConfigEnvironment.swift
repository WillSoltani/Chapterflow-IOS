import SwiftUI

// MARK: - SwiftUI Environment key for AppConfig

private struct AppConfigKey: EnvironmentKey {
    static let defaultValue = AppConfig(
        apiBaseURL: "",
        cognitoRegion: "",
        cognitoUserPoolID: "",
        cognitoClientID: ""
    )
}

public extension EnvironmentValues {
    /// The app configuration injected by `ChapterFlowApp` at the root
    /// `WindowGroup`. Downstream models read this to get the API base URL,
    /// Cognito ids, etc. without coupling to `Bundle.main`.
    var appConfig: AppConfig {
        get { self[AppConfigKey.self] }
        set { self[AppConfigKey.self] = newValue }
    }
}
