import SwiftUI
import DesignSystem

/// A single row in the reflections history list.
///
/// Shows the reflection text, date stamp, a "pending" badge when not yet synced,
/// and the AI feedback (or a "Get feedback" button when feedback hasn't been
/// requested yet).
struct ReflectionRowView: View {

    let item: ReflectionDisplayItem
    let isFetchingFeedback: Bool
    let onRequestFeedback: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            header
            reflectionText
            feedbackSection
        }
        .padding(.cfSpacing16)
        .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius12))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: .cfSpacing8) {
            Text(item.createdAt, style: .relative)
                .font(.cfCaption)
                .foregroundStyle(Color.cfTertiaryLabel)

            if item.isLocalPending {
                pendingBadge
            }

            Spacer()
        }
    }

    private var pendingBadge: some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.cfCaption2)
            Text("Pending sync")
                .font(.cfCaption2)
        }
        .foregroundStyle(Color.secondary)
        .padding(.horizontal, .cfSpacing8)
        .padding(.vertical, .cfSpacing2)
        .background(.regularMaterial, in: Capsule())
        .accessibilityLabel("Not yet synced to the server")
    }

    // MARK: - Reflection text

    private var reflectionText: some View {
        Text(item.text)
            .font(.cfBody)
            .foregroundStyle(Color.cfLabel)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Feedback section

    @ViewBuilder
    private var feedbackSection: some View {
        if let feedback = item.feedbackText {
            feedbackBubble(feedback)
        } else if item.isFeedbackLoading {
            feedbackPendingIndicator
        } else if isFetchingFeedback {
            feedbackLoadingIndicator
        } else {
            getFeedbackButton
        }
    }

    private func feedbackBubble(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            HStack(spacing: .cfSpacing4) {
                Image(systemName: "sparkles")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfAccent)
                Text("AI Reflection")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfAccent)
            }
            Text(text)
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.cfSpacing12)
        .background(Color.cfAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: .cfRadius8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI feedback: \(text)")
    }

    private var feedbackPendingIndicator: some View {
        HStack(spacing: .cfSpacing6) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.cfCaption)
            Text("Feedback queued — will arrive once you're back online")
                .font(.cfCaption)
        }
        .foregroundStyle(Color.cfTertiaryLabel)
        .accessibilityLabel("AI feedback is queued and will arrive when you reconnect")
    }

    private var feedbackLoadingIndicator: some View {
        HStack(spacing: .cfSpacing8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Getting feedback…")
                .font(.cfCaption)
                .foregroundStyle(Color.cfTertiaryLabel)
        }
        .accessibilityLabel("Loading AI feedback")
    }

    private var getFeedbackButton: some View {
        Button(action: onRequestFeedback) {
            Label("Get AI feedback", systemImage: "sparkles")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfAccent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Request AI feedback on this reflection")
        .accessibilityHint("Gets personalized encouragement and insights from AI")
        .disabled(item.isLocalPending)
        .opacity(item.isLocalPending ? 0.4 : 1)
    }
}

// MARK: - Local spacing

private extension CGFloat {
    static let cfSpacing6: CGFloat = 6
}

// MARK: - Previews

#if DEBUG
#Preview("Synced – no feedback", traits: .sizeThatFitsLayout) {
    let item = ReflectionDisplayItem.synced(ChapterReflection(
        reflectionId: "r1",
        bookId: "atomic-habits",
        chapterN: 3,
        text: "I found the habit loop concept really insightful — especially how cues shape automatic behavior without us realising it.",
        createdAt: Date(timeIntervalSinceNow: -3600)
    ))
    ReflectionRowView(item: item, isFetchingFeedback: false, onRequestFeedback: {})
        .padding()
}

#Preview("Synced – with feedback", traits: .sizeThatFitsLayout) {
    let item = ReflectionDisplayItem.synced(ChapterReflection(
        reflectionId: "r2",
        bookId: "atomic-habits",
        chapterN: 3,
        text: "I want to apply this to my morning routine.",
        createdAt: Date(timeIntervalSinceNow: -7200),
        feedbackText: "Excellent observation! Linking a new habit to an existing cue is one of the most reliable strategies from this chapter. Your morning routine is a perfect anchor."
    ))
    ReflectionRowView(item: item, isFetchingFeedback: false, onRequestFeedback: {})
        .padding()
}

#Preview("Pending (offline)", traits: .sizeThatFitsLayout) {
    let item = ReflectionDisplayItem.pending(PendingReflectionItem(
        localId: "local-1",
        bookId: "atomic-habits",
        chapterN: 3,
        text: "Written while offline — this will sync when I reconnect.",
        createdAt: Date(timeIntervalSinceNow: -60)
    ))
    ReflectionRowView(item: item, isFetchingFeedback: false, onRequestFeedback: {})
        .padding()
}

#Preview("Fetching feedback", traits: .sizeThatFitsLayout) {
    let item = ReflectionDisplayItem.synced(ChapterReflection(
        reflectionId: "r3",
        bookId: "atomic-habits",
        chapterN: 3,
        text: "The two-minute rule changed how I think about starting.",
        createdAt: Date(timeIntervalSinceNow: -1800)
    ))
    ReflectionRowView(item: item, isFetchingFeedback: true, onRequestFeedback: {})
        .padding()
}

#Preview("Dark mode", traits: .sizeThatFitsLayout) {
    let item = ReflectionDisplayItem.synced(ChapterReflection(
        reflectionId: "r4",
        bookId: "atomic-habits",
        chapterN: 3,
        text: "Identity-based habits feel like a long game — but the right one.",
        createdAt: Date(timeIntervalSinceNow: -86400),
        feedbackText: "You've grasped a key distinction. Identity-based habits build from the inside out, creating lasting change rather than short-lived motivation spikes."
    ))
    ReflectionRowView(item: item, isFetchingFeedback: false, onRequestFeedback: {})
        .padding()
        .preferredColorScheme(.dark)
}
#endif
