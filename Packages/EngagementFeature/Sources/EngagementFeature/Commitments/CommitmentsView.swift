import SwiftUI
import DesignSystem
import Models
import CoreKit

// MARK: - CommitmentsView

/// Lists the user's active and completed if-then commitments.
///
/// Presented from a chapter completion screen or the engagement tab.
public struct CommitmentsView: View {

    private let model: CommitmentsModel
    @State private var showingCreate = false
    @State private var selectedForReflection: Commitment?
    @State private var createContext: CreateContext?

    public struct CreateContext {
        let bookId: String
        let chapterId: String
    }

    public init(model: CommitmentsModel, createContext: CreateContext? = nil) {
        self.model = model
        self._createContext = State(initialValue: createContext)
    }

    public var body: some View {
        Group {
            switch model.loadState {
            case .idle, .loading:
                CommitmentsSkeletonView()
            case .loaded(let all):
                loadedView(all)
            case .error(let error):
                errorView(error)
            }
        }
        .navigationTitle("Commitments")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .background(Color.cfGroupedBackground.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("New commitment")
                }
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateCommitmentView(model: model, context: createContext)
        }
        .sheet(item: $selectedForReflection) { commitment in
            CommitmentReflectionView(commitment: commitment, model: model)
        }
        .task { model.load() }
        .refreshable { await model.refresh() }
    }

    // MARK: - Loaded

    private func loadedView(_ all: [Commitment]) -> some View {
        Group {
            if all.isEmpty {
                emptyState
            } else {
                commitmentList(all)
            }
        }
    }

    private func commitmentList(_ all: [Commitment]) -> some View {
        List {
            let overdue = model.overdueCommitments
            if !overdue.isEmpty {
                Section("Ready for reflection") {
                    ForEach(overdue) { commitment in
                        CommitmentRow(
                            commitment: commitment,
                            onReflect: { selectedForReflection = commitment }
                        )
                    }
                }
            }

            let active = model.activeCommitments.filter { !overdue.map(\.id).contains($0.id) }
            if !active.isEmpty {
                Section("Active") {
                    ForEach(active) { commitment in
                        CommitmentRow(
                            commitment: commitment,
                            onReflect: { selectedForReflection = commitment }
                        )
                    }
                }
            }

            let done = model.doneCommitments
            if !done.isEmpty {
                Section("Completed") {
                    ForEach(done) { commitment in
                        CommitmentRow(
                            commitment: commitment,
                            onReflect: nil
                        )
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: .cfSpacing24) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 56))
                .foregroundStyle(Color.cfAccent)
                .accessibilityHidden(true)
            VStack(spacing: .cfSpacing8) {
                Text("No commitments yet")
                    .font(.cfTitle3)
                    .foregroundStyle(Color.cfLabel)
                Text("After finishing a chapter, create an if-then plan to apply what you learned.")
                    .font(.cfBody)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, .cfSpacing32)
            }
            Button("Add commitment") { showingCreate = true }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add a new commitment")
            Spacer()
        }
    }

    // MARK: - Error

    private func errorView(_ error: AppError) -> some View {
        VStack(spacing: .cfSpacing16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.cfSecondaryLabel)
                .accessibilityHidden(true)
            Text("Couldn't load commitments")
                .font(.cfHeadline)
                .foregroundStyle(Color.cfLabel)
            Button("Try again") { Task { await model.refresh() } }
                .buttonStyle(.bordered)
            Spacer()
        }
    }
}

// MARK: - CommitmentRow

struct CommitmentRow: View {

    let commitment: Commitment
    let onReflect: (() -> Void)?

    private var isOverdue: Bool {
        commitment.status == .active && commitment.followUpDate <= Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text("If \(commitment.ifStatement)")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfLabel)
                        .lineLimit(2)
                    Text("then \(commitment.thenStatement)")
                        .font(.cfBody)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .lineLimit(2)
                }
                Spacer()
                statusBadge
            }

            HStack(spacing: .cfSpacing4) {
                Image(systemName: "calendar")
                    .font(.cfCaption)
                    .foregroundStyle(isOverdue ? Color.orange : Color.cfTertiaryLabel)
                    .accessibilityHidden(true)
                Text(followUpLabel)
                    .font(.cfCaption)
                    .foregroundStyle(isOverdue ? Color.orange : Color.cfTertiaryLabel)
            }

            if let outcome = commitment.outcome {
                outcomeChip(outcome)
            }

            if isOverdue, let reflect = onReflect {
                Button("Reflect now") { reflect() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Submit reflection for this commitment")
            }
        }
        .padding(.vertical, .cfSpacing4)
        .accessibilityElement(children: .combine)
    }

    private var statusBadge: some View {
        Group {
            switch commitment.status {
            case .active:
                Text(isOverdue ? "Due" : "Active")
                    .font(.cfCaption2)
                    .padding(.horizontal, .cfSpacing8)
                    .padding(.vertical, .cfSpacing4)
                    .background(isOverdue ? Color.orange.opacity(0.15) : Color.cfAccent.opacity(0.12))
                    .foregroundStyle(isOverdue ? Color.orange : Color.cfAccent)
                    .clipShape(Capsule())
            case .done:
                Text("Done")
                    .font(.cfCaption2)
                    .padding(.horizontal, .cfSpacing8)
                    .padding(.vertical, .cfSpacing4)
                    .background(Color.green.opacity(0.12))
                    .foregroundStyle(Color.green)
                    .clipShape(Capsule())
            case .unknown:
                EmptyView()
            }
        }
    }

    private var followUpLabel: String {
        if commitment.status == .done {
            return "Completed"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Follow-up \(formatter.localizedString(for: commitment.followUpDate, relativeTo: Date()))"
    }

    private func outcomeChip(_ outcome: CommitmentOutcome) -> some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: outcomeIcon(outcome))
                .font(.cfCaption)
                .accessibilityHidden(true)
            Text(outcomeLabel(outcome))
                .font(.cfCaption)
        }
        .foregroundStyle(outcomeColor(outcome))
    }

    private func outcomeIcon(_ outcome: CommitmentOutcome) -> String {
        switch outcome {
        case .helped: return "hand.thumbsup.fill"
        case .partly: return "hand.thumbsup"
        case .didnt:  return "hand.thumbsdown"
        case .unknown: return "questionmark"
        }
    }

    private func outcomeLabel(_ outcome: CommitmentOutcome) -> String {
        switch outcome {
        case .helped:  return "It helped"
        case .partly:  return "Partly helped"
        case .didnt:   return "Didn't help"
        case .unknown: return "Unknown"
        }
    }

    private func outcomeColor(_ outcome: CommitmentOutcome) -> Color {
        switch outcome {
        case .helped:  return .green
        case .partly:  return Color.orange
        case .didnt:   return Color.red
        case .unknown: return Color.cfSecondaryLabel
        }
    }
}

// MARK: - Skeleton

struct CommitmentsSkeletonView: View {
    var body: some View {
        List {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: .cfSpacing8) {
                    CFSkeleton().frame(width: 200, height: 16)
                    CFSkeleton().frame(width: 160, height: 14)
                    CFSkeleton().frame(width: 80, height: 12)
                }
                .padding(.vertical, .cfSpacing4)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }
}

// MARK: - Previews

#Preview("Loaded — light") {
    NavigationStack {
        CommitmentsView(model: CommitmentsModel.preview)
    }
}

#Preview("Loaded — dark") {
    NavigationStack {
        CommitmentsView(model: CommitmentsModel.preview)
    }
    .preferredColorScheme(.dark)
}

#Preview("Loaded — XXL text") {
    NavigationStack {
        CommitmentsView(model: CommitmentsModel.preview)
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Empty state") {
    NavigationStack {
        CommitmentsView(model: CommitmentsModel.previewEmpty)
    }
}
