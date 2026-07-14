import Foundation
import Testing
@testable import Persistence

@Suite("App persistence bootstrap")
struct AppPersistenceBootstrapTests {
    @Test("explicit test storage opens required SwiftData and download resources")
    func opensRequiredResources() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "cf-bootstrap-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let loader = DefaultAppPersistenceLoader(
            storage: .inMemory,
            downloadRoot: root
        )

        let resources = try await loader.load()

        #expect(resources.downloadFileStore.root == root)
        #expect(FileManager.default.fileExists(atPath: root.path))
        _ = resources.controller.container
    }

    @Test("download directory failure propagates without a fallback location")
    func downloadFailureDoesNotFallback() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appending(path: "cf-bootstrap-blocker-\(UUID().uuidString)")
        try Data("not-a-directory".utf8).write(to: parent)
        defer { try? FileManager.default.removeItem(at: parent) }
        let impossibleRoot = parent.appending(path: "Downloads")
        let loader = DefaultAppPersistenceLoader(
            storage: .inMemory,
            downloadRoot: impossibleRoot
        )

        do {
            _ = try await loader.load()
            Issue.record("Loader silently substituted another download directory")
        } catch {
            #expect(!FileManager.default.fileExists(atPath: impossibleRoot.path))
        }
    }

    #if DEBUG
    @Test("explicit hermetic loader opens isolated Debug-only resources")
    func hermeticLoaderOpensIsolatedResources() async throws {
        let resources = try await DefaultAppPersistenceLoader
            .hermeticTestStorage()
            .load()
        defer { try? FileManager.default.removeItem(at: resources.downloadFileStore.root) }

        #expect(FileManager.default.fileExists(atPath: resources.downloadFileStore.root.path))
        _ = resources.controller.container
    }
    #endif
}
