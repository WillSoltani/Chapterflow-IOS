import SwiftUI
import Models
import DesignSystem

// MARK: - ScenarioStatusBadge

/// A small pill badge conveying scenario moderation status and points.
public struct ScenarioStatusBadge: View {
    let status: ScenarioStatus
    let pointsAwarded: Int?

    public init(status: ScenarioStatus, pointsAwarded: Int?) {
        self.status = status
        self.pointsAwarded = pointsAwarded
    }

    public var body: some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, .cfSpacing8)
        .padding(.vertical, .cfSpacing4)
        .background(backgroundColor.opacity(0.15), in: Capsule())
        .overlay(Capsule().stroke(backgroundColor.opacity(0.3), lineWidth: 0.5))
    }

    private var iconName: String {
        switch status {
        case .pending:          return "clock"
        case .approved:         return "checkmark.circle.fill"
        case .rejected:         return "xmark.circle.fill"
        case .unknown:          return "questionmark.circle"
        }
    }

    private var label: String {
        switch status {
        case .pending:  return "Pending review"
        case .approved:
            if let pts = pointsAwarded, pts > 0 {
                return "+\(pts) pts · Approved"
            }
            return "Approved"
        case .rejected: return "Not approved"
        case .unknown:  return "Unknown"
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .pending:          return .cfSecondaryLabel
        case .approved:         return Color(red: 0.12, green: 0.60, blue: 0.35)
        case .rejected:         return Color(red: 0.80, green: 0.25, blue: 0.20)
        case .unknown:          return .cfTertiaryLabel
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .pending:          return .cfSecondaryLabel
        case .approved:         return Color(red: 0.12, green: 0.60, blue: 0.35)
        case .rejected:         return Color(red: 0.80, green: 0.25, blue: 0.20)
        case .unknown:          return .cfTertiaryLabel
        }
    }
}
