import SwiftUI
import Models
import DesignSystem

/// A single row in the BookDetail chapter list.
///
/// Shows the chapter number, title, reading time, completion/lock state,
/// quiz score, and the application badge (committed/applied).
public struct ChapterRowView: View {

    let chapter: BookManifestChapter
    let isUnlocked: Bool
    let isCompleted: Bool
    let score: Int?
    let applicationState: ChapterApplicationState
    let lockReason: ChapterLockReason?
    let onTap: () -> Void

    public init(
        chapter: BookManifestChapter,
        isUnlocked: Bool,
        isCompleted: Bool,
        score: Int?,
        applicationState: ChapterApplicationState,
        lockReason: ChapterLockReason?,
        onTap: @escaping () -> Void
    ) {
        self.chapter = chapter
        self.isUnlocked = isUnlocked
        self.isCompleted = isCompleted
        self.score = score
        self.applicationState = applicationState
        self.lockReason = lockReason
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: isUnlocked ? onTap : {}) {
            HStack(alignment: .top, spacing: .cfSpacing12) {
                statusBadge
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    HStack(spacing: .cfSpacing8) {
                        Text(chapter.title)
                            .font(.cfSubheadline)
                            .foregroundStyle(isUnlocked ? Color.cfLabel : Color.cfTertiaryLabel)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        applicationBadge
                    }

                    HStack(spacing: .cfSpacing8) {
                        Label("\(chapter.readingTimeMinutes) min", systemImage: "clock")
                            .font(.cfCaption2)
                            .foregroundStyle(Color.cfTertiaryLabel)
                            .labelStyle(.titleAndIcon)

                        if let score {
                            scorePill(score)
                        }
                    }

                    if let reason = lockReason, !isUnlocked {
                        lockHint(for: reason)
                            .padding(.top, .cfSpacing2)
                    }
                }
            }
            .padding(.vertical, .cfSpacing12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isUnlocked ? .isButton : .isStaticText)
    }

    // MARK: - Status badge

    private var statusBadge: some View {
        ZStack {
            Circle()
                .strokeBorder(badgeStrokeColor, lineWidth: 1.5)
                .background(Circle().fill(badgeFill))
                .frame(width: 28, height: 28)

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.cfAccent)
            } else if isUnlocked {
                Text("\(chapter.number)")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfLabel)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
        }
        .frame(width: 28, height: 28)
    }

    private var badgeStrokeColor: Color {
        if isCompleted { return Color.cfAccent }
        if isUnlocked { return Color.cfSeparator }
        return Color.cfSecondaryFill
    }

    private var badgeFill: Color {
        if isCompleted { return Color.cfAccent.opacity(0.12) }
        return Color.clear
    }

    // MARK: - Application badge

    @ViewBuilder
    private var applicationBadge: some View {
        switch applicationState {
        case .committed:
            badgePill("Committed", color: Color.cfAccent)
        case .applied:
            badgePill("Applied", color: .green)
        case .none, .unknown:
            EmptyView()
        }
    }

    private func badgePill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.cfCaption2)
            .padding(.horizontal, .cfSpacing8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Score pill

    private func scorePill(_ score: Int) -> some View {
        Text("\(score)%")
            .font(.cfCaption2)
            .padding(.horizontal, .cfSpacing8)
            .padding(.vertical, 3)
            .background(Capsule().fill(scoreColor(score).opacity(0.15)))
            .foregroundStyle(scoreColor(score))
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return Color.cfAccent }
        return .orange
    }

    // MARK: - Lock hint

    private func lockHint(for reason: ChapterLockReason) -> some View {
        HStack(spacing: .cfSpacing4) {
            switch reason {
            case .finishPriorQuiz:
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.cfCaption2)
                Text("Finish Chapter \(chapter.number - 1) quiz to unlock")
                    .font(.cfCaption2)
            case .requiresPro:
                Image(systemName: "star.fill")
                    .font(.cfCaption2)
                Text("Upgrade to Pro to continue")
                    .font(.cfCaption2)
            }
        }
        .foregroundStyle(Color.cfTertiaryLabel)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts: [String] = ["Chapter \(chapter.number): \(chapter.title)"]
        if isCompleted { parts.append("Completed") }
        if let score { parts.append("Score: \(score)%") }
        if !isUnlocked { parts.append("Locked") }
        switch applicationState {
        case .committed: parts.append("Committed")
        case .applied:   parts.append("Applied")
        default: break
        }
        return parts.joined(separator: ". ")
    }

    private var accessibilityHint: String {
        guard !isUnlocked else { return "Tap to open" }
        switch lockReason {
        case .finishPriorQuiz: return "Complete Chapter \(chapter.number - 1) quiz to unlock"
        case .requiresPro:     return "Upgrade to Pro to unlock"
        case .none:            return "Locked"
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Chapter states", traits: .sizeThatFitsLayout) {
    VStack(spacing: 0) {
        Divider()
        ChapterRowView(
            chapter: BookManifestChapter(
                chapterId: "ch-1", number: 1, title: "The Surprising Power of Atomic Habits",
                readingTimeMinutes: 12, chapterKey: nil, quizKey: nil
            ),
            isUnlocked: true, isCompleted: true, score: 100,
            applicationState: .applied, lockReason: nil,
            onTap: {}
        )
        .padding(.horizontal, .cfSpacing16)
        Divider()
        ChapterRowView(
            chapter: BookManifestChapter(
                chapterId: "ch-2", number: 2, title: "How Your Habits Shape Your Identity",
                readingTimeMinutes: 14, chapterKey: nil, quizKey: nil
            ),
            isUnlocked: true, isCompleted: false, score: nil,
            applicationState: .committed, lockReason: nil,
            onTap: {}
        )
        .padding(.horizontal, .cfSpacing16)
        Divider()
        ChapterRowView(
            chapter: BookManifestChapter(
                chapterId: "ch-3", number: 3, title: "How to Build Better Habits in 4 Simple Steps",
                readingTimeMinutes: 18, chapterKey: nil, quizKey: nil
            ),
            isUnlocked: false, isCompleted: false, score: nil,
            applicationState: .none, lockReason: .finishPriorQuiz,
            onTap: {}
        )
        .padding(.horizontal, .cfSpacing16)
        Divider()
        ChapterRowView(
            chapter: BookManifestChapter(
                chapterId: "ch-4", number: 4, title: "The Man Who Didn't Look Right",
                readingTimeMinutes: 10, chapterKey: nil, quizKey: nil
            ),
            isUnlocked: false, isCompleted: false, score: nil,
            applicationState: .none, lockReason: .requiresPro,
            onTap: {}
        )
        .padding(.horizontal, .cfSpacing16)
        Divider()
    }
}

#Preview("Dark mode", traits: .sizeThatFitsLayout) {
    VStack(spacing: 0) {
        Divider()
        ChapterRowView(
            chapter: BookManifestChapter(
                chapterId: "ch-1", number: 1, title: "The Surprising Power of Atomic Habits",
                readingTimeMinutes: 12, chapterKey: nil, quizKey: nil
            ),
            isUnlocked: true, isCompleted: true, score: 85,
            applicationState: .applied, lockReason: nil,
            onTap: {}
        )
        .padding(.horizontal, .cfSpacing16)
        Divider()
    }
    .preferredColorScheme(.dark)
}
#endif
