import Testing
@testable import CoreKit

private enum SampleRoute: Routed {
    case detail(id: String)
    case settings
}

@MainActor
@Suite("Router")
struct RouterTests {
    @Test("push increases depth, pop decreases it")
    func pushPop() {
        let router = Router()
        #expect(router.isAtRoot)
        #expect(router.depth == 0)

        router.push(SampleRoute.detail(id: "1"))
        router.push(SampleRoute.settings)
        #expect(router.depth == 2)
        #expect(!router.isAtRoot)

        router.pop()
        #expect(router.depth == 1)
    }

    @Test("pop at root is a no-op")
    func popAtRoot() {
        let router = Router()
        router.pop()
        #expect(router.depth == 0)
    }

    @Test("popToRoot clears the whole stack")
    func popToRoot() {
        let router = Router()
        router.push(SampleRoute.detail(id: "1"))
        router.push(SampleRoute.detail(id: "2"))
        router.push(SampleRoute.settings)
        #expect(router.depth == 3)

        router.popToRoot()
        #expect(router.depth == 0)
        #expect(router.isAtRoot)
    }
}
