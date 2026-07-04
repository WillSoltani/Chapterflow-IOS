import Testing
import Foundation
@testable import NotificationsFeature

// MARK: - PushNotificationType — RF2 evolution tests

@Suite("PushNotificationType")
struct PushNotificationTypeTests {

    // MARK: Known raw values

    @Test("badge_earned decodes correctly")
    func badgeEarned() {
        #expect(PushNotificationType(rawValue: "badge_earned") == .badgeEarned)
    }

    @Test("tier_up decodes correctly")
    func tierUp() {
        #expect(PushNotificationType(rawValue: "tier_up") == .tierUp)
    }

    @Test("streak_milestone decodes correctly")
    func streakMilestone() {
        #expect(PushNotificationType(rawValue: "streak_milestone") == .streakMilestone)
    }

    @Test("insight_spark decodes correctly")
    func insightSpark() {
        #expect(PushNotificationType(rawValue: "insight_spark") == .insightSpark)
    }

    @Test("reading_reminder decodes correctly")
    func readingReminder() {
        #expect(PushNotificationType(rawValue: "reading_reminder") == .readingReminder)
    }

    @Test("streak_at_risk decodes correctly")
    func streakAtRisk() {
        #expect(PushNotificationType(rawValue: "streak_at_risk") == .streakAtRisk)
    }

    @Test("partner_nudge decodes correctly")
    func partnerNudge() {
        #expect(PushNotificationType(rawValue: "partner_nudge") == .partnerNudge)
    }

    @Test("commitment_followup decodes correctly")
    func commitmentFollowup() {
        #expect(PushNotificationType(rawValue: "commitment_followup") == .commitmentFollowup)
    }

    @Test("event_reminder decodes correctly")
    func eventReminder() {
        #expect(PushNotificationType(rawValue: "event_reminder") == .eventReminder)
    }

    @Test("scenario_approved decodes correctly")
    func scenarioApproved() {
        #expect(PushNotificationType(rawValue: "scenario_approved") == .scenarioApproved)
    }

    @Test("scenario_rejected decodes correctly")
    func scenarioRejected() {
        #expect(PushNotificationType(rawValue: "scenario_rejected") == .scenarioRejected)
    }

    // MARK: RF2 — unknown raw values

    @Test("RF2: unrecognised type decodes to .unknown, never crashes")
    func unknownTypeDoesNotCrash() {
        let type = PushNotificationType(rawValue: "some_future_type_v2")
        guard case .unknown(let raw) = type else {
            Issue.record("Expected .unknown, got \(type)")
            return
        }
        #expect(raw == "some_future_type_v2")
    }

    @Test("RF2: empty string decodes to .unknown")
    func emptyStringIsUnknown() {
        guard case .unknown = PushNotificationType(rawValue: "") else {
            Issue.record("Expected .unknown for empty string")
            return
        }
    }

    // MARK: Round-trip

    @Test("rawValue round-trips for all known types")
    func rawValueRoundTrip() {
        let known = PushNotificationType.known
        for type in known {
            #expect(PushNotificationType(rawValue: type.rawValue) == type)
        }
    }

    // MARK: Category identifiers

    @Test("each known type has a unique category identifier")
    func uniqueCategoryIdentifiers() {
        let ids = PushNotificationType.known.map(\.categoryIdentifier)
        let unique = Set(ids)
        #expect(ids.count == unique.count)
    }

    @Test("unknown type maps to CF_GENERAL category")
    func unknownCategoryIsGeneral() {
        #expect(PushNotificationType.unknown("anything").categoryIdentifier == "CF_GENERAL")
    }
}
