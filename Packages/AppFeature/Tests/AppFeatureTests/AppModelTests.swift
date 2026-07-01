import Testing
import Foundation
@testable import AppFeature

@Suite("AppModel deep-link routing")
@MainActor
struct AppModelTests {

    @Test("book URL routes to library tab")
    func bookURLRoutesToLibrary() async {
        let model = AppModel()
        model.handle(url: URL(string: "chapterflow://book/abc123")!)
        #expect(model.selectedTab == .library)
    }

    @Test("chapter URL routes to library tab")
    func chapterURLRoutesToLibrary() async {
        let model = AppModel()
        model.handle(url: URL(string: "chapterflow://book/abc123/chapter/3")!)
        #expect(model.selectedTab == .library)
    }

    @Test("review URL routes to reviews tab")
    func reviewURLRoutesToReviews() async {
        let model = AppModel()
        model.handle(url: URL(string: "chapterflow://review")!)
        #expect(model.selectedTab == .reviews)
    }

    @Test("pair accept URL routes to profile tab")
    func pairAcceptRoutesToProfile() async {
        let model = AppModel()
        model.handle(url: URL(string: "chapterflow://pair/accept/XYZ")!)
        #expect(model.selectedTab == .profile)
    }

    @Test("gift URL routes to profile tab")
    func giftURLRoutesToProfile() async {
        let model = AppModel()
        model.handle(url: URL(string: "chapterflow://gift/GIFTCODE")!)
        #expect(model.selectedTab == .profile)
    }

    @Test("unknown scheme is ignored; tab stays at default")
    func unknownSchemeIgnored() async {
        let model = AppModel()
        model.handle(url: URL(string: "https://chapterflow.app/book/abc123")!)
        #expect(model.selectedTab == .home)
    }

    @Test("unrecognised chapterflow path leaves tab unchanged")
    func unknownPathIgnored() async {
        let model = AppModel()
        model.handle(url: URL(string: "chapterflow://unknown-feature")!)
        #expect(model.selectedTab == .home)
    }
}
