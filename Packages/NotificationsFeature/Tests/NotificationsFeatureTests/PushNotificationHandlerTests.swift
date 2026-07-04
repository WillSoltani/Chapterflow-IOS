import Testing
import Foundation
import CoreKit
@testable import NotificationsFeature

// MARK: - PushNotificationHandler routing tests

@Suite("PushNotificationHandler")
struct PushNotificationHandlerTests {

    // MARK: - Explicit deepLink in payload

    @Test("explicit deepLink in payload is used verbatim")
    func explicitDeepLink() {
        let url = handler(
            userInfo: ["deepLink": "chapterflow://review", "type": "streak_at_risk"],
            action: "com.apple.UNNotificationDefaultActionIdentifier"
        )
        #expect(url.absoluteString == "chapterflow://review")
    }

    @Test("non-chapterflow deepLink in payload is ignored; falls back to type routing")
    func invalidDeepLinkFallsBack() {
        let url = handler(
            userInfo: ["deepLink": "https://example.com", "type": "streak_at_risk"],
            action: "com.apple.UNNotificationDefaultActionIdentifier"
        )
        // streak_at_risk default → review
        #expect(url.absoluteString == "chapterflow://review")
    }

    // MARK: - Per-type routing (default action / tap)

    let defaultAction = "com.apple.UNNotificationDefaultActionIdentifier"

    @Test("badge_earned routes to engagement")
    func badgeEarned() {
        let url = handler(userInfo: ["type": "badge_earned"], action: defaultAction)
        #expect(url.absoluteString == "chapterflow://engagement")
    }

    @Test("tier_up routes to engagement")
    func tierUp() {
        let url = handler(userInfo: ["type": "tier_up"], action: defaultAction)
        #expect(url.absoluteString == "chapterflow://engagement")
    }

    @Test("streak_milestone routes to engagement")
    func streakMilestone() {
        let url = handler(userInfo: ["type": "streak_milestone"], action: defaultAction)
        #expect(url.absoluteString == "chapterflow://engagement")
    }

    @Test("streak_at_risk routes to review")
    func streakAtRisk() {
        let url = handler(userInfo: ["type": "streak_at_risk"], action: defaultAction)
        #expect(url.absoluteString == "chapterflow://review")
    }

    @Test("partner_nudge routes to profile")
    func partnerNudge() {
        let url = handler(userInfo: ["type": "partner_nudge"], action: defaultAction)
        #expect(url.absoluteString == "chapterflow://profile")
    }

    @Test("event_reminder routes to engagement")
    func eventReminder() {
        let url = handler(userInfo: ["type": "event_reminder"], action: defaultAction)
        #expect(url.absoluteString == "chapterflow://engagement")
    }

    @Test("scenario_approved routes to engagement")
    func scenarioApproved() {
        let url = handler(userInfo: ["type": "scenario_approved"], action: defaultAction)
        #expect(url.absoluteString == "chapterflow://engagement")
    }

    @Test("scenario_rejected routes to engagement")
    func scenarioRejected() {
        let url = handler(userInfo: ["type": "scenario_rejected"], action: defaultAction)
        #expect(url.absoluteString == "chapterflow://engagement")
    }

    // MARK: - insight_spark / reading_reminder / commitment_followup with chapter payload

    @Test("insight_spark with bookId+chapterNumber routes to chapter")
    func insightSparkWithChapter() {
        let url = handler(
            userInfo: ["type": "insight_spark", "bookId": "b-123", "chapterNumber": 4],
            action: defaultAction
        )
        #expect(url.absoluteString == "chapterflow://book/b-123/chapter/4")
    }

    @Test("insight_spark without chapter info routes to engagement")
    func insightSparkNoChapter() {
        let url = handler(userInfo: ["type": "insight_spark"], action: defaultAction)
        #expect(url.absoluteString == "chapterflow://engagement")
    }

    @Test("reading_reminder with chapter routes to chapter")
    func readingReminderWithChapter() {
        let url = handler(
            userInfo: ["type": "reading_reminder", "bookId": "b-abc", "chapterNumber": 2],
            action: defaultAction
        )
        #expect(url.absoluteString == "chapterflow://book/b-abc/chapter/2")
    }

    @Test("reading_reminder without chapter routes to library")
    func readingReminderNoChapter() {
        let url = handler(userInfo: ["type": "reading_reminder"], action: defaultAction)
        #expect(url.absoluteString == "chapterflow://library")
    }

    @Test("commitment_followup with chapter routes to chapter")
    func commitmentFollowupWithChapter() {
        let url = handler(
            userInfo: ["type": "commitment_followup", "bookId": "b-xyz", "chapterNumber": 7],
            action: defaultAction
        )
        #expect(url.absoluteString == "chapterflow://book/b-xyz/chapter/7")
    }

    @Test("commitment_followup without chapter routes to library")
    func commitmentFollowupNoChapter() {
        let url = handler(userInfo: ["type": "commitment_followup"], action: defaultAction)
        #expect(url.absoluteString == "chapterflow://library")
    }

    // MARK: - Inline action overrides

    @Test("OPEN_CHAPTER action with bookId+chapterNumber routes to chapter")
    func openChapterActionWithPayload() {
        let url = handler(
            userInfo: ["type": "reading_reminder", "bookId": "b-1", "chapterNumber": 3],
            action: "CF_ACTION_OPEN_CHAPTER"
        )
        #expect(url.absoluteString == "chapterflow://book/b-1/chapter/3")
    }

    @Test("OPEN_CHAPTER action without chapter info routes to library")
    func openChapterActionNoPayload() {
        let url = handler(
            userInfo: ["type": "reading_reminder"],
            action: "CF_ACTION_OPEN_CHAPTER"
        )
        #expect(url.absoluteString == "chapterflow://library")
    }

    @Test("REVIEW_NOW action routes to review regardless of type")
    func reviewNowAction() {
        let url = handler(
            userInfo: ["type": "streak_at_risk"],
            action: "CF_ACTION_REVIEW_NOW"
        )
        #expect(url.absoluteString == "chapterflow://review")
    }

    // MARK: - RF2: unknown type is handled safely

    @Test("RF2: completely unknown type routes to engagement — never crashes")
    func unknownTypeSafeDefault() {
        let url = handler(
            userInfo: ["type": "a_brand_new_server_type_2026"],
            action: defaultAction
        )
        #expect(url.absoluteString == "chapterflow://engagement")
    }

    @Test("RF2: missing type key routes to engagement")
    func missingTypeSafeDefault() {
        let url = handler(userInfo: [:], action: defaultAction)
        #expect(url.absoluteString == "chapterflow://engagement")
    }

    // MARK: - chapterNumber as String (some push providers stringify numbers)

    @Test("chapterNumber as string is parsed correctly")
    func chapterNumberAsString() {
        let url = handler(
            userInfo: ["type": "reading_reminder", "bookId": "b-1", "chapterNumber": "5"],
            action: defaultAction
        )
        #expect(url.absoluteString == "chapterflow://book/b-1/chapter/5")
    }

    // MARK: - Helper

    private func handler(userInfo: [AnyHashable: Any], action: String) -> URL {
        PushNotificationHandler.routingURL(userInfo: userInfo, actionIdentifier: action)
    }
}
