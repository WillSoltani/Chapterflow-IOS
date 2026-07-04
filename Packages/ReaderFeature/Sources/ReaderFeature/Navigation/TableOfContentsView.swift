import SwiftUI
import Models
import DesignSystem

// MARK: - TableOfContentsView

/// Book table of contents: all chapters with lock / complete / current state.
///
/// Tapping an unlocked chapter calls `model.navigate(to:)` which fires the
/// host's navigation callback. Locked chapters are inert.
///
/// Designed to render both as a modal sheet (iPhone) and a persistent sidebar
/// column (iPad). Pass `isSheet: false` in the sidebar context to suppress the
/// `NavigationStack` wrapper and Done button.
public struct TableOfContentsView: View {
    @Bindable private var model: ChapterNavModel
    private let currentReadPercent: Double
    private let isSheet: Bool

    public init(
        model: ChapterNavModel,
        currentReadPercent: Double,
        isSheet: Bool = true
    ) {
        self.model = model
        self.currentReadPercent = currentReadPercent
        self.isSheet = isSheet
    }

    public var body: some View {
        if isSheet {
            NavigationStack {
                content
                    .navigationTitle("Contents")
                    .inlineTitleDisplayMode()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                model.isToCPresented = false
                            }
                        }
                    }
            }
        } else {
            VStack(spacing: 0) {
                sidebarHeader
                Divider()
                content
            }
        }
    }

    // MARK: - Sidebar header

    private var sidebarHeader: some View {
        Text("Contents")
            .font(.cfTitle3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, .cfSpacing16)
            .padding(.vertical, .cfSpacing12)
    }

    // MARK: - Chapter list

    private var content: some View {
        List(model.items) { item in
            ChapterNavRow(
                item: item,
                chapterReadPercent: item.isCurrent ? currentReadPercent : nil
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard !item.isLocked else { return }
                model.navigate(to: item.chapter.number)
            }
            .listRowBackground(rowBackground(for: item))
            .listRowInsets(EdgeInsets(
                top: .cfSpacing4,
                leading: .cfSpacing12,
                bottom: .cfSpacing4,
                trailing: .cfSpacing12
            ))
        }
        .listStyle(.plain)
        .accessibilityLabel("Table of Contents")
    }

    @ViewBuilder
    private func rowBackground(for item: ChapterNavItem) -> some View {
        if item.isCurrent {
            RoundedRectangle(cornerRadius: .cfRadius8)
                .fill(Color.cfAccent.opacity(0.08))
        } else {
            Color.clear
        }
    }
}

// MARK: - Platform helpers

private extension View {
    @ViewBuilder
    func inlineTitleDisplayMode() -> some View {
#if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
}

// MARK: - ChapterNavRow

/// A single row in the table of contents.
struct ChapterNavRow: View {
    let item: ChapterNavItem
    /// Non-nil for the current chapter — shows a mini in-progress bar.
    let chapterReadPercent: Double?

    var body: some View {
        HStack(alignment: .top, spacing: .cfSpacing12) {
            statusIcon
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: .cfSpacing4) {
                HStack {
                    Text("Chapter \(item.chapter.number)")
                        .font(.cfCaption)
                        .foregroundStyle(labelColor)
                    Spacer()
                    Text("\(item.chapter.readingTimeMinutes) min")
                        .font(.cfCaption2)
                        .foregroundStyle(Color.cfTertiaryLabel)
                }

                Text(item.chapter.title)
                    .font(.cfSubheadline)
                    .foregroundStyle(item.isLocked ? Color.cfSecondaryLabel : Color.cfLabel)
                    .lineLimit(2)

                if let reason = item.lockReason {
                    Text(reason)
                        .font(.cfCaption2)
                        .foregroundStyle(Color.cfTertiaryLabel)
                }

                if let percent = chapterReadPercent, percent > 0 {
                    progressBar(percent: percent)
                }
            }
        }
        .padding(.vertical, .cfSpacing4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(item.isLocked ? .isStaticText : .isButton)
    }

    private var labelColor: Color {
        if item.isLocked { return Color.cfTertiaryLabel }
        if item.isCurrent { return Color.cfAccent }
        return Color.cfSecondaryLabel
    }

    @ViewBuilder
    private var statusIcon: some View {
        if item.isLocked {
            Image(systemName: "lock.fill")
                .font(.cfCaption)
                .foregroundStyle(Color.cfTertiaryLabel)
        } else if item.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.cfCallout)
                .foregroundStyle(Color.cfAccent)
        } else if item.isCurrent {
            Image(systemName: "circle.fill")
                .font(Font.system(size: 8))
                .foregroundStyle(Color.cfAccent)
        } else {
            Image(systemName: "circle")
                .font(Font.system(size: 8))
                .foregroundStyle(Color.cfTertiaryLabel)
        }
    }

    private func progressBar(percent: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.cfSeparator.opacity(0.4))
                    .frame(height: 2)
                Capsule()
                    .fill(Color.cfAccent)
                    .frame(width: max(0, geo.size.width * percent), height: 2)
            }
        }
        .frame(height: 2)
        .padding(.top, .cfSpacing4)
    }

    private var accessibilityLabel: String {
        var parts = ["Chapter \(item.chapter.number): \(item.chapter.title)"]
        parts.append("\(item.chapter.readingTimeMinutes) minutes")
        if item.isCurrent { parts.append("current chapter") }
        if item.isCompleted { parts.append("completed") }
        if item.isLocked {
            parts.append("locked")
            if let reason = item.lockReason { parts.append(reason) }
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private func makePreviewNavModel(
    currentChapter: Int = 2,
    unlockedThrough: Int = 3
) -> ChapterNavModel {
    let chapters = (1...6).map { n in
        BookManifestChapter(
            chapterId: "ch-\(n)",
            number: n,
            title: [
                "The Surprising Power of Atomic Habits",
                "How Your Habits Shape Your Identity",
                "How to Build Better Habits in 4 Simple Steps",
                "The Man Who Didn't Look Right",
                "The Best Way to Start a New Habit",
                "Motivation Is Overrated"
            ][n - 1],
            readingTimeMinutes: [12, 10, 14, 8, 11, 13][n - 1],
            chapterKey: "ch-key-\(n)",
            quizKey: "quiz-key-\(n)"
        )
    }
    let cover = Cover(emoji: "📚", color: "#1a1a2e")
    let manifest = BookManifest(
        bookId: "atomic-habits",
        title: "Atomic Habits",
        author: "James Clear",
        categories: ["Self-Help"],
        tags: [],
        cover: cover,
        variantFamily: .emh,
        status: "published",
        latestVersion: 1,
        currentPublishedVersion: 1,
        updatedAt: "2024-01-01T00:00:00Z",
        chapters: chapters,
        totalReadingTimeMinutes: 68,
        chapterCount: 6
    )
    let progress = BookProgress(
        currentChapterNumber: currentChapter,
        unlockedThroughChapterNumber: unlockedThrough,
        completedChapters: [1],
        bestScoreByChapter: ["1": 85],
        preferredVariant: .medium,
        progressRev: 1
    )
    return ChapterNavModel(
        manifest: manifest,
        progress: progress,
        currentChapterNumber: currentChapter
    )
}

#Preview("ToC Sheet — light") {
    @Previewable @State var presented = true
    Color.cfBackground
        .sheet(isPresented: $presented) {
            TableOfContentsView(
                model: makePreviewNavModel(),
                currentReadPercent: 0.45,
                isSheet: true
            )
        }
}

#Preview("ToC Sheet — dark") {
    @Previewable @State var presented = true
    Color.cfBackground
        .sheet(isPresented: $presented) {
            TableOfContentsView(
                model: makePreviewNavModel(),
                currentReadPercent: 0.45,
                isSheet: true
            )
        }
        .preferredColorScheme(.dark)
}

#Preview("ToC Sheet — XXL text") {
    @Previewable @State var presented = true
    Color.cfBackground
        .sheet(isPresented: $presented) {
            TableOfContentsView(
                model: makePreviewNavModel(),
                currentReadPercent: 0.45,
                isSheet: true
            )
        }
        .dynamicTypeSize(.accessibility3)
}

#Preview("ToC Sidebar (iPad-style)") {
    TableOfContentsView(
        model: makePreviewNavModel(currentChapter: 3, unlockedThrough: 4),
        currentReadPercent: 0.7,
        isSheet: false
    )
    .frame(width: 300)
    .background(Color.cfBackground)
}
#endif
