import SwiftUI
import DesignSystem
import Models
import CoreKit

// MARK: - StreakView

/// The streak screen — shows the 30-day activity heatmap, shield count,
/// milestone progress, and a "streak at risk" warning late in the day.
public struct StreakView: View {

    private let model: StreakModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: StreakModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.loadState {
            case .loading:
                StreakSkeletonView()
            case .loaded(let streak):
                loadedView(streak)
            case .error(let error):
                errorView(error)
            }
        }
        .navigationTitle("Streak")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .background(Color.cfGroupedBackground.ignoresSafeArea())
        .task { model.load() }
        .refreshable { await model.refresh() }
    }

    // MARK: - Loaded

    private func loadedView(_ streak: StreakState) -> some View {
        ScrollView {
            VStack(spacing: .cfSpacing20) {
                heroSection(streak)

                if model.isAtRisk {
                    atRiskBanner(streak)
                }

                heatmapSection

                statsRow(streak)

                shieldsSection(streak)

                milestonesSection(streak)
            }
            .padding(.cfSpacing16)
        }
    }

    // MARK: - Hero

    private func heroSection(_ streak: StreakState) -> some View {
        CFCard {
            HStack(alignment: .center, spacing: .cfSpacing16) {
                flameIcon(currentStreak: streak.currentStreak)

                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text("\(streak.currentStreak)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(streakColor(streak.currentStreak))
                        .contentTransition(.numericText())
                    Text(streak.currentStreak == 1 ? "day streak" : "day streak")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: .cfSpacing4) {
                    Text("Best")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfTertiaryLabel)
                    Text("\(streak.longestStreak)")
                        .font(.cfTitle3)
                        .foregroundStyle(Color.cfLabel)
                    Text(streak.longestStreak == 1 ? "day" : "days")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfTertiaryLabel)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current streak: \(streak.currentStreak) days. Best: \(streak.longestStreak) days.")
    }

    private func flameIcon(currentStreak: Int) -> some View {
        Image(systemName: currentStreak > 0 ? "flame.fill" : "flame")
            .font(.system(size: 44))
            .foregroundStyle(streakColor(currentStreak))
            .symbolEffect(.bounce, value: reduceMotion ? 0 : currentStreak)
    }

    // MARK: - At-risk banner

    private func atRiskBanner(_ streak: StreakState) -> some View {
        HStack(spacing: .cfSpacing12) {
            Image(systemName: "shield.lefthalf.filled.slash")
                .font(.cfSubheadline)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: .cfSpacing2) {
                Text("Streak at Risk")
                    .font(.cfSubheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("Read something today to keep your \(streak.currentStreak)-day streak.")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
            Spacer()
        }
        .padding(.cfSpacing12)
        .background {
            RoundedRectangle(cornerRadius: .cfRadius12)
                .fill(Color.orange.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: .cfRadius12)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                }
        }
        .accessibilityLabel("Streak at risk. Read something today to keep your \(streak.currentStreak)-day streak.")
    }

    // MARK: - Heatmap

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Label("Last 30 Days", systemImage: "calendar")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            CFCard {
                HeatmapGridView(days: model.heatmapDays)
            }
        }
    }

    // MARK: - Stats row

    private func statsRow(_ streak: StreakState) -> some View {
        HStack(spacing: .cfSpacing12) {
            statPill(
                value: "\(streak.currentStreak)",
                label: "Current",
                icon: "flame.fill",
                color: streakColor(streak.currentStreak)
            )
            statPill(
                value: "\(streak.longestStreak)",
                label: "Longest",
                icon: "trophy.fill",
                color: .yellow
            )
        }
    }

    private func statPill(value: String, label: String, icon: String, color: Color) -> some View {
        CFCard {
            HStack(spacing: .cfSpacing8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.cfSubheadline)
                VStack(alignment: .leading, spacing: .cfSpacing2) {
                    Text(value)
                        .font(.cfTitle3.weight(.semibold))
                        .foregroundStyle(Color.cfLabel)
                    Text(label)
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
                Spacer()
            }
        }
        .accessibilityLabel("\(label): \(value) days")
    }

    // MARK: - Shields

    private func shieldsSection(_ streak: StreakState) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Label("Streak Shields", systemImage: "shield.fill")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            CFCard {
                VStack(alignment: .leading, spacing: .cfSpacing16) {
                    shieldDisplay(count: streak.streakShieldsHeld)

                    Divider()

                    VStack(alignment: .leading, spacing: .cfSpacing8) {
                        Text("What are Streak Shields?")
                            .font(.cfSubheadline.weight(.medium))
                            .foregroundStyle(Color.cfLabel)
                        Text("Shields protect your streak when life gets in the way. Missing a day consumes one shield automatically — your streak stays alive. Shields are earned by reaching reading milestones and maintaining long streaks.")
                            .font(.cfCaption)
                            .foregroundStyle(Color.cfSecondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func shieldDisplay(count: Int) -> some View {
        HStack(spacing: .cfSpacing8) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < count ? "shield.fill" : "shield")
                    .font(.system(size: 28))
                    .foregroundStyle(index < count ? Color.cfAccent : Color.cfTertiaryLabel)
                    .accessibilityHidden(true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: .cfSpacing2) {
                Text("\(count)")
                    .font(.cfTitle2.weight(.semibold))
                    .foregroundStyle(count > 0 ? Color.cfAccent : Color.cfTertiaryLabel)
                Text(count == 1 ? "shield held" : "shields held")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
        }
        .accessibilityLabel("\(count) \(count == 1 ? "streak shield" : "streak shields") held")
    }

    // MARK: - Milestones

    private func milestonesSection(_ streak: StreakState) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Label("Milestones", systemImage: "flag.checkered")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            CFCard {
                VStack(spacing: 0) {
                    ForEach(Array(streakMilestoneDays.enumerated()), id: \.element) { index, milestone in
                        if index > 0 {
                            Divider()
                                .padding(.leading, .cfSpacing32 + .cfSpacing12)
                        }
                        milestoneRow(
                            days: milestone,
                            currentStreak: streak.currentStreak,
                            isNext: milestone == model.nextMilestone
                        )
                    }
                }
            }
        }
    }

    private func milestoneRow(days: Int, currentStreak: Int, isNext: Bool) -> some View {
        let reached = currentStreak >= days
        return HStack(spacing: .cfSpacing12) {
            Image(systemName: reached ? "checkmark.circle.fill" : (isNext ? "circle.dotted" : "circle"))
                .font(.cfSubheadline)
                .foregroundStyle(reached ? Color.green : (isNext ? Color.cfAccent : Color.cfTertiaryLabel))
                .frame(width: .cfSpacing20)

            Text("\(days)-day streak")
                .font(.cfBody)
                .foregroundStyle(reached ? Color.cfLabel : Color.cfSecondaryLabel)

            Spacer()

            if reached {
                Text("Done")
                    .font(.cfCaption.weight(.medium))
                    .foregroundStyle(Color.green)
            } else if isNext {
                Text("\(days - currentStreak) to go")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfAccent)
            }
        }
        .padding(.vertical, .cfSpacing12)
        .accessibilityLabel(milestoneAccessibilityLabel(days: days, currentStreak: currentStreak, isNext: isNext))
        .accessibilityAddTraits(reached ? [.isStaticText] : [])
    }

    private func milestoneAccessibilityLabel(days: Int, currentStreak: Int, isNext: Bool) -> String {
        if currentStreak >= days {
            return "\(days)-day milestone: completed"
        } else if isNext {
            return "\(days)-day milestone: \(days - currentStreak) days to go"
        }
        return "\(days)-day milestone: not yet reached"
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
            Button("Try Again") { model.load() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(.cfSpacing24)
    }

    // MARK: - Helpers

    private func streakColor(_ streak: Int) -> Color {
        switch streak {
        case 0:         return Color.cfTertiaryLabel
        case 1..<7:     return .orange
        case 7..<30:    return .orange
        case 30..<100:  return Color(red: 0.9, green: 0.4, blue: 0)
        default:        return Color(red: 0.85, green: 0.25, blue: 0)
        }
    }
}

// MARK: - HeatmapGridView

/// A 5-column × 6-row grid of day cells, oldest in the top-left corner.
struct HeatmapGridView: View {

    let days: [HeatmapDay]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: .cfSpacing4), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            LazyVGrid(columns: columns, spacing: .cfSpacing4) {
                ForEach(days.indices, id: \.self) { index in
                    HeatmapCell(day: days[index])
                }
            }

            legendRow
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("30-day activity heatmap")
    }

    private var legendRow: some View {
        HStack(spacing: .cfSpacing4) {
            Text("Less")
                .font(.cfCaption2)
                .foregroundStyle(Color.cfTertiaryLabel)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                RoundedRectangle(cornerRadius: .cfRadius4)
                    .fill(heatColor(intensity: intensity))
                    .frame(width: 12, height: 12)
            }
            Text("More")
                .font(.cfCaption2)
                .foregroundStyle(Color.cfTertiaryLabel)
            Spacer()
        }
    }

    private func heatColor(intensity: Double) -> Color {
        if intensity <= 0 {
            return Color.cfSecondaryFill
        }
        return Color.cfAccent.opacity(0.2 + intensity * 0.8)
    }
}

// MARK: - HeatmapCell

private struct HeatmapCell: View {
    let day: HeatmapDay

    var body: some View {
        RoundedRectangle(cornerRadius: .cfRadius4)
            .fill(cellColor)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityLabel(day.accessibilityLabel)
    }

    private var cellColor: Color {
        if !day.hasActivity {
            return Color.cfSecondaryFill
        }
        return Color.cfAccent.opacity(0.2 + day.intensity * 0.8)
    }
}

// MARK: - StreakSkeletonView

private struct StreakSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: .cfSpacing20) {
                CFCard {
                    CFSkeleton()
                        .frame(height: 80)
                }
                CFCard {
                    CFSkeleton()
                        .frame(height: 140)
                }
                CFCard {
                    CFSkeleton()
                        .frame(height: 60)
                }
            }
            .padding(.cfSpacing16)
        }
    }
}

// MARK: - Previews

#Preview("Streak — light") {
    let presenter = CelebrationPresenter()
    let model = StreakModel(repository: .preview, celebrationPresenter: presenter)
    return NavigationStack {
        StreakView(model: model)
    }
}

#Preview("Streak — dark") {
    let presenter = CelebrationPresenter()
    let model = StreakModel(repository: .preview, celebrationPresenter: presenter)
    return NavigationStack {
        StreakView(model: model)
    }
    .preferredColorScheme(.dark)
}

#Preview("Streak — XXL text") {
    let presenter = CelebrationPresenter()
    let model = StreakModel(repository: .preview, celebrationPresenter: presenter)
    return NavigationStack {
        StreakView(model: model)
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Streak — at risk") {
    let presenter = CelebrationPresenter()
    let model = StreakModel(repository: .previewAtRisk, celebrationPresenter: presenter)
    return NavigationStack {
        StreakView(model: model)
    }
}

#Preview("Streak — no streak") {
    let presenter = CelebrationPresenter()
    let model = StreakModel(repository: .previewNoStreak, celebrationPresenter: presenter)
    return NavigationStack {
        StreakView(model: model)
    }
}
