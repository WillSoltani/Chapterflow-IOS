import SwiftUI
import DesignSystem
import Models

// MARK: - TierExplainerView

/// Sheet that explains all five tiers and what advances the user.
///
/// Highlight the current tier; dim the ones the user hasn't reached yet.
struct TierExplainerView: View {

    let currentTier: TierKey

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: .cfSpacing16) {
                    metricsExplainer
                    Divider()
                    tierLadder
                }
                .padding(.cfSpacing16)
            }
            .background(Color.cfGroupedBackground.ignoresSafeArea())
            .navigationTitle("Tier Levels")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Metrics explainer

    private var metricsExplainer: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Text("How You Advance")
                .font(.cfTitle3.weight(.semibold))
                .foregroundStyle(Color.cfLabel)

            Text("Your tier reflects depth and breadth of learning. Three metrics are tracked:")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: .cfSpacing8) {
                metricRow(
                    icon: "checkmark.seal.fill",
                    color: Color.cfAccent,
                    title: "Loops Completed",
                    detail: "Finish a chapter's quiz successfully to complete a loop."
                )
                metricRow(
                    icon: "chart.bar.fill",
                    color: .green,
                    title: "Average Quiz Score",
                    detail: "Your average score across all loops in the current tier period."
                )
                metricRow(
                    icon: "books.vertical.fill",
                    color: .orange,
                    title: "Categories Explored",
                    detail: "Unique book categories you've completed at least one loop in."
                )
            }
        }
        .padding(.cfSpacing16)
        .background {
            RoundedRectangle(cornerRadius: .cfRadius12)
                .fill(Color.cfSecondaryBackground)
        }
    }

    private func metricRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: .cfSpacing12) {
            Image(systemName: icon)
                .font(.cfSubheadline)
                .foregroundStyle(color)
                .frame(width: .cfIconSmall)

            VStack(alignment: .leading, spacing: .cfSpacing2) {
                Text(title)
                    .font(.cfSubheadline.weight(.medium))
                    .foregroundStyle(Color.cfLabel)
                Text(detail)
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(detail)")
    }

    // MARK: - Tier ladder

    private var tierLadder: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Text("The Tiers")
                .font(.cfTitle3.weight(.semibold))
                .foregroundStyle(Color.cfLabel)

            VStack(spacing: 0) {
                ForEach(Array(TierKey.allCases.reversed().enumerated()), id: \.element.rawValue) { index, tier in
                    if index > 0 {
                        connectorLine
                    }
                    tierRow(tier)
                }
            }
        }
    }

    private var connectorLine: some View {
        HStack {
            Spacer()
                .frame(width: .cfSpacing48 + .cfSpacing12)
            Rectangle()
                .fill(Color.cfSeparator)
                .frame(width: 2, height: .cfSpacing20)
            Spacer()
        }
    }

    private func tierRow(_ tier: TierKey) -> some View {
        let isCurrent = tier == currentTier
        let isReached = tier.rank <= currentTier.rank

        return HStack(alignment: .top, spacing: .cfSpacing16) {
            ZStack {
                Circle()
                    .fill(isReached ? tierColor(tier).opacity(0.15) : Color.cfSecondaryFill)
                Image(systemName: tierSystemImage(tier))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isReached ? tierColor(tier) : Color.cfTertiaryLabel)
            }
            .frame(width: .cfSpacing48, height: .cfSpacing48)

            VStack(alignment: .leading, spacing: .cfSpacing4) {
                HStack(spacing: .cfSpacing8) {
                    Text(tier.displayName)
                        .font(isCurrent ? .cfSubheadline.weight(.bold) : .cfSubheadline.weight(.medium))
                        .foregroundStyle(isReached ? Color.cfLabel : Color.cfTertiaryLabel)
                    if isCurrent {
                        Text("Current")
                            .font(.cfCaption.weight(.semibold))
                            .foregroundStyle(tierColor(tier))
                            .padding(.horizontal, .cfSpacing8)
                            .padding(.vertical, .cfSpacing2)
                            .background {
                                Capsule()
                                    .fill(tierColor(tier).opacity(0.15))
                            }
                    }
                }
                Text(tierDescription(tier))
                    .font(.cfCaption)
                    .foregroundStyle(isReached ? Color.cfSecondaryLabel : Color.cfTertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                if !isReached && tier.rank != TierKey.reader.rank {
                    Text(tierRequirement(tier))
                        .font(.cfCaption2)
                        .foregroundStyle(Color.cfTertiaryLabel)
                        .padding(.top, .cfSpacing2)
                }
            }

            Spacer()
        }
        .padding(.cfSpacing12)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: .cfRadius12)
                    .fill(tierColor(tier).opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: .cfRadius12)
                            .strokeBorder(tierColor(tier).opacity(0.25), lineWidth: 1)
                    }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: tier, isCurrent: isCurrent))
    }

    // MARK: - Helpers

    private func accessibilityLabel(for tier: TierKey, isCurrent: Bool) -> String {
        var label = tier.displayName
        if isCurrent { label += ", current tier" }
        label += ". " + tierDescription(tier)
        return label
    }
}

// MARK: - TierKey display helpers (internal to EngagementFeature)

extension TierKey {
    var displayName: String {
        switch self {
        case .reader:      return "Reader"
        case .analyst:     return "Analyst"
        case .synthesizer: return "Synthesizer"
        case .polymath:    return "Polymath"
        case .luminary:    return "Luminary"
        case .unknown(let s): return s.capitalized
        }
    }
}

// MARK: - Free functions shared with TierView

func tierColor(_ tier: TierKey) -> Color {
    switch tier {
    case .reader:      return .secondary
    case .analyst:     return Color(red: 0.18, green: 0.40, blue: 0.82) // cfAccent
    case .synthesizer: return .green
    case .polymath:    return .orange
    case .luminary:    return Color(red: 0.95, green: 0.75, blue: 0.20) // gold
    case .unknown:     return .secondary
    }
}

func tierSystemImage(_ tier: TierKey) -> String {
    switch tier {
    case .reader:      return "book.fill"
    case .analyst:     return "magnifyingglass"
    case .synthesizer: return "arrow.triangle.merge"
    case .polymath:    return "brain.head.profile"
    case .luminary:    return "star.fill"
    case .unknown:     return "questionmark.circle"
    }
}

func tierDescription(_ tier: TierKey) -> String {
    switch tier {
    case .reader:
        return "You're building a reading habit. Complete loops and explore new books to advance."
    case .analyst:
        return "You examine ideas critically and quiz yourself consistently. Keep exploring more categories."
    case .synthesizer:
        return "You connect ideas across books and domains. A broad, high-scoring learner."
    case .polymath:
        return "Mastery across many fields. Your average scores and loop count put you in the top tier."
    case .luminary:
        return "The highest level. You exemplify consistent, deep, and diverse learning."
    case .unknown:
        return "A tier the app hasn't seen before. Keep learning!"
    }
}

func tierRequirement(_ tier: TierKey) -> String {
    switch tier {
    case .reader:
        return "Starting tier — everyone begins here."
    case .analyst:
        return "Complete loops and maintain a solid quiz average."
    case .synthesizer:
        return "More loops, higher scores, and at least 3 categories explored."
    case .polymath:
        return "Consistently high scores across 5+ categories."
    case .luminary:
        return "Top scores across many categories with a large loop count."
    case .unknown:
        return ""
    }
}
