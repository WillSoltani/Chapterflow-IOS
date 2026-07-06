import SwiftUI
import Persistence
import DesignSystem

// MARK: - SharedStateDiagnosticsView

/// A debug view that displays the current App Group shared-state snapshot.
///
/// Used in `#Preview` and optionally surfaced in a Settings debug menu to
/// verify that widgets will see correct data.
struct SharedStateDiagnosticsView: View {
    let snapshot: SharedAppStateSnapshot

    var body: some View {
        List {
            Section("Streak") {
                row("Days", value: "\(snapshot.streakDays)")
                row("At Risk", value: snapshot.streakAtRisk ? "Yes" : "No")
            }
            Section("Continue Reading") {
                if let bookId = snapshot.continueBookId {
                    row("Book ID", value: bookId)
                    row("Title", value: snapshot.continueBookTitle ?? "—")
                    row("Cover", value: [snapshot.continueBookCoverEmoji, snapshot.continueBookCoverColor]
                        .compactMap { $0 }.joined(separator: " "))
                    row("Chapter", value: snapshot.continueChapterNumber.map { "\($0)" } ?? "—")
                    row("Progress", value: snapshot.continueProgress.map {
                        String(format: "%.0f%%", $0 * 100)
                    } ?? "—")
                } else {
                    Text("No continue-reading entry")
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
            }
            Section("Reviews") {
                row("Due Cards", value: "\(snapshot.dueReviewCount)")
            }
            Section("Daily Goal") {
                row("Goal", value: "\(snapshot.dailyGoalMinutes) min")
                row("Progress", value: "\(snapshot.goalProgressMinutes) min")
                row("Fraction", value: String(format: "%.0f%%", snapshot.goalFraction * 100))
                row("Goal Met", value: snapshot.isDailyGoalMet ? "Yes" : "No")
            }
            Section("Meta") {
                row("Last Updated", value: snapshot.lastUpdated == .distantPast
                    ? "Never"
                    : snapshot.lastUpdated.formatted(.relative(presentation: .named)))
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Shared State")
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.cfLabel)
            Spacer()
            Text(value)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Previews

private let sampleFull = SharedAppStateSnapshot(
    streakDays: 14,
    streakAtRisk: false,
    continueBookId: "book-abc",
    continueBookTitle: "Thinking, Fast and Slow",
    continueBookCoverEmoji: "🧠",
    continueBookCoverColor: "#3A86FF",
    continueChapterNumber: 7,
    continueProgress: 0.42,
    dueReviewCount: 5,
    dailyGoalMinutes: 20,
    goalProgressMinutes: 12,
    lastUpdated: Date()
)

private let sampleAtRisk = SharedAppStateSnapshot(
    streakDays: 3,
    streakAtRisk: true,
    continueBookId: "book-xyz",
    continueBookTitle: "Atomic Habits",
    continueBookCoverEmoji: "⚛️",
    continueBookCoverColor: "#FF6B6B",
    continueChapterNumber: 2,
    continueProgress: 0.15,
    dueReviewCount: 0,
    dailyGoalMinutes: 10,
    goalProgressMinutes: 0,
    lastUpdated: Date()
)

private let sampleEmpty = SharedAppStateSnapshot()

#Preview("Healthy State — Light", traits: .sizeThatFitsLayout) {
    NavigationStack {
        SharedStateDiagnosticsView(snapshot: sampleFull)
    }
}

#Preview("At-Risk Streak — Dark", traits: .sizeThatFitsLayout) {
    NavigationStack {
        SharedStateDiagnosticsView(snapshot: sampleAtRisk)
    }
    .preferredColorScheme(.dark)
}

#Preview("Empty (No Data) — XXL Type", traits: .sizeThatFitsLayout) {
    NavigationStack {
        SharedStateDiagnosticsView(snapshot: sampleEmpty)
    }
    .dynamicTypeSize(.accessibility1)
}
