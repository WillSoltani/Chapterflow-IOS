import SwiftUI
import Charts
import Models
import DesignSystem

/// Donut chart showing the distribution of the user's books by status:
/// Completed / In Progress / Not Started.
///
/// Uses `DashboardSnapshot` progress data. Category names become available
/// once the catalog is joined (P5.1 shows status distribution as a meaningful proxy).
struct CategoryCoverageChart: View {

    let snapshot: DashboardSnapshot

    private struct Slice: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
        let color: Color
    }

    private var slices: [Slice] {
        let completed = snapshot.booksCompleted
        let inProgress = snapshot.booksInProgress
        let notStarted = snapshot.booksNotStarted
        var result: [Slice] = []
        if completed > 0 {
            result.append(Slice(label: "Completed", count: completed, color: Color.cfAccent))
        }
        if inProgress > 0 {
            result.append(Slice(label: "In Progress", count: inProgress, color: Color.orange))
        }
        if notStarted > 0 {
            result.append(Slice(label: "Not Started", count: notStarted, color: Color.cfFill))
        }
        return result
    }

    private var total: Int { slices.reduce(0) { $0 + $1.count } }

    var body: some View {
        HStack(alignment: .center, spacing: .cfSpacing24) {
            if total == 0 {
                emptyState
            } else {
                donut
                legend
            }
        }
        .accessibilityLabel(accessibilityDescription)
    }

    private var donut: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Books", slice.count),
                innerRadius: .ratio(0.55),
                angularInset: 2
            )
            .foregroundStyle(slice.color)
            .cornerRadius(4)
        }
        .frame(width: 120, height: 120)
        .overlay {
            VStack(spacing: 2) {
                Text("\(total)")
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfLabel)
                Text("books")
                    .font(.cfCaption2)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            ForEach(slices) { slice in
                HStack(spacing: .cfSpacing8) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 10, height: 10)
                    Text(slice.label)
                        .font(.cfFootnote)
                        .foregroundStyle(Color.cfSecondaryLabel)
                    Spacer()
                    Text("\(slice.count)")
                        .font(.cfFootnote)
                        .foregroundStyle(Color.cfLabel)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: .cfSpacing8) {
                Image(systemName: "book")
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfTertiaryLabel)
                Text("No books started yet")
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
            Spacer()
        }
        .frame(height: 120)
    }

    private var accessibilityDescription: String {
        slices.map { "\($0.count) \($0.label)" }.joined(separator: ", ")
    }
}

// MARK: - Preview

#Preview("CategoryCoverageChart") {
    let snapshot = DashboardSnapshot(
        dashboard: .preview,
        streak: .preview,
        progress: [
            ProgressOverviewItem(bookId: "a", currentChapterNumber: 12, totalChapters: 12, completedChapterCount: 12, lastReadAt: nil),
            ProgressOverviewItem(bookId: "b", currentChapterNumber: 5, totalChapters: 10, completedChapterCount: 5, lastReadAt: nil),
            ProgressOverviewItem(bookId: "c", currentChapterNumber: 1, totalChapters: 8, completedChapterCount: 0, lastReadAt: nil),
            ProgressOverviewItem(bookId: "d", currentChapterNumber: 3, totalChapters: 14, completedChapterCount: 3, lastReadAt: nil),
        ]
    )
    CategoryCoverageChart(snapshot: snapshot)
        .padding(.cfSpacing16)
        .background(Color.cfGroupedBackground)
}
