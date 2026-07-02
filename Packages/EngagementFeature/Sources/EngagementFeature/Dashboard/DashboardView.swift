import SwiftUI
import DesignSystem
import Models
import CoreKit

/// The progress dashboard — a full-screen glanceable summary of the user's
/// reading activity, stats, and learning trends.
///
/// Entry point: embed this view wherever a progress summary is needed (Home tab,
/// Profile screen). Supply a `DashboardModel` via the initializer.
///
/// `DashboardModel` is `@Observable`, so SwiftUI automatically tracks all
/// property accesses and re-renders only when necessary.
public struct DashboardView: View {
    private let model: DashboardModel

    public init(model: DashboardModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.loadState {
            case .loading:
                DashboardSkeletonView()
            case .loaded(let snapshot):
                loadedView(snapshot)
            case .error(let error):
                errorView(error)
            }
        }
        .navigationTitle("Progress")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .background(Color.cfGroupedBackground.ignoresSafeArea())
        .task { model.load() }
    }

    // MARK: - Loaded state

    private func loadedView(_ snapshot: DashboardSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: .cfSpacing24, pinnedViews: []) {
                // 1. Glanceable stat cards
                statCards(snapshot.dashboard)

                // 2. Continue reading card
                if let book = snapshot.dashboard.continueBook {
                    continueReadingCard(book)
                }

                // 3. Daily reading activity
                ChartSection(title: "Daily Reading Activity", systemImage: "waveform.path.ecg") {
                    ReadingTimeTrendChart(days: snapshot.last14Days)
                }

                // 4. Weekly goal
                ChartSection(title: "Weekly Goal", systemImage: "target") {
                    WeeklyGoalChart(
                        weeklyReadMinutes: snapshot.dashboard.weeklyReadMinutes,
                        weeklyGoalMinutes: snapshot.dashboard.weeklyGoalMinutes
                    )
                }

                // 5. Chapters progress by book
                ChartSection(title: "Chapters Completed", systemImage: "checkmark.circle") {
                    ChaptersProgressChart(items: snapshot.progress)
                }

                // 6. Books overview (category coverage)
                ChartSection(title: "Books Overview", systemImage: "books.vertical") {
                    CategoryCoverageChart(snapshot: snapshot)
                }
            }
            .padding(.cfSpacing16)
        }
        .refreshable {
            await model.refresh()
        }
        .animation(.easeInOut(duration: 0.25), value: model.isRefreshing)
    }

    // MARK: - Stat cards

    private func statCards(_ dashboard: Dashboard) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: .cfSpacing12
        ) {
            StatCardView(
                title: "Streak",
                value: "\(dashboard.currentStreak)",
                subtitle: dashboard.currentStreak == 1 ? "day" : "days",
                icon: "flame.fill",
                iconColor: .orange
            )
            StatCardView(
                title: "Books Done",
                value: "\(dashboard.booksCompleted)",
                subtitle: "of \(dashboard.booksStarted) started",
                icon: "books.vertical.fill",
                iconColor: Color.cfAccent
            )
            StatCardView(
                title: "Tier",
                value: tierName(dashboard.tier),
                subtitle: tierProgressLabel(dashboard.tierProgress),
                icon: "star.fill",
                iconColor: tierColor(dashboard.tier)
            )
            StatCardView(
                title: "Flow Points",
                value: formattedPoints(dashboard.flowPoints),
                subtitle: "balance",
                icon: "bolt.fill",
                iconColor: .purple
            )
        }
    }

    // MARK: - Continue reading card

    private func continueReadingCard(_ book: DashboardBookEntry) -> some View {
        CFCard {
            HStack(spacing: .cfSpacing12) {
                coverView(book.cover)
                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text("Continue Reading")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                    Text(book.title)
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfLabel)
                        .lineLimit(2)
                    Text("Chapter \(book.lastChapterNumber)")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfTertiaryLabel)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
        }
        .accessibilityLabel("Continue reading \(book.title), chapter \(book.lastChapterNumber)")
        .accessibilityAddTraits(.isButton)
    }

    private func coverView(_ cover: Cover?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: .cfRadius8)
                .fill(coverColor(cover?.color))
            Text(cover?.emoji ?? "📖")
                .font(.system(size: 24))
        }
        .frame(width: 44, height: 44)
    }

    // MARK: - Error state

    private func errorView(_ error: AppError) -> some View {
        VStack(spacing: .cfSpacing16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.cfLargeTitle)
                .foregroundStyle(Color.cfTertiaryLabel)
            Text(error.errorDescription ?? "Something went wrong.")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                model.load()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(.cfSpacing24)
    }

    // MARK: - Formatters

    private func tierName(_ tier: String?) -> String {
        tier?.capitalized ?? "Reader"
    }

    private func tierProgressLabel(_ progress: Double?) -> String {
        guard let p = progress else { return "" }
        return "\(Int(p * 100))% to next"
    }

    private func tierColor(_ tier: String?) -> Color {
        switch tier?.lowercased() {
        case "analyst": return .blue
        case "synthesizer": return .green
        case "polymath": return .orange
        case "luminary": return .yellow
        default: return .secondary
        }
    }

    private func formattedPoints(_ points: Int) -> String {
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: points), number: .decimal)
        return formatted
    }

    private func coverColor(_ hex: String?) -> Color {
        guard let hex = hex, hex.hasPrefix("#"), hex.count == 7 else {
            return Color.cfSecondaryBackground
        }
        let r = Double(Int(hex.dropFirst(1).prefix(2), radix: 16) ?? 128) / 255
        let g = Double(Int(hex.dropFirst(3).prefix(2), radix: 16) ?? 128) / 255
        let b = Double(Int(hex.dropFirst(5).prefix(2), radix: 16) ?? 128) / 255
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - ChartSection helper

private struct ChartSection<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Label(title, systemImage: systemImage)
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
            CFCard {
                content
            }
        }
    }
}

// MARK: - Previews

#Preview("Dashboard — light") {
    let model = DashboardModel(repository: .preview)
    NavigationStack {
        DashboardView(model: model)
    }
}

#Preview("Dashboard — dark") {
    let model = DashboardModel(repository: .preview)
    NavigationStack {
        DashboardView(model: model)
    }
    .preferredColorScheme(.dark)
}

#Preview("Dashboard — XXL text") {
    let model = DashboardModel(repository: .preview)
    NavigationStack {
        DashboardView(model: model)
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Dashboard — skeleton") {
    DashboardSkeletonView()
        .background(Color.cfGroupedBackground)
}
