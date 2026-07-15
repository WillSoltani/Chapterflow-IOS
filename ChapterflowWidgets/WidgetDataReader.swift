import Foundation
import SwiftUI
import WidgetKit

// MARK: - Shared state keys
// Must stay in sync with SharedStateKeys in Persistence/SharedStateWriter.swift

private enum Keys {
    static let streakDays          = "shared.streakDays"
    static let longestStreak       = "shared.longestStreak"
    static let streakShieldsHeld   = "shared.streakShieldsHeld"
    static let streakAtRisk        = "shared.streakAtRisk"
    static let dueReviewCount      = "shared.dueReviewCount"
    static let dailyGoalMinutes    = "shared.dailyGoalMinutes"
    static let goalProgressMinutes = "shared.goalProgressMinutes"
    static let continueBookId          = "shared.continueBookId"
    static let continueBookTitle       = "shared.continueBookTitle"
    static let continueBookCoverEmoji  = "shared.continueBookCoverEmoji"
    static let continueBookCoverColor  = "shared.continueBookCoverColor"
    static let continueChapterNumber   = "shared.continueChapterNumber"
    static let continueProgress        = "shared.continueProgress"
    static let lastUpdated             = "shared.lastUpdated"
}

private let appGroupID = "group.com.chapterflow"
private let goalTiers = [10, 20, 30]
private let defaultGoalMinutes = 10

// MARK: - WidgetSnapshot

/// Snapshot of widget-relevant user state read from the App Group.
///
/// Mirrors `SharedAppStateSnapshot` in the Persistence module.
/// Both structs must stay in sync (same keys, same field semantics).
struct WidgetSnapshot: Sendable {
    var streakDays: Int
    var longestStreak: Int
    var streakShieldsHeld: Int
    var streakAtRisk: Bool
    var continueBookId: String?
    var continueBookTitle: String?
    var continueBookCoverEmoji: String?
    var continueBookCoverColor: String?
    var continueChapterNumber: Int?
    var continueProgress: Double?
    var dueReviewCount: Int
    var dailyGoalMinutes: Int
    var goalProgressMinutes: Int
    var lastUpdated: Date
    var isAccountDataAvailable: Bool = true

    var goalFraction: Double {
        guard dailyGoalMinutes > 0 else { return 0 }
        return min(1.0, Double(goalProgressMinutes) / Double(dailyGoalMinutes))
    }

    var hasContinueReading: Bool { continueBookId != nil }
    var isDailyGoalMet: Bool { goalFraction >= 1.0 }

    // MARK: - Factory

    static func load() -> WidgetSnapshot {
        // Legacy App Group values have no provable account owner. Preserve them
        // untouched for WP-ID-01B, but never display or deep-link them under the
        // account that happens to be active when WidgetKit asks for a timeline.
        .ownerlessQuarantined
    }

    static let ownerlessQuarantined = WidgetSnapshot(
        streakDays: 0,
        longestStreak: 0,
        streakShieldsHeld: 0,
        streakAtRisk: false,
        continueBookId: nil,
        continueBookTitle: nil,
        continueBookCoverEmoji: nil,
        continueBookCoverColor: nil,
        continueChapterNumber: nil,
        continueProgress: nil,
        dueReviewCount: 0,
        dailyGoalMinutes: defaultGoalMinutes,
        goalProgressMinutes: 0,
        lastUpdated: .distantPast,
        isAccountDataAvailable: false
    )

    static let placeholder = WidgetSnapshot(
        streakDays: 12,
        longestStreak: 30,
        streakShieldsHeld: 1,
        streakAtRisk: false,
        continueBookId: "placeholder",
        continueBookTitle: "Atomic Habits",
        continueBookCoverEmoji: "⚛️",
        continueBookCoverColor: "#3A86FF",
        continueChapterNumber: 5,
        continueProgress: 0.62,
        dueReviewCount: 7,
        dailyGoalMinutes: 20,
        goalProgressMinutes: 14,
        lastUpdated: Date()
    )
}

/// Fail-closed presentation used while App Group snapshots are ownerless.
/// It never turns quarantine defaults into claims about the current account.
struct WidgetAccountDataUnavailableView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "person.crop.circle.badge.questionmark")
                }
            case .accessoryInline:
                Label("Open ChapterFlow", systemImage: "book.closed")
            case .accessoryRectangular:
                Label("Account data unavailable", systemImage: "book.closed")
                    .font(.system(size: 13, weight: .semibold))
            default:
                VStack(spacing: .wS8) {
                    Image(systemName: "book.closed.fill")
                        .font(.title2)
                        .foregroundStyle(Color.cfWidgetAccent)
                    Text("Open ChapterFlow")
                        .font(.headline)
                    Text("Account data is unavailable here.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.wS16)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "chapterflow://library"))
    }
}

// MARK: - Widget design tokens (mirrors DesignSystem values)

extension Color {
    /// Brand accent — matches `Color.cfAccent` in DesignSystem.
    static let cfWidgetAccent = Color(red: 0.18, green: 0.40, blue: 0.82)
    /// Flame orange for streak indicators.
    static let cfWidgetFlame  = Color(red: 1.0, green: 0.45, blue: 0.15)

    /// Initialises a `Color` from a hex string like "#3A86FF" or "3A86FF".
    /// Returns `nil` when the string is not a valid 6-digit hex.
    init?(hexString: String?) {
        guard let raw = hexString?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#")),
              raw.count == 6,
              let value = UInt64(raw, radix: 16)
        else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double(value         & 0xFF) / 255
        )
    }
}

extension CGFloat {
    static let wS4:  CGFloat = 4
    static let wS8:  CGFloat = 8
    static let wS12: CGFloat = 12
    static let wS16: CGFloat = 16
}
