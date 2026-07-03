import SwiftUI
import DesignSystem
import Models
import CoreKit

// MARK: - BadgesView

/// The Badges & Achievements screen.
///
/// Shows a filterable grid of earned and locked badges, grouped by achievement
/// track (mastery / consistency / exploration / hidden). Tapping a badge opens a
/// detail sheet. Newly earned badges surface through the shared
/// ``CelebrationPresenter`` — mount the view with `.celebrationOverlay(_:)` at
/// the feature root so the shared presenter is reused.
///
/// ```swift
/// BadgesView(model: BadgesModel(repository: repo, presenter: presenter))
///     .celebrationOverlay(presenter)
/// ```
public struct BadgesView: View {

    private let model: BadgesModel

    public init(model: BadgesModel) {
        self.model = model
    }

    // Three-column grid, slightly narrower columns on compact width.
    private let columns = [
        GridItem(.adaptive(minimum: 90, maximum: 120)),
    ]

    public var body: some View {
        @Bindable var bindable = model
        Group {
            switch model.loadState {
            case .loading:
                BadgesSkeletonView()
            case .loaded:
                loadedView
            case .error(let error):
                errorView(error)
            }
        }
        .navigationTitle("Achievements")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .background(Color.cfGroupedBackground.ignoresSafeArea())
        .task { model.load() }
        .sheet(item: $bindable.selectedBadge) { badge in
            BadgeDetailSheet(badge: badge) {
                model.selectedBadge = nil
            }
        }
    }

    // MARK: - Loaded

    @ViewBuilder
    private var loadedView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: .cfSpacing24, pinnedViews: [.sectionHeaders]) {
                Section {
                    if model.displayedBadges.isEmpty {
                        emptyTrackView
                    } else {
                        badgeGrid
                    }
                } header: {
                    trackFilterBar
                        .background(Color.cfGroupedBackground)
                }
            }
            .padding(.horizontal, .cfSpacing16)
            .padding(.bottom, .cfSpacing24)
        }
        .refreshable {
            await model.refresh()
        }
        .animation(.easeInOut(duration: 0.25), value: model.selectedTrack)
    }

    // MARK: - Track filter

    private var trackFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .cfSpacing8) {
                TrackPill(
                    title: "All",
                    systemImage: "square.grid.2x2",
                    isSelected: model.selectedTrack == nil
                ) {
                    model.selectedTrack = nil
                }
                ForEach(AchievementTrack.allCases, id: \.self) { track in
                    TrackPill(
                        title: track.displayName,
                        systemImage: track.systemImage,
                        isSelected: model.selectedTrack == track
                    ) {
                        model.selectedTrack = track
                    }
                }
            }
            .padding(.vertical, .cfSpacing12)
        }
        .accessibilityLabel("Achievement tracks")
    }

    // MARK: - Badge grid

    private var badgeGrid: some View {
        LazyVGrid(columns: columns, spacing: .cfSpacing16) {
            ForEach(model.displayedBadges) { badge in
                BadgeGridCell(badge: badge)
                    .onTapGesture {
                        model.selectedBadge = badge
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.displayedBadges.map(\.badgeId))
    }

    // MARK: - Empty state

    private var emptyTrackView: some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: model.selectedTrack?.systemImage ?? "medal")
                .font(.system(size: 40))
                .foregroundStyle(Color.cfTertiaryLabel)
            Text("No \(model.selectedTrack?.displayName ?? "") badges yet")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.cfSpacing48)
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
}

// MARK: - TrackPill

private struct TrackPill: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.cfCaption)
                .padding(.horizontal, .cfSpacing12)
                .padding(.vertical, .cfSpacing8)
                .foregroundStyle(isSelected ? Color.white : Color.cfLabel)
                .background(
                    isSelected ? Color.cfAccent : Color.cfSecondaryBackground,
                    in: Capsule()
                )
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

// MARK: - BadgesSkeletonView

private struct BadgesSkeletonView: View {
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 90, maximum: 120))],
            spacing: .cfSpacing16
        ) {
            ForEach(0..<12, id: \.self) { _ in
                VStack(spacing: .cfSpacing8) {
                    CFSkeleton()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                    CFSkeleton()
                        .frame(height: 12)
                        .clipShape(Capsule())
                }
                .padding(.cfSpacing8)
            }
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.top, .cfSpacing16)
    }
}

// MARK: - Previews

#Preview("Badges — light") {
    NavigationStack {
        BadgesView(model: .preview)
    }
}

#Preview("Badges — dark") {
    NavigationStack {
        BadgesView(model: .preview)
    }
    .preferredColorScheme(.dark)
}

#Preview("Badges — XXL text") {
    NavigationStack {
        BadgesView(model: .preview)
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Badges — error") {
    NavigationStack {
        BadgesView(model: .previewError)
    }
}
