import SwiftUI
import Models
import DesignSystem

/// A compact badge row surfacing the two completion axes for a chapter.
///
/// - **Knowledge**: whether the chapter's quiz has been passed (server truth).
/// - **Application**: the user's self-reported commitment level
///   (none / committed / applied), sourced from `applicationStates` on the
///   book-state endpoint. This axis is NOT a gate — it is displayed alongside
///   the knowledge axis purely for the user's reference.
///
/// The row is hidden entirely when neither axis is active (`!isKnowledgeComplete`
/// and `applicationState == .none`) to avoid visual clutter on untouched chapters.
public struct ChapterCompletionBadgesView: View {
    public let isKnowledgeComplete: Bool
    public let applicationState: ChapterApplicationState

    public init(isKnowledgeComplete: Bool, applicationState: ChapterApplicationState) {
        self.isKnowledgeComplete = isKnowledgeComplete
        self.applicationState = applicationState
    }

    public var body: some View {
        HStack(spacing: .cfSpacing8) {
            if isKnowledgeComplete {
                knowledgeBadge
            }
            if applicationState != .none {
                applicationBadge
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Knowledge badge

    private var knowledgeBadge: some View {
        Label("Knowledge", systemImage: "checkmark.seal.fill")
            .font(.cfCaption)
            .foregroundStyle(Color.cfAccent)
            .padding(.horizontal, .cfSpacing8)
            .padding(.vertical, .cfSpacing4)
            .background(
                Capsule()
                    .fill(Color.cfAccent.opacity(0.12))
            )
            .accessibilityHidden(true)
    }

    // MARK: - Application badge

    private var applicationBadge: some View {
        Label(applicationLabel, systemImage: applicationIcon)
            .font(.cfCaption)
            .foregroundStyle(applicationColor)
            .padding(.horizontal, .cfSpacing8)
            .padding(.vertical, .cfSpacing4)
            .background(
                Capsule()
                    .fill(applicationColor.opacity(0.12))
            )
            .accessibilityHidden(true)
    }

    private var applicationLabel: String {
        switch applicationState {
        case .none:     return ""
        case .committed: return "Committed"
        case .applied:   return "Applied"
        case .unknown:   return "In Progress"
        }
    }

    private var applicationIcon: String {
        switch applicationState {
        case .none:     return "circle"
        case .committed: return "flag.fill"
        case .applied:   return "star.fill"
        case .unknown:   return "clock.fill"
        }
    }

    private var applicationColor: Color {
        switch applicationState {
        case .none:     return Color.cfSecondaryLabel
        case .committed: return Color.orange
        case .applied:   return Color.green
        case .unknown:   return Color.cfSecondaryLabel
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts: [String] = []
        if isKnowledgeComplete { parts.append("Knowledge complete") }
        switch applicationState {
        case .none: break
        case .committed: parts.append("Application: committed")
        case .applied:   parts.append("Application: applied")
        case .unknown(let s): parts.append("Application: \(s)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Both axes — light") {
    VStack(spacing: .cfSpacing16) {
        ChapterCompletionBadgesView(isKnowledgeComplete: true, applicationState: .applied)
        ChapterCompletionBadgesView(isKnowledgeComplete: true, applicationState: .committed)
        ChapterCompletionBadgesView(isKnowledgeComplete: true, applicationState: .none)
        ChapterCompletionBadgesView(isKnowledgeComplete: false, applicationState: .committed)
        ChapterCompletionBadgesView(isKnowledgeComplete: false, applicationState: .none)
    }
    .padding()
    .background(Color.cfBackground)
}

#Preview("Both axes — dark") {
    VStack(spacing: .cfSpacing16) {
        ChapterCompletionBadgesView(isKnowledgeComplete: true, applicationState: .applied)
        ChapterCompletionBadgesView(isKnowledgeComplete: true, applicationState: .committed)
        ChapterCompletionBadgesView(isKnowledgeComplete: false, applicationState: .none)
    }
    .padding()
    .background(Color.cfBackground)
    .preferredColorScheme(.dark)
}

#Preview("Both axes — XXL") {
    ChapterCompletionBadgesView(isKnowledgeComplete: true, applicationState: .applied)
        .padding()
        .background(Color.cfBackground)
        .dynamicTypeSize(.accessibility3)
}
#endif
