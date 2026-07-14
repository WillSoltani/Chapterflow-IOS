import AuthKit
import CoreKit
import Foundation
import Persistence
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
        do {
            let persistence = try makeTestPersistenceResources()
            let authService = AuthService(config: validated.value)
            return AppModel(
                config: validated,
                persistence: persistence,
                authService: authService,
                session: SessionManager(authService: authService)
            )
        } catch {
            preconditionFailure("Test persistence must initialize: \(error)")
        }
    case .invalid(let issues):
        preconditionFailure("Test configuration must remain valid: \(issues.map(\.code))")
    }
}

func makeTestPersistenceResources() throws -> AppPersistenceResources {
    let controller = try PersistenceController.makeDefault(storage: .inMemory)
    let fileStore = try FileStore(
        root: FileManager.default.temporaryDirectory
            .appending(path: "cf-app-feature-tests-\(UUID().uuidString)")
    )
    return AppPersistenceResources(
        controller: controller,
        downloadFileStore: fileStore
    )
}
