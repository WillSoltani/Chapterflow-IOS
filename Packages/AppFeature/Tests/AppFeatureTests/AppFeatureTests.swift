import Testing
import Foundation
import CoreKit
@testable import AppFeature

@Suite("AppFeature")
struct AppFeatureTests {
    @Test("module exposes its name")
    func moduleName() {
        #expect(AppFeature.moduleName == "AppFeature")
    }
}

// MARK: - DeepLinkParser

@Suite("DeepLinkParser")
struct DeepLinkParserTests {
    @Test("custom-scheme book URL → library book route")
    func bookURL() throws {
        let url = try #require(URL(string: "chapterflow://book/42"))
        #expect(DeepLinkParser.target(for: url) == .library(.book(id: "42")))
    }

    @Test("custom-scheme chapter URL → library chapter route")
    func chapterURL() throws {
        let url = try #require(URL(string: "chapterflow://book/42/chapter/3"))
        #expect(DeepLinkParser.target(for: url) == .library(.chapter(bookId: "42", chapter: 3)))
    }

    @Test("pair-accept URL → profile route")
    func pairAcceptURL() throws {
        let url = try #require(URL(string: "chapterflow://pair/accept/XYZ"))
        #expect(DeepLinkParser.target(for: url) == .profile(.pairAccept(code: "XYZ")))
    }

    @Test("gift URL → profile route")
    func giftURL() throws {
        let url = try #require(URL(string: "chapterflow://gift/GIFT99"))
        #expect(DeepLinkParser.target(for: url) == .profile(.gift(code: "GIFT99")))
    }

    @Test("review URL → reviews tab root")
    func reviewURL() throws {
        let url = try #require(URL(string: "chapterflow://review"))
        #expect(DeepLinkParser.target(for: url) == .tabRoot(.reviews))
    }

    @Test("universal (https) link maps like the custom scheme")
    func universalLink() throws {
        let url = try #require(URL(string: "https://chapterflow.app/book/7/chapter/2"))
        #expect(DeepLinkParser.target(for: url) == .library(.chapter(bookId: "7", chapter: 2)))
    }

    @Test("unknown / foreign URLs resolve to nil")
    func unknownURLs() throws {
        let foreign = try #require(URL(string: "https://example.com/"))
        #expect(DeepLinkParser.target(for: foreign) == nil)

        let unrecognized = try #require(URL(string: "chapterflow://wat/ever"))
        #expect(DeepLinkParser.target(for: unrecognized) == nil)
    }

    @Test("maps a CoreKit.DeepLink value directly")
    func fromDeepLinkValue() {
        #expect(DeepLinkParser.target(for: .book(id: "1")) == .library(.book(id: "1")))
        #expect(DeepLinkParser.target(for: .review) == .tabRoot(.reviews))
        #expect(DeepLinkParser.target(for: .unknown(URL(string: "chapterflow://x")!)) == nil)
    }
}

// MARK: - TabRouter

@Suite("TabRouter")
@MainActor
struct TabRouterTests {
    @Test("starts on Home with empty stacks")
    func initialState() {
        let router = TabRouter()
        #expect(router.selectedTab == .home)
        for tab in Tab.allCases {
            #expect(router.depth(of: tab) == 0)
        }
    }

    @Test("applying a library target selects Library and pushes one route")
    func applyLibrary() {
        let router = TabRouter()
        router.apply(.library(.chapter(bookId: "42", chapter: 3)))
        #expect(router.selectedTab == .library)
        #expect(router.depth(of: .library) == 1)
        #expect(router.depth(of: .home) == 0)
    }

    @Test("applying a tab-root target switches tab without pushing")
    func applyTabRoot() {
        let router = TabRouter()
        router.apply(.tabRoot(.reviews))
        #expect(router.selectedTab == .reviews)
        #expect(router.depth(of: .reviews) == 0)
    }

    @Test("popToRoot clears a tab's stack")
    func popToRoot() {
        let router = TabRouter()
        router.apply(.profile(.pairAccept(code: "ABC")))
        #expect(router.depth(of: .profile) == 1)
        router.popToRoot(.profile)
        #expect(router.depth(of: .profile) == 0)
    }

    @Test("each tab keeps its own independent stack")
    func independentStacks() {
        let router = TabRouter()
        router.apply(.library(.book(id: "1")))
        router.apply(.profile(.gift(code: "G")))
        #expect(router.depth(of: .library) == 1)
        #expect(router.depth(of: .profile) == 1)
        #expect(router.selectedTab == .profile)
    }
}

// MARK: - AppRootModel

@Suite("AppRootModel")
@MainActor
struct AppRootModelTests {
    @Test("resolves to ready when a token is present")
    func readyWhenSignedIn() async {
        let model = AppRootModel(dependencies: .mock(signedIn: true))
        #expect(model.phase == .launching)
        await model.resolveSession()
        #expect(model.phase == .ready)
    }

    @Test("resolves to signedOut with no token")
    func signedOutWhenNoToken() async {
        let model = AppRootModel(dependencies: .mock(signedIn: false))
        await model.resolveSession()
        #expect(model.phase == .signedOut)
    }

    @Test("didSignIn advances to ready")
    func signIn() async {
        let model = AppRootModel(dependencies: .mock(signedIn: false))
        await model.resolveSession()
        #expect(model.phase == .signedOut)
        model.didSignIn()
        #expect(model.phase == .ready)
    }

    @Test("signOut returns to signedOut and resets flags")
    func signOut() async {
        let deps = Dependencies.mock(signedIn: true)
        let model = AppRootModel(dependencies: deps)
        await model.resolveSession()
        model.signOut()
        #expect(model.phase == .signedOut)
        #expect(deps.featureFlags.config == nil)
    }
}

// MARK: - Dependencies

@Suite("Dependencies")
@MainActor
struct DependenciesTests {
    @Test("mock container builds with all collaborators")
    func mockBuilds() {
        let deps = Dependencies.mock()
        #expect(deps.config.apiBaseURL == "https://example.com")
        #expect(deps.featureFlags.isEnabled(.offlineReading) == true)
    }

    @Test("mock respects signed-in flag via the token store")
    func mockTokenState() async throws {
        let signedOut = Dependencies.mock(signedIn: false)
        let token = try await signedOut.tokenStore.validToken()
        #expect(token == nil)
    }
}
