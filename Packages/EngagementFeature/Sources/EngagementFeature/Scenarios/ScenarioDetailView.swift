import SwiftUI
import Models
import DesignSystem

// MARK: - ScenarioDetailView

/// Full-screen detail for a submitted scenario showing all fields + status.
public struct ScenarioDetailView: View {
    let scenario: UserScenario

    public init(scenario: UserScenario) {
        self.scenario = scenario
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .cfSpacing24) {
                // Status banner
                statusBanner

                // Fields
                fieldSection(label: "Your Scenario", content: scenario.scenario)
                fieldSection(label: "What To Do", content: scenario.whatToDo)
                fieldSection(label: "Why It Matters", content: scenario.whyItMatters)
            }
            .padding(.cfSpacing20)
        }
        .navigationTitle(scenario.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .background(Color.cfGroupedBackground.ignoresSafeArea())
    }

    // MARK: Private

    private var statusBanner: some View {
        HStack(spacing: .cfSpacing12) {
            Image(systemName: statusIcon)
                .font(.system(size: 28))
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: .cfSpacing4) {
                Text(statusHeadline)
                    .font(.cfBody.weight(.semibold))
                    .foregroundStyle(Color.cfLabel)
                if let sub = statusSubtitle {
                    Text(sub)
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
            }
            Spacer()
        }
        .padding(.cfSpacing16)
        .background(statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: .cfRadius12))
    }

    private var statusIcon: String {
        switch scenario.status {
        case .pending:  return "clock.fill"
        case .approved: return "checkmark.seal.fill"
        case .rejected: return "xmark.circle.fill"
        case .unknown:  return "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch scenario.status {
        case .pending:  return Color.cfSecondaryLabel
        case .approved: return Color(red: 0.12, green: 0.60, blue: 0.35)
        case .rejected: return Color(red: 0.80, green: 0.25, blue: 0.20)
        case .unknown:  return Color.cfTertiaryLabel
        }
    }

    private var statusHeadline: String {
        switch scenario.status {
        case .pending:  return "Under Review"
        case .approved: return "Approved"
        case .rejected: return "Not Approved"
        case .unknown:  return "Status Unknown"
        }
    }

    private var statusSubtitle: String? {
        switch scenario.status {
        case .pending:
            return "Our AI and moderation team will review your scenario shortly."
        case .approved:
            if let pts = scenario.pointsAwarded, pts > 0 {
                return "You earned \(pts) Flow Points for this application."
            }
            return "Great work applying what you learned!"
        case .rejected:
            return "This scenario didn't meet our guidelines. Try again with a more specific example."
        case .unknown:
            return nil
        }
    }

    @ViewBuilder
    private func fieldSection(label: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Text(label)
                .font(.cfCaption.weight(.semibold))
                .foregroundStyle(Color.cfAccent)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(content)
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.cfSpacing16)
        .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius12))
    }
}
