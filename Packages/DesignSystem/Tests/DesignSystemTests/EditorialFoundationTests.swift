import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Editorial Foundation")
struct EditorialFoundationTests {
    @Test("editorial roles map to native relative text styles")
    func typographyRoleMappings() {
        #expect(CFEditorialTextRole.allCases.count == 6)
        #expect(CFEditorialTextRole.display.relativeTextStyle == .largeTitle)
        #expect(CFEditorialTextRole.screenTitle.relativeTextStyle == .title)
        #expect(CFEditorialTextRole.sectionTitle.relativeTextStyle == .title3)
        #expect(CFEditorialTextRole.body.relativeTextStyle == .body)
        #expect(CFEditorialTextRole.metadata.relativeTextStyle == .subheadline)
        #expect(CFEditorialTextRole.caption.relativeTextStyle == .caption)
    }

    @Test("editorial fonts resolve and provide unconstrained readable leading")
    func typographyFontsResolve() {
        _ = Font.cfEditorialDisplay
        _ = Font.cfScreenTitle
        _ = Font.cfSectionTitle
        _ = Font.cfEditorialBody
        _ = Font.cfMetadata
        _ = Font.cfEditorialCaption

        #expect(CFEditorialTextRole.allCases.allSatisfy { $0.lineSpacing >= 1 })
    }

    @Test("section header stacks at accessibility sizes and retains a 44 point action target")
    @MainActor
    func sectionHeaderLayoutContract() {
        #expect(!CFEditorialSectionHeader.usesStackedLayout(for: .large))
        #expect(CFEditorialSectionHeader.usesStackedLayout(for: .accessibility1))
        #expect(CFEditorialSectionHeader.usesStackedLayout(for: .accessibility5))
        #expect(CFEditorialSectionHeader.minimumActionTarget >= 44)
        #expect(CFEditorialSectionHeader.minimumActionTarget == .cfIconLarge)
    }

    @Test("inline states have distinct noncolor indicators and retry semantics")
    func inlineStateSemantics() {
        #expect(CFInlineState.Kind.allCases.count == 4)
        #expect(Set(CFInlineState.Kind.allCases.map(\.indicatorName)).count == 4)
        #expect(!CFInlineState.Kind.loading.supportsRetry)
        #expect(!CFInlineState.Kind.empty.supportsRetry)
        #expect(CFInlineState.Kind.error.supportsRetry)
        #expect(CFInlineState.Kind.offline.supportsRetry)
    }

    @Test("inline state stores approved copy instead of arbitrary Error values")
    func inlineStatePayloadContract() {
        let state = CFInlineState(
            kind: .error,
            title: "Highlights could not load",
            message: "Your saved highlights are still safe."
        )

        let storedFields = Mirror(reflecting: state).children.compactMap(\.label)
        #expect(storedFields == ["kind", "title", "message"])
        #expect(state.title == "Highlights could not load")
        #expect(state.message == "Your saved highlights are still safe.")
    }

    @Test("retry is absent by default and only retained for recoverable states")
    @MainActor
    func retryPresenceContract() {
        let retry = CFInlineRetryAction("Try Again") {}
        let error = CFInlineState(kind: .error, title: "Could not load")
        let empty = CFInlineState(kind: .empty, title: "Nothing here")

        #expect(!CFInlineStateView(state: error).showsRetry)
        #expect(CFInlineStateView(state: error, retryAction: retry).showsRetry)
        #expect(!CFInlineStateView(state: empty, retryAction: retry).showsRetry)
        #expect(CFInlineStateView.minimumActionTarget >= 44)
    }

    @Test("VoiceOver contract orders heading, message, then action")
    @MainActor
    func inlineAccessibilityOrder() {
        let view = CFInlineStateView(
            state: CFInlineState(
                kind: .offline,
                title: "You're offline",
                message: "Reconnect to refresh this section."
            ),
            retryAction: CFInlineRetryAction("Retry") {}
        )

        #expect(
            view.accessibilityOrder == [
                "You're offline",
                "Reconnect to refresh this section.",
                "Retry",
            ]
        )
    }

    @Test("Reduce Motion disables inline state animation")
    @MainActor
    func reduceMotionPolicy() {
        #expect(CFInlineStateView.animatesStateChanges(reduceMotion: false))
        #expect(!CFInlineStateView.animatesStateChanges(reduceMotion: true))
    }
}
