import AuthKit
import CoreKit
import Foundation
import Persistence
@testable import AppFeature

@MainActor
func makeTestAppModel(session injectedSession: SessionManager? = nil) -> AppModel {
    let validated = makeTestValidatedConfig()

    do {
        let persistence = try makeTestPersistenceResources()
        let authService = AuthService(config: validated.value)
        let session = injectedSession ?? SessionManager(authService: authService)
        return AppModel(
            config: validated,
            persistence: persistence,
            authService: authService,
            session: session
        )
    } catch {
        preconditionFailure("Test persistence must initialize: \(error)")
    }
}

func makeTestValidatedConfig() -> ValidatedAppConfig {
    let config = AppConfig(
        apiBaseURL: "https://api.chapterflow.test",
        cognitoRegion: "us-east-1",
        cognitoUserPoolID: "us-east-1_ChapterFlowTests",
        cognitoClientID: "chapterflowtestsclient12345",
        cognitoDomain: "auth.chapterflow.test"
    )

    switch config.validate() {
    case .valid(let validated): return validated
    case .invalid(let issues):
        preconditionFailure("Test configuration must remain valid: \(issues.map(\.code))")
    }
}

@MainActor
func makeTestAppModel(
    session: SessionManager,
    scopeBuilder: @escaping @MainActor (AccountContext) async throws -> SessionScope
) -> AppModel {
    let validated = makeTestValidatedConfig()
    do {
        let persistence = try makeTestPersistenceResources()
        let authService = AuthService(config: validated.value)
        let loader = InMemoryAccountPersistenceLoader(
            root: FileManager.default.temporaryDirectory
                .appending(path: "cf-scope-loader-\(UUID().uuidString)")
        )
        return AppModel(
            config: validated,
            persistence: persistence,
            authService: authService,
            session: session,
            accountPersistenceLoader: loader,
            scopeBuilder: scopeBuilder
        )
    } catch {
        preconditionFailure("Test persistence must initialize: \(error)")
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
