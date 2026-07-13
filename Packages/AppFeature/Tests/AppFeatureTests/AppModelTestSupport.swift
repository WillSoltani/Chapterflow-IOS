import CoreKit
@testable import AppFeature

@MainActor
func makeTestAppModel() -> AppModel {
    let config = AppConfig(
        apiBaseURL: "https://api.chapterflow.test",
        cognitoRegion: "us-east-1",
        cognitoUserPoolID: "us-east-1_ChapterFlowTests",
        cognitoClientID: "chapterflowtestsclient12345",
        cognitoDomain: "auth.chapterflow.test"
    )

    switch config.validate() {
    case .valid(let validated):
        return AppModel(config: validated)
    case .invalid(let issues):
        preconditionFailure("Test configuration must remain valid: \(issues.map(\.code))")
    }
}
