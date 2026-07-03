import SwiftUI
import DesignSystem
import Models
import CoreKit

// MARK: - ReviewsView

/// Hub view for the Reviews tab.
///
/// Shows today's due-card count, a "Start Session" CTA, and a pending-sync
/// badge when offline grades are waiting to be uploaded. Presents
/// ``ReviewSessionView`` as a full-screen cover when the user starts a session.
public struct ReviewsView: View {

    @State private var model: ReviewsModel
    @State private var showingSession: Bool = false

    public init(model: ReviewsModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: .cfSpacing24) {
                    heroSection
                    if model.pendingGradeCount > 0 {
                        pendingBadge
                    }
                    actionSection
                }
                .padding(.horizontal, .cfSpacing16)
                .padding(.top, .cfSpacing24)
            }
            .navigationTitle("Reviews")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .background(Color.cfGroupedBackground.ignoresSafeArea())
            .refreshable { await model.refresh() }
            .task { model.load() }
            #if os(iOS)
            .fullScreenCover(isPresented: $showingSession) {
                ReviewSessionView(model: model)
            }
            #else
            .sheet(isPresented: $showingSession) {
                ReviewSessionView(model: model)
            }
            #endif
            .onChange(of: model.sessionState) { _, newState in
                if case .inactive = newState { showingSession = false }
                if case .front = newState, !showingSession { showingSession = true }
            }
        }
    }

    // MARK: - Hero section

    @ViewBuilder
    private var heroSection: some View {
        switch model.loadState {
        case .idle, .loading:
            loadingHero
        case .loaded(let dueCount, let nextDue):
            loadedHero(dueCount: dueCount, nextDue: nextDue)
        case .error(let error):
            errorHero(error)
        }
    }

    private var loadingHero: some View {
        CFCard {
            VStack(spacing: .cfSpacing16) {
                CFSkeleton()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                CFSkeleton()
                    .frame(width: 120, height: 24)
                    .clipShape(Capsule())
                CFSkeleton()
                    .frame(width: 180, height: 16)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, .cfSpacing24)
        }
    }

    private func loadedHero(dueCount: Int, nextDue: Date?) -> some View {
        CFCard {
            VStack(spacing: .cfSpacing16) {
                ZStack {
                    Circle()
                        .fill(Color.cfAccent.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: dueCount > 0 ? "star.fill" : "checkmark.seal.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(dueCount > 0 ? Color.cfAccent : .green)
                }

                VStack(spacing: .cfSpacing4) {
                    if dueCount > 0 {
                        Text("\(dueCount)")
                            .font(.cfLargeTitle)
                            .foregroundStyle(Color.cfLabel)
                        Text(dueCount == 1 ? "card due today" : "cards due today")
                            .font(.cfSubheadline)
                            .foregroundStyle(Color.cfSecondaryLabel)
                    } else {
                        Text("All caught up!")
                            .font(.cfTitle2)
                            .foregroundStyle(Color.cfLabel)
                        if let nextDue {
                            Text("Next review \(nextDue.formatted(.relative(presentation: .named)))")
                                .font(.cfSubheadline)
                                .foregroundStyle(Color.cfSecondaryLabel)
                        } else {
                            Text("No upcoming reviews")
                                .font(.cfSubheadline)
                                .foregroundStyle(Color.cfSecondaryLabel)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, .cfSpacing24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(dueCount > 0
            ? "\(dueCount) \(dueCount == 1 ? "card" : "cards") due today"
            : "All caught up. \(nextDue.map { "Next review \($0.formatted(.relative(presentation: .named)))" } ?? "No upcoming reviews")"
        )
    }

    private func errorHero(_ error: AppError) -> some View {
        CFCard {
            VStack(spacing: .cfSpacing12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .accessibilityHidden(true)
                Text("Couldn't load reviews")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfLabel)
                Text(error.localizedDescription)
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await model.refresh() } }
                    .font(.cfSubheadline)
                    .tint(Color.cfAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, .cfSpacing24)
        }
    }

    // MARK: - Offline pending badge

    private var pendingBadge: some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "arrow.up.circle")
                .foregroundStyle(Color.cfAccent)
                .accessibilityHidden(true)
            Text("\(model.pendingGradeCount) grade\(model.pendingGradeCount == 1 ? "" : "s") pending upload")
                .font(.cfFootnote)
                .foregroundStyle(Color.cfSecondaryLabel)
            Spacer()
        }
        .padding(.horizontal, .cfSpacing12)
        .padding(.vertical, .cfSpacing8)
        .background(Color.cfAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: .cfRadius8))
        .accessibilityLabel("\(model.pendingGradeCount) offline \(model.pendingGradeCount == 1 ? "grade" : "grades") pending upload")
    }

    // MARK: - Action section

    @ViewBuilder
    private var actionSection: some View {
        if case .loaded(let dueCount, _) = model.loadState, dueCount > 0 {
            Button {
                model.startSession()
            } label: {
                Text("Start Review Session")
                    .font(.cfHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .cfSpacing16)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.cfAccent)
            .disabled(model.isLoading)
            .accessibilityLabel("Start a review session with \(dueCount) due cards")
        }
    }
}

// MARK: - AppError description

private extension AppError {
    var localizedDescription: String {
        switch self {
        case .offline:           return "You're offline. Pull to refresh when you reconnect."
        case .unauthenticated,
             .reauthRequired:    return "Please sign in again."
        case .rateLimited:       return "Too many requests. Please wait and try again."
        case .notFound:          return "Reviews not found."
        case .decoding:          return "Received unexpected data from the server."
        case .server(_, let msg, _): return msg
        default:                 return "Something went wrong."
        }
    }
}

// MARK: - Previews

#if DEBUG
import Networking
import Persistence

#Preview("Due cards (hub)", traits: .sizeThatFitsLayout) {
    let model = ReviewsModel(repository: ReviewsRepository(apiClient: MockAPIClient()))
    model.loadState = .loaded(dueCount: 7, nextDue: nil)
    return ReviewsView(model: model)
}

#Preview("All caught up") {
    let model = ReviewsModel(repository: ReviewsRepository(apiClient: MockAPIClient()))
    model.loadState = .loaded(dueCount: 0, nextDue: Date().addingTimeInterval(86400))
    return ReviewsView(model: model)
}

#Preview("Loading state") {
    let model = ReviewsModel(repository: ReviewsRepository(apiClient: MockAPIClient()))
    model.loadState = .loading
    return ReviewsView(model: model)
}

#Preview("Pending offline badge") {
    let model = ReviewsModel(repository: ReviewsRepository(apiClient: MockAPIClient()))
    model.loadState = .loaded(dueCount: 3, nextDue: nil)
    return ReviewsView(model: model)
}

#Preview("Error state") {
    let model = ReviewsModel(repository: ReviewsRepository(apiClient: MockAPIClient()))
    model.loadState = .error(.offline)
    return ReviewsView(model: model)
}

#Preview("Dark mode — due") {
    let model = ReviewsModel(repository: ReviewsRepository(apiClient: MockAPIClient()))
    model.loadState = .loaded(dueCount: 12, nextDue: nil)
    return ReviewsView(model: model)
        .preferredColorScheme(.dark)
}

#Preview("XXL Dynamic Type — due") {
    let model = ReviewsModel(repository: ReviewsRepository(apiClient: MockAPIClient()))
    model.loadState = .loaded(dueCount: 5, nextDue: nil)
    return ReviewsView(model: model)
        .dynamicTypeSize(.accessibility3)
}
#endif
