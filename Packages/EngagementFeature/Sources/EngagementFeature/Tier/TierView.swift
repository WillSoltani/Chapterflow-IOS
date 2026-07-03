import SwiftUI
import DesignSystem
import Models
import CoreKit

// MARK: - TierView

/// The tier screen — shows the user's current tier, progress to the next tier,
/// a per-metric breakdown (loops, quiz score, categories), and routes tier-up
/// moments through the shared ``CelebrationPresenter``.
///
/// Open the tier explainer sheet via the info button in the navigation bar.
public struct TierView: View {

    @Bindable private var model: TierModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: TierModel) {
        _model = Bindable(model)
    }

    public var body: some View {
        Group {
            switch model.loadState {
            case .loading:
                TierSkeletonView()
            case .loaded(let state):
                loadedView(state)
            case .error(let error):
                errorView(error)
            }
        }
        .navigationTitle("Tier")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .background(Color.cfGroupedBackground.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Button {
                    model.showExplainer = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Tier levels explainer")
            }
        }
        .sheet(isPresented: $model.showExplainer) {
            TierExplainerView(currentTier: model.currentTier)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { model.load() }
        .refreshable { await model.refresh() }
    }

    // MARK: - Loaded

    private func loadedView(_ state: TierState) -> some View {
        ScrollView {
            VStack(spacing: .cfSpacing20) {
                heroCard(state)

                if let metrics = state.metrics, state.nextTier != nil {
                    progressSection(state, metrics: metrics)
                } else if state.currentTier == .luminary {
                    luminaryBadge
                }

                tierPathSection(state)
            }
            .padding(.cfSpacing16)
        }
        .animation(.easeInOut(duration: 0.25), value: model.isRefreshing)
    }

    // MARK: - Hero card

    private func heroCard(_ state: TierState) -> some View {
        CFCard {
            VStack(spacing: .cfSpacing16) {
                HStack(alignment: .center, spacing: .cfSpacing16) {
                    tierBadge(state.currentTier, size: 64)

                    VStack(alignment: .leading, spacing: .cfSpacing4) {
                        Text(state.currentTier.displayName)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(tierColor(state.currentTier))

                        if let nextTier = state.nextTier {
                            Text("Working toward \(nextTier.displayName)")
                                .font(.cfSubheadline)
                                .foregroundStyle(Color.cfSecondaryLabel)
                        } else {
                            Text("Top tier achieved")
                                .font(.cfSubheadline)
                                .foregroundStyle(Color.cfSecondaryLabel)
                        }
                    }

                    Spacer()
                }

                if let nextTier = state.nextTier {
                    overallProgressBar(state.overallProgress, nextTier: nextTier)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heroAccessibilityLabel(state))
    }

    private func tierBadge(_ tier: TierKey, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(tierColor(tier).opacity(0.15))
            Image(systemName: tierSystemImage(tier))
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(tierColor(tier))
                .symbolEffect(.bounce, options: .nonRepeating, value: tier.rawValue)
        }
        .frame(width: size, height: size)
    }

    private func overallProgressBar(_ progress: Double, nextTier: TierKey) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            HStack {
                Text("Progress to \(nextTier.displayName)")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.cfCaption.weight(.semibold))
                    .foregroundStyle(Color.cfLabel)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: .cfRadius4)
                        .fill(Color.cfSecondaryFill)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: .cfRadius4)
                        .fill(tierColor(nextTier))
                        .frame(width: geo.size.width * progress, height: 8)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8),
                            value: progress
                        )
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Overall progress to \(nextTier.displayName): \(Int(progress * 100)) percent")
        .accessibilityValue("\(Int(progress * 100)) of 100")
    }

    // MARK: - Per-metric progress

    private func progressSection(_ state: TierState, metrics: TierProgressDetail) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Label("Progress Metrics", systemImage: "chart.bar")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            CFCard {
                VStack(spacing: .cfSpacing16) {
                    let loopsLabel = "\(metrics.loopsCompleted)" + (metrics.loopsTarget.map { "/\($0)" } ?? "")
                    metricRow(icon: "checkmark.seal.fill", iconColor: Color.cfAccent,
                              title: "Loops Completed", label: loopsLabel, progress: model.loopsProgress)

                    Divider()

                    let quizLabel = "\(Int(metrics.averageQuizScore))%" +
                        (metrics.quizScoreTarget.map { " / \(Int($0))% target" } ?? "")
                    metricRow(icon: "chart.bar.fill", iconColor: .green,
                              title: "Avg. Quiz Score", label: quizLabel, progress: model.quizScoreProgress)

                    Divider()

                    let catLabel = "\(metrics.categoriesExplored)" +
                        (metrics.categoriesTarget.map { " / \($0) explored" } ?? "")
                    metricRow(icon: "books.vertical.fill", iconColor: .orange,
                              title: "Categories", label: catLabel, progress: model.categoriesProgress)
                }
            }
        }
    }

    private func metricRow(
        icon: String,
        iconColor: Color,
        title: String,
        label: String,
        progress: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            HStack(spacing: .cfSpacing8) {
                Image(systemName: icon)
                    .font(.cfSubheadline)
                    .foregroundStyle(iconColor)
                    .frame(width: .cfIconSmall)

                Text(title)
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfLabel)

                Spacer()

                Text(label)
                    .font(.cfSubheadline.weight(.semibold))
                    .foregroundStyle(Color.cfLabel)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: .cfRadius4)
                        .fill(Color.cfSecondaryFill)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: .cfRadius4)
                        .fill(iconColor)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8),
                            value: progress
                        )
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(label). \(Int(progress * 100)) percent complete.")
    }

    // MARK: - Luminary badge (top tier)

    private var luminaryBadge: some View {
        CFCard {
            HStack(spacing: .cfSpacing16) {
                Image(systemName: "star.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(tierColor(.luminary))

                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text("Pinnacle Achieved")
                        .font(.cfSubheadline.weight(.semibold))
                        .foregroundStyle(Color.cfLabel)
                    Text("You've reached the highest level of mastery. Keep learning to maintain your Luminary status.")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tier path (mini ladder)

    private func tierPathSection(_ state: TierState) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Label("Tier Ladder", systemImage: "arrow.up.right")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            CFCard {
                VStack(spacing: 0) {
                    ForEach(Array(TierKey.allCases.enumerated()), id: \.element.rawValue) { index, tier in
                        if index > 0 {
                            Divider()
                                .padding(.leading, .cfSpacing40 + .cfSpacing12)
                        }
                        tierLadderRow(tier, currentTier: state.currentTier)
                    }
                }
            }
        }
    }

    private func tierLadderRow(_ tier: TierKey, currentTier: TierKey) -> some View {
        let isCurrent = tier == currentTier
        let isReached = tier.rank <= currentTier.rank

        return HStack(spacing: .cfSpacing12) {
            ZStack {
                Circle()
                    .fill(isReached ? tierColor(tier).opacity(0.15) : Color.cfSecondaryFill)
                if isReached {
                    Image(systemName: isCurrent ? tierSystemImage(tier) : "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tierColor(tier))
                } else {
                    Image(systemName: tierSystemImage(tier))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.cfTertiaryLabel)
                }
            }
            .frame(width: .cfSpacing40, height: .cfSpacing40)

            Text(tier.displayName)
                .font(isCurrent ? .cfBody.weight(.semibold) : .cfBody)
                .foregroundStyle(isReached ? Color.cfLabel : Color.cfTertiaryLabel)

            Spacer()

            if isCurrent {
                Text("You are here")
                    .font(.cfCaption.weight(.medium))
                    .foregroundStyle(tierColor(tier))
            } else if isReached {
                Image(systemName: "checkmark.circle.fill")
                    .font(.cfCaption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, .cfSpacing12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tierLadderAccessibilityLabel(tier, isCurrent: isCurrent, isReached: isReached))
    }

    // MARK: - Error

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

    // MARK: - Platform helpers

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .automatic
        #endif
    }

    // MARK: - Accessibility helpers

    private func heroAccessibilityLabel(_ state: TierState) -> String {
        var label = "Current tier: \(state.currentTier.displayName)."
        if let next = state.nextTier {
            label += " \(Int(state.overallProgress * 100)) percent toward \(next.displayName)."
        } else {
            label += " Top tier achieved."
        }
        return label
    }

    private func tierLadderAccessibilityLabel(_ tier: TierKey, isCurrent: Bool, isReached: Bool) -> String {
        if isCurrent { return "\(tier.displayName): current tier" }
        if isReached { return "\(tier.displayName): completed" }
        return "\(tier.displayName): not yet reached"
    }
}

// MARK: - TierSkeletonView

private struct TierSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: .cfSpacing20) {
                CFCard {
                    CFSkeleton()
                        .frame(height: 100)
                }
                CFCard {
                    CFSkeleton()
                        .frame(height: 140)
                }
                CFCard {
                    CFSkeleton()
                        .frame(height: 200)
                }
            }
            .padding(.cfSpacing16)
        }
    }
}

// MARK: - Previews

#Preview("Tier — Analyst (light)") {
    let presenter = CelebrationPresenter()
    let model = TierModel(repository: .previewTierAnalyst, celebrationPresenter: presenter)
    return NavigationStack {
        TierView(model: model)
    }
}

#Preview("Tier — Luminary (dark)") {
    let presenter = CelebrationPresenter()
    let model = TierModel(repository: .previewTierLuminary, celebrationPresenter: presenter)
    return NavigationStack {
        TierView(model: model)
    }
    .preferredColorScheme(.dark)
}

#Preview("Tier — Reader (XXL text)") {
    let presenter = CelebrationPresenter()
    let model = TierModel(repository: .previewTierReader, celebrationPresenter: presenter)
    return NavigationStack {
        TierView(model: model)
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Tier — Just Promoted (tier-up)") {
    let presenter = CelebrationPresenter()
    let model = TierModel(repository: .previewTierPromoted, celebrationPresenter: presenter)
    return NavigationStack {
        TierView(model: model)
    }
}

#Preview("Tier Explainer") {
    TierExplainerView(currentTier: .analyst)
}
