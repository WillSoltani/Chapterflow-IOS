import SwiftUI
import DesignSystem
import Models
import CoreKit

// MARK: - JourneyDetailView

/// Detail view for a single journey — shows the book sequence with reasons,
/// the user's progress, and a Start / Continue action.
public struct JourneyDetailView: View {

    private let model: JourneyDetailModel
    private let onOpenBook: (String) -> Void

    public init(model: JourneyDetailModel, onOpenBook: @escaping (String) -> Void) {
        self.model = model
        self.onOpenBook = onOpenBook
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection
                contentSection
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(model.journey.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .background(Color.cfGroupedBackground.ignoresSafeArea())
        .task { model.load() }
        .refreshable { await model.refresh() }
        .celebrationOverlay(model.celebrationPresenter)
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .bottomLeading) {
            JourneyCoverView(gradient: model.journey.gradient, height: 220)
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)

            VStack(alignment: .leading, spacing: .cfSpacing8) {
                Text(model.journey.title)
                    .font(.cfTitle1)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)

                HStack(spacing: .cfSpacing12) {
                    Label(durationLabel, systemImage: "calendar")
                        .font(.cfFootnote)
                        .foregroundStyle(.white.opacity(0.9))
                    Label("\(model.journey.books.count) books", systemImage: "books.vertical")
                        .font(.cfFootnote)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.cfSpacing16)
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(spacing: .cfSpacing20) {
            descriptionCard
            progressSection
            rewardsSection
            booksSection
            actionButton
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing20)
    }

    // MARK: - Description

    private var descriptionCard: some View {
        CFCard {
            Text(model.journey.description)
                .font(.cfBody)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        switch model.loadState {
        case .loading:
            CFSkeleton()
                .frame(height: 80)
                .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        case .loaded(let userJourney):
            if userJourney.isCompleted {
                completedBanner
            } else {
                CFCard {
                    VStack(alignment: .leading, spacing: .cfSpacing12) {
                        HStack {
                            Text("Progress")
                                .font(.cfSubheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(userJourney.completedBookIds.count) / \(model.journey.books.count)")
                                .font(.cfCaption)
                                .foregroundStyle(.secondary)
                        }
                        CFProgressBar(fraction: model.progressFraction)
                    }
                }
            }
        case .notStarted, .error:
            EmptyView()
        }
    }

    private var completedBanner: some View {
        CFCard {
            HStack(spacing: .cfSpacing12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text("Journey Complete!")
                        .font(.cfHeadline)
                        .foregroundStyle(.primary)
                    Text("You've finished all \(model.journey.books.count) books.")
                        .font(.cfCallout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Rewards

    @ViewBuilder
    private var rewardsSection: some View {
        let hasBadge = model.journey.completionBadge != nil
        let hasPoints = (model.journey.bonusFlowPoints ?? 0) > 0
        if hasBadge || hasPoints {
            CFCard {
                VStack(alignment: .leading, spacing: .cfSpacing12) {
                    Text("Completion Rewards")
                        .font(.cfSubheadline)
                        .foregroundStyle(.primary)
                    HStack(spacing: .cfSpacing16) {
                        if let badge = model.journey.completionBadge {
                            Label(badge.name, systemImage: "medal.fill")
                                .font(.cfCallout)
                                .foregroundStyle(.yellow)
                        }
                        if let pts = model.journey.bonusFlowPoints, pts > 0 {
                            Label("+\(pts) Flow Points", systemImage: "bolt.fill")
                                .font(.cfCallout)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Books

    private var booksSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Text("Books in This Journey")
                .font(.cfSubheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, .cfSpacing4)

            VStack(spacing: .cfSpacing8) {
                let sorted = model.journey.books.sorted { $0.order < $1.order }
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, book in
                    JourneyBookRowView(
                        book: book,
                        index: index,
                        isCompleted: isBookCompleted(book.bookId),
                        isCurrent: isCurrentBook(index),
                        onTap: { onOpenBook(book.bookId) }
                    )
                }
            }
        }
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        switch model.loadState {
        case .loading:
            EmptyView()
        case .notStarted:
            Button {
                Task { await model.start() }
            } label: {
                Group {
                    if model.isStarting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Start Journey")
                            .font(.cfHeadline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cfAccent)
            .disabled(model.isStarting)
            .accessibilityLabel("Start the \(model.journey.title) journey")
        case .loaded(let uj):
            if !uj.isCompleted, let activeBook = model.activeBook {
                Button {
                    onOpenBook(activeBook.bookId)
                } label: {
                    Text("Continue: \(activeBook.title)")
                        .font(.cfHeadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cfAccent)
                .accessibilityLabel("Continue reading \(activeBook.title)")
            }
        case .error(let error):
            VStack(spacing: .cfSpacing12) {
                Text(error.localizedDescription)
                    .font(.cfCallout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await model.refresh() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Helpers

    private var durationLabel: String {
        let w = model.journey.durationWeeks
        return "\(w) week\(w == 1 ? "" : "s")"
    }

    private func isBookCompleted(_ bookId: String) -> Bool {
        guard case .loaded(let uj) = model.loadState else { return false }
        return uj.completedBookIds.contains(bookId)
    }

    private func isCurrentBook(_ index: Int) -> Bool {
        guard case .loaded = model.loadState, !model.isCompleted else { return false }
        return index == (model.currentBookIndex ?? 0)
    }
}

// MARK: - CFProgressBar (local helper)

private struct CFProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.cfFill)
                    .frame(height: 6)
                Capsule()
                    .fill(Color.cfAccent)
                    .frame(width: max(0, geo.size.width * fraction), height: 6)
                    .animation(.easeInOut(duration: 0.3), value: fraction)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Previews

#Preview("Journey Detail — not started") {
    NavigationStack {
        JourneyDetailView(
            model: .previewNotStarted,
            onOpenBook: { _ in }
        )
    }
}

#Preview("Journey Detail — in progress") {
    NavigationStack {
        JourneyDetailView(
            model: .previewInProgress,
            onOpenBook: { _ in }
        )
    }
}

#Preview("Journey Detail — dark") {
    NavigationStack {
        JourneyDetailView(
            model: .previewInProgress,
            onOpenBook: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Journey Detail — XXL") {
    NavigationStack {
        JourneyDetailView(
            model: .previewNotStarted,
            onOpenBook: { _ in }
        )
    }
    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}
