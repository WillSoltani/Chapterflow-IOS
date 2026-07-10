import Testing
import Foundation
@testable import NotificationsFeature
import Models

// MARK: - Decoding tests (RF2)

@Suite("NotificationInbox — decoding")
struct NotificationInboxDecodingTests {

    @Test("Decodes a valid notifications response")
    func decodesValidResponse() throws {
        let json = """
        {
            "notifications": [
                {
                    "notificationId": "n1",
                    "type": "badge_earned",
                    "title": "Badge!",
                    "body": "You earned a badge.",
                    "isRead": false,
                    "createdAt": "2024-01-16T10:00:00.000Z",
                    "deepLink": "chapterflow://profile"
                }
            ],
            "unreadCount": 1
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(NotificationsResponse.self, from: data)
        #expect(response.notifications.count == 1)
        #expect(response.unreadCount == 1)
        #expect(response.notifications[0].notificationId == "n1")
        #expect(response.notifications[0].type == .badgeEarned)
        #expect(response.notifications[0].isRead == false)
    }

    @Test("RF2: unknown notification type decodes to .unknown instead of crashing")
    func unknownTypeDecodesToUnknown() throws {
        let json = """
        {
            "notifications": [
                {
                    "notificationId": "nx",
                    "type": "future_server_type",
                    "title": "Future event",
                    "body": "Something the client doesn't know about yet.",
                    "isRead": false,
                    "createdAt": "2024-01-16T10:00:00Z",
                    "deepLink": null
                }
            ],
            "unreadCount": 1
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(NotificationsResponse.self, from: data)
        #expect(response.notifications.count == 1)
        if case .unknown(let raw) = response.notifications[0].type {
            #expect(raw == "future_server_type")
        } else {
            Issue.record("Expected .unknown(\"future_server_type\"), got \(response.notifications[0].type)")
        }
    }

    @Test("RF2: element missing the identity field is dropped; rest survive (decodeLossy)")
    func malformedElementDropped() throws {
        // Post-reconciliation only `notificationId` is required (a missing
        // title defaults to "" — the deployed inbox items can omit display
        // fields). An element with NO identity is still dropped.
        let json = """
        {
            "notifications": [
                {
                    "notificationId": "n1",
                    "type": "review_due",
                    "title": "Valid",
                    "body": "Valid body.",
                    "isRead": true,
                    "createdAt": "2024-01-16T10:00:00Z"
                },
                {
                    "type": "badge_earned",
                    "body": "Missing notificationId — should be dropped.",
                    "isRead": false,
                    "createdAt": "2024-01-16T11:00:00Z"
                }
            ],
            "unreadCount": 1
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(NotificationsResponse.self, from: data)
        // Only the element with an identity survives.
        #expect(response.notifications.count == 1)
        #expect(response.notifications[0].notificationId == "n1")
    }

    @Test("deployed readAt string/null maps to isRead")
    func readAtMapsToIsRead() throws {
        let json = """
        {
            "notifications": [
                {
                    "notificationId": "n1",
                    "type": "badge_earned",
                    "title": "T",
                    "body": "B",
                    "channel": "inapp",
                    "readAt": null,
                    "createdAt": "2026-07-09T10:00:00Z"
                },
                {
                    "notificationId": "n2",
                    "type": "badge_earned",
                    "title": "T2",
                    "body": "B2",
                    "channel": "inapp",
                    "readAt": "2026-07-09T11:00:00Z",
                    "createdAt": "2026-07-09T10:30:00Z"
                }
            ],
            "unreadCount": 1
        }
        """
        let response = try JSONDecoder().decode(NotificationsResponse.self, from: Data(json.utf8))
        #expect(response.notifications.count == 2)
        #expect(response.notifications.first { $0.notificationId == "n1" }?.isRead == false)
        #expect(response.notifications.first { $0.notificationId == "n2" }?.isRead == true)
    }

    @Test("Decodes ISO-8601 date with and without fractional seconds")
    func decodesISODateVariants() throws {
        let jsonWithFractional = """
        {
            "notifications": [{
                "notificationId": "n1", "type": "review_due",
                "title": "T", "body": "B", "isRead": false,
                "createdAt": "2024-01-16T10:00:00.000Z"
            }],
            "unreadCount": 0
        }
        """
        let jsonWithout = jsonWithFractional.replacingOccurrences(
            of: "2024-01-16T10:00:00.000Z",
            with: "2024-01-16T10:00:00Z"
        )
        let r1 = try JSONDecoder().decode(NotificationsResponse.self, from: Data(jsonWithFractional.utf8))
        let r2 = try JSONDecoder().decode(NotificationsResponse.self, from: Data(jsonWithout.utf8))
        #expect(r1.notifications[0].createdAt == "2024-01-16T10:00:00.000Z")
        #expect(r2.notifications[0].createdAt == "2024-01-16T10:00:00Z")
    }

    @Test("Optional deepLink field is nil when absent")
    func optionalDeepLinkNil() throws {
        let json = """
        {
            "notifications": [{
                "notificationId": "n1", "type": "streak_reminder",
                "title": "T", "body": "B", "isRead": false,
                "createdAt": "2024-01-16T10:00:00Z"
            }],
            "unreadCount": 0
        }
        """
        let response = try JSONDecoder().decode(NotificationsResponse.self, from: Data(json.utf8))
        #expect(response.notifications[0].deepLink == nil)
    }
}

// MARK: - Routing tests

@Suite("NotificationInbox — routing")
struct NotificationInboxRoutingTests {

    @Test("Uses explicit deepLink field when present and valid chapterflow:// URL")
    func usesExplicitDeepLink() {
        let notif = AppNotification(
            notificationId: "n1",
            type: .badgeEarned,
            title: "T",
            body: "B",
            isRead: false,
            createdAt: "2024-01-16T10:00:00Z",
            deepLink: "chapterflow://profile/badges"
        )
        let url = NotificationInboxModel.routingURL(for: notif)
        #expect(url?.absoluteString == "chapterflow://profile/badges")
    }

    @Test("Falls back to type-based URL when deepLink is nil")
    func fallsBackToTypeBased() {
        let notif = AppNotification(
            notificationId: "n2",
            type: .reviewDue,
            title: "T",
            body: "B",
            isRead: false,
            createdAt: "2024-01-16T10:00:00Z",
            deepLink: nil
        )
        let url = NotificationInboxModel.routingURL(for: notif)
        #expect(url?.absoluteString == "chapterflow://review")
    }

    @Test("RF2: unknown type routes to engagement (never crashes)")
    func unknownTypeRoutesToEngagement() {
        let notif = AppNotification(
            notificationId: "n3",
            type: .unknown("future_thing"),
            title: "T",
            body: "B",
            isRead: false,
            createdAt: "2024-01-16T10:00:00Z",
            deepLink: nil
        )
        let url = NotificationInboxModel.routingURL(for: notif)
        #expect(url?.absoluteString == "chapterflow://engagement")
    }

    @Test("Ignores deepLink with non-chapterflow scheme")
    func ignoresNonChapterflowScheme() {
        let notif = AppNotification(
            notificationId: "n4",
            type: .badgeEarned,
            title: "T",
            body: "B",
            isRead: false,
            createdAt: "2024-01-16T10:00:00Z",
            deepLink: "https://example.com/profile"
        )
        let url = NotificationInboxModel.routingURL(for: notif)
        // Falls through to type fallback, not the https URL
        #expect(url?.scheme == "chapterflow")
    }
}
