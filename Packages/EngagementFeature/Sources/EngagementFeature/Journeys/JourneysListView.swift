import SwiftUI
import DesignSystem
import Models
import CoreKit

// MARK: - JourneysListView

/// The journeys browser — shows all available curated multi-book paths.
///
/// Pass an `onOpenBook` closure from the parent feature so tapping a journey
/// book can route into the reader without creating a cross-package import.
public struct JourneysListView: View {

    private let model: JourneysModel
    private let repository: JourneysRepository
    private let celebrationPresenter: CelebrationPresenter
    private let onOpenBook: (String) -> Void

    public init(
        model: JourneysModel,
        repository: JourneysRepository,
        celebrationPresenter: CelebrationPresenter,
        onOpenBook: @escaping (String) -> Void
    ) {
        self.model = model
        self.repository = repository
        self.celebrationPresenter = celebrationPresenter
        self.onOpenBook = onOpenBook
    }

    public var body: some View {
        Group {
            switch model.loadState {
            case .loading:
                JourneysSkeletonView()
            case .loaded(let journeys) where journeys.isEmpty:
                CFEmptyState(
                    systemImage: "map",
                    title: "No Journeys Yet",
                    description: "Curated multi-book paths will appear here."
                )
            case .loaded(let journeys):
                journeyList(journeys)
            case .error(let error):
                CFEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn't Load Journeys",
                    description: error.localizedDescription
                )
            }
        }
        .navigationTitle("Journeys")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .background(Color.cfGroupedBackground.ignoresSafeArea())
        .task { model.load() }
        .refreshable { await model.refresh() }
    }

    // MARK: - Loaded list

    private func journeyList(_ journeys: [JourneyCatalogItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: .cfSpacing16) {
                ForEach(journeys) { journey in
                    NavigationLink {
                        JourneyDetailView(
                            model: JourneyDetailModel(
                                journey: journey,
                                repository: repository,
                                celebrationPresenter: celebrationPresenter
                            ),
                            onOpenBook: onOpenBook
                        )
                    } label: {
                        JourneyCardView(journey: journey)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, .cfSpacing16)
            .padding(.vertical, .cfSpacing12)
        }
    }
}

// MARK: - JourneyCardView

/// A card in the journeys list — shows the gradient cover, title, duration, and book count.
struct JourneyCardView: View {

    let journey: JourneyCatalogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            gradientHeader
            infoSection
        }
        .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Subviews

    private var gradientHeader: some View {
        ZStack(alignment: .bottomLeading) {
            JourneyCoverView(gradient: journey.gradient, height: 120)
            VStack(alignment: .leading, spacing: .cfSpacing4) {
                Text(journey.title)
                    .font(.cfTitle3)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                Text(durationLabel)
                    .font(.cfCaption)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .padding(.cfSpacing12)
        }
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius16))
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Text(journey.description)
                .font(.cfCallout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: .cfSpacing12) {
                Label("\(journey.books.count) books", systemImage: "books.vertical")
                    .font(.cfCaption)
                    .foregroundStyle(.secondary)

                if let points = journey.bonusFlowPoints, points > 0 {
                    Label("+\(points) FP", systemImage: "bolt.fill")
                        .font(.cfCaption)
                        .foregroundStyle(.yellow)
                }

                if let badge = journey.completionBadge {
                    Label(badge.name, systemImage: "medal.fill")
                        .font(.cfCaption)
                        .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 0.15))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.cfCaption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, .cfSpacing12)
        .padding(.vertical, .cfSpacing12)
    }

    // MARK: - Helpers

    private var durationLabel: String {
        "\(journey.durationWeeks) week\(journey.durationWeeks == 1 ? "" : "s")"
    }

    private var accessibilityLabel: String {
        "\(journey.title), \(durationLabel), \(journey.books.count) books. \(journey.description)"
    }
}

// MARK: - JourneyCoverView

/// Renders a journey's gradient cover (or a fallback accent gradient).
struct JourneyCoverView: View {

    let gradient: JourneyGradient?
    var height: CGFloat = 160

    var body: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private var gradientColors: [Color] {
        guard let g = gradient else {
            return [Color.cfAccent, Color.cfAccent.opacity(0.6)]
        }
        return [Color(hex: g.startColor), Color(hex: g.endColor)]
    }
}

// MARK: - Skeleton

struct JourneysSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: .cfSpacing16) {
                ForEach(0..<4, id: \.self) { _ in
                    CFSkeleton()
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: .cfRadius16))
                }
            }
            .padding(.horizontal, .cfSpacing16)
            .padding(.vertical, .cfSpacing12)
        }
    }
}

// MARK: - Previews

#Preview("Journeys List") {
    NavigationStack {
        JourneysListView(
            model: .preview,
            repository: .preview,
            celebrationPresenter: CelebrationPresenter(),
            onOpenBook: { _ in }
        )
    }
}

#Preview("Journeys List — dark") {
    NavigationStack {
        JourneysListView(
            model: .preview,
            repository: .preview,
            celebrationPresenter: CelebrationPresenter(),
            onOpenBook: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Journeys List — XXL") {
    NavigationStack {
        JourneysListView(
            model: .preview,
            repository: .preview,
            celebrationPresenter: CelebrationPresenter(),
            onOpenBook: { _ in }
        )
    }
    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}
