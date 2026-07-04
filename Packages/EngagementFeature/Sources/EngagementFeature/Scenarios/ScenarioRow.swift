import SwiftUI
import Models
import DesignSystem

// MARK: - ScenarioRow

/// A single row in the "My Scenarios" list showing title, scope, status, and points.
public struct ScenarioRow: View {
    let scenario: UserScenario

    public init(scenario: UserScenario) {
        self.scenario = scenario
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            HStack(alignment: .firstTextBaseline, spacing: .cfSpacing8) {
                Text(scenario.title)
                    .font(.cfBody.weight(.semibold))
                    .foregroundStyle(Color.cfLabel)
                    .lineLimit(2)
                Spacer()
                scopeTag
            }

            Text(scenario.scenario)
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
                .lineLimit(3)

            HStack {
                ScenarioStatusBadge(
                    status: scenario.status,
                    pointsAwarded: scenario.pointsAwarded
                )
                Spacer()
                Text(scenario.createdAt, style: .date)
                    .font(.cfCaption2)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
        }
        .padding(.vertical, .cfSpacing4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Private

    private var scopeTag: some View {
        Text(scopeLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.cfSecondaryLabel)
            .padding(.horizontal, .cfSpacing6)
            .padding(.vertical, 3)
            .background(Color.cfSecondaryFill, in: Capsule())
    }

    private var scopeLabel: String {
        switch scenario.scope {
        case .work:          return "Work"
        case .school:        return "School"
        case .personal:      return "Personal"
        case .unknown(let s): return s.capitalized
        }
    }

    private var accessibilityDescription: String {
        var parts: [String] = [scenario.title]
        parts.append(scopeLabel)
        switch scenario.status {
        case .pending:  parts.append("pending review")
        case .approved:
            if let pts = scenario.pointsAwarded {
                parts.append("approved, \(pts) points awarded")
            } else {
                parts.append("approved")
            }
        case .rejected: parts.append("not approved")
        case .unknown:  parts.append("status unknown")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - CGFloat helper

private extension CGFloat {
    static let cfSpacing6: CGFloat = 6
}
