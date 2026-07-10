import Testing
import Foundation
@testable import SettingsFeature
import Persistence

// MARK: - Fixtures

private let sampleReleases = WhatsNewContent(releases: [
    WhatsNewRelease(version: "1.0", title: "Welcome", highlights: [
        WhatsNewHighlight(id: "a", symbolName: "star", title: "A", detail: "First.")
    ]),
    WhatsNewRelease(version: "1.2", title: "What's New", highlights: [
        WhatsNewHighlight(id: "b", symbolName: "bolt", title: "B", detail: "Second."),
        WhatsNewHighlight(id: "c", symbolName: "leaf", title: "C", detail: "Third.")
    ])
])

private func isolatedStore(_ name: String) -> WhatsNewStore {
    let suite = "test.whatsnew.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return WhatsNewStore(store: KeyValueStore(defaults: defaults))
}

// MARK: - AppVersion

@Suite("AppVersion ordering")
struct AppVersionTests {

    @Test("component-wise numeric comparison, not lexical")
    func numericCompare() {
        #expect(AppVersion("1.10") > AppVersion("1.9"))
        #expect(AppVersion("2.0") > AppVersion("1.99"))
        #expect(AppVersion("1.0.1") > AppVersion("1.0"))
    }

    @Test("missing trailing components count as zero")
    func trailingZeros() {
        #expect(AppVersion("1.2") == AppVersion("1.2.0"))
        #expect(AppVersion("1") == AppVersion("1.0.0"))
    }

    @Test("non-numeric suffixes are ignored")
    func nonNumericSuffix() {
        #expect(AppVersion("1.2-beta") == AppVersion("1.2"))
    }
}

// MARK: - Policy

@Suite("WhatsNewPolicy (pure show-once decision)")
struct WhatsNewPolicyTests {

    @Test("fresh install never shows What's New")
    func freshInstall() {
        #expect(WhatsNewPolicy.shouldShow(lastSeenVersion: nil, currentVersion: "1.2") == false)
        #expect(WhatsNewPolicy.shouldShow(lastSeenVersion: "", currentVersion: "1.2") == false)
    }

    @Test("same version never re-shows")
    func sameVersion() {
        #expect(WhatsNewPolicy.shouldShow(lastSeenVersion: "1.2", currentVersion: "1.2") == false)
        #expect(WhatsNewPolicy.shouldShow(lastSeenVersion: "1.2", currentVersion: "1.2.0") == false)
    }

    @Test("newer version after an update shows")
    func newerVersion() {
        #expect(WhatsNewPolicy.shouldShow(lastSeenVersion: "1.1", currentVersion: "1.2"))
        #expect(WhatsNewPolicy.shouldShow(lastSeenVersion: "1.9", currentVersion: "1.10"))
    }

    @Test("downgrade never shows")
    func downgrade() {
        #expect(WhatsNewPolicy.shouldShow(lastSeenVersion: "1.3", currentVersion: "1.2") == false)
    }
}

// MARK: - Store

@Suite("WhatsNewStore (last-seen persistence)")
struct WhatsNewStoreTests {

    @Test("starts empty, then persists the marked version")
    func markAndRead() {
        let store = isolatedStore("markAndRead")
        #expect(store.lastSeenVersion == nil)
        store.markSeen("1.4")
        #expect(store.lastSeenVersion == "1.4")
    }

    @Test("marking overwrites the previous value")
    func overwrite() {
        let store = isolatedStore("overwrite")
        store.markSeen("1.0")
        store.markSeen("1.5")
        #expect(store.lastSeenVersion == "1.5")
    }
}

// MARK: - Content provider

@Suite("WhatsNewContentProvider (bundle + selection)")
struct WhatsNewContentProviderTests {

    @Test("exact version match wins")
    func exactMatch() {
        let provider = WhatsNewContentProvider(content: sampleReleases)
        #expect(provider.release(forVersion: "1.2")?.version == "1.2")
        #expect(provider.release(forVersion: "1.0")?.version == "1.0")
    }

    @Test("falls back to newest release not newer than the current version")
    func fallbackToNewestOlder() {
        let provider = WhatsNewContentProvider(content: sampleReleases)
        // 1.1 has no exact match; newest release <= 1.1 is 1.0.
        #expect(provider.release(forVersion: "1.1")?.version == "1.0")
        // 1.5 is ahead of notes; newest available is 1.2.
        #expect(provider.release(forVersion: "1.5")?.version == "1.2")
    }

    @Test("no release when the version predates all content")
    func noneWhenTooOld() {
        let provider = WhatsNewContentProvider(content: sampleReleases)
        #expect(provider.release(forVersion: "0.9") == nil)
    }

    @Test("bundled WhatsNew.json loads and is non-empty")
    func bundledContentLoads() {
        let provider = WhatsNewContentProvider()
        #expect(provider.releases.isEmpty == false)
        let release = provider.releases.first
        #expect(release?.highlights.isEmpty == false)
    }
}

// MARK: - Model

@Suite("WhatsNewModel (coordination)")
@MainActor
struct WhatsNewModelTests {

    @Test("auto-presents after an update when content exists")
    func presentsAfterUpdate() {
        let store = isolatedStore("presentsAfterUpdate")
        store.markSeen("1.0")
        let model = WhatsNewModel(
            currentVersion: "1.2",
            provider: WhatsNewContentProvider(content: sampleReleases),
            store: store
        )
        #expect(model.shouldPresentOnLaunch)
        #expect(model.currentRelease?.version == "1.2")
    }

    @Test("does not present on a fresh install")
    func noPresentFreshInstall() {
        let model = WhatsNewModel(
            currentVersion: "1.2",
            provider: WhatsNewContentProvider(content: sampleReleases),
            store: isolatedStore("noPresentFreshInstall")
        )
        #expect(model.shouldPresentOnLaunch == false)
    }

    @Test("does not present for the same version already seen")
    func noRepresentSameVersion() {
        let store = isolatedStore("noRepresentSameVersion")
        store.markSeen("1.2")
        let model = WhatsNewModel(
            currentVersion: "1.2",
            provider: WhatsNewContentProvider(content: sampleReleases),
            store: store
        )
        #expect(model.shouldPresentOnLaunch == false)
    }

    @Test("marking seen prevents re-presentation for the same version")
    func markSeenStopsRepresent() {
        let store = isolatedStore("markSeenStopsRepresent")
        store.markSeen("1.0")
        let model = WhatsNewModel(
            currentVersion: "1.2",
            provider: WhatsNewContentProvider(content: sampleReleases),
            store: store
        )
        #expect(model.shouldPresentOnLaunch)
        model.markCurrentVersionSeen()
        // A freshly-constructed model reads the same persisted store.
        let reloaded = WhatsNewModel(
            currentVersion: "1.2",
            provider: WhatsNewContentProvider(content: sampleReleases),
            store: store
        )
        #expect(reloaded.shouldPresentOnLaunch == false)
    }

    @Test("displayRelease falls back to newest when no current match")
    func displayReleaseFallback() {
        let model = WhatsNewModel(
            currentVersion: "0.9",
            provider: WhatsNewContentProvider(content: sampleReleases),
            store: isolatedStore("displayReleaseFallback")
        )
        #expect(model.currentRelease == nil)
        #expect(model.displayRelease?.version == "1.2")
    }
}

// MARK: - Tolerant decoding (RF2)

@Suite("WhatsNew tolerant decoding")
struct WhatsNewDecodingTests {

    @Test("a malformed highlight is dropped; the rest survive")
    func malformedHighlightDropped() throws {
        let json = """
        {
          "releases": [
            {
              "version": "1.0",
              "title": "Welcome",
              "highlights": [
                { "id": "a", "symbolName": "star", "title": "A", "detail": "Good." },
                { "id": "b", "symbolName": "bolt" },
                { "id": "c", "symbolName": "leaf", "title": "C", "detail": "Also good." }
              ]
            }
          ]
        }
        """
        let content = try JSONDecoder().decode(WhatsNewContent.self, from: Data(json.utf8))
        let release = try #require(content.releases.first)
        #expect(release.highlights.count == 2)
        #expect(release.highlights.map(\.id) == ["a", "c"])
    }

    @Test("a malformed release is dropped; the rest survive")
    func malformedReleaseDropped() throws {
        let json = """
        {
          "releases": [
            { "title": "Missing version", "highlights": [] },
            { "version": "1.2", "title": "OK", "highlights": [] }
          ]
        }
        """
        let content = try JSONDecoder().decode(WhatsNewContent.self, from: Data(json.utf8))
        #expect(content.releases.count == 1)
        #expect(content.releases.first?.version == "1.2")
    }
}
