import SwiftUI
import Models
import DesignSystem
import CoreKit

// MARK: - ScenariosView

/// Hub for the Scenarios (apply-it) feature.
///
/// Shows:
/// - My submitted scenarios with moderation status and points
/// - Community approved scenarios as inspiration (when server exposes them)
/// - A compose button to write a new scenario
///
/// Points and status are server-authoritative and reflected directly from the
/// server response — never modified client-side.
public struct ScenariosView: View {

    private let model: ScenariosModel
    @State private var isComposing: Bool = false
    @State private var selectedScenario: UserScenario?

    public init(model: ScenariosModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.loadState {
            case .idle, .loading:
                loadingView
            case .loaded:
                loadedContent
            case .error(let message):
                errorView(message: message)
            }
        }
        .navigationTitle("Apply It")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .background(Color.cfGroupedBackground.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.resetForm()
                    isComposing = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .accessibilityLabel("Write a scenario")
                }
            }
        }
        .sheet(isPresented: $isComposing) {
            ComposeScenarioView(model: model)
        }
        .navigationDestination(item: $selectedScenario) { scenario in
            ScenarioDetailView(scenario: scenario)
        }
        .task { model.load() }
        .refreshable { await model.refresh() }
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: .cfSpacing24) {
            ForEach(0..<3, id: \.self) { _ in
                skeletonRow
            }
            Spacer()
        }
        .padding(.cfSpacing20)
    }

    private var skeletonRow: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            RoundedRectangle(cornerRadius: .cfRadius4)
                .fill(Color.cfSecondaryFill)
                .frame(height: 16)
                .frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: .cfRadius4)
                .fill(Color.cfSecondaryFill)
                .frame(height: 12)
                .frame(maxWidth: 200)
        }
        .padding(.cfSpacing16)
        .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius12))
    }

    // MARK: Loaded

    @ViewBuilder
    private var loadedContent: some View {
        List {
            if model.pendingCount > 0 {
                pendingBanner
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .padding(.bottom, .cfSpacing8)
            }

            // My scenarios
            Section {
                if model.myScenarios.isEmpty {
                    emptyMyScenarios
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(model.myScenarios) { scenario in
                        Button {
                            selectedScenario = scenario
                        } label: {
                            ScenarioRow(scenario: scenario)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.cfSecondaryBackground)
                    }
                }
            } header: {
                Text("My Scenarios")
                    .font(.cfCaption.weight(.semibold))
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            // Community scenarios (only if server returns them)
            if !model.communityScenarios.isEmpty {
                Section {
                    ForEach(model.communityScenarios) { scenario in
                        CommunityScenarioRow(scenario: scenario)
                            .listRowBackground(Color.cfSecondaryBackground)
                    }
                } header: {
                    Text("From the Community")
                        .font(.cfCaption.weight(.semibold))
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: Pending outbox banner

    private var pendingBanner: some View {
        HStack(spacing: .cfSpacing10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.cfAccent)
            Text("\(model.pendingCount) submission\(model.pendingCount == 1 ? "" : "s") will sync when online")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
            Spacer()
        }
        .padding(.cfSpacing12)
        .background(Color.cfAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: .cfRadius10))
        .padding(.horizontal, .cfSpacing16)
    }

    // MARK: Empty state

    private var emptyMyScenarios: some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "lightbulb")
                .font(.system(size: 36))
                .foregroundStyle(Color.cfTertiaryLabel)

            VStack(spacing: .cfSpacing4) {
                Text("No scenarios yet")
                    .font(.cfBody.weight(.semibold))
                    .foregroundStyle(Color.cfLabel)
                Text("Write your first real-world application for this chapter and earn Flow Points when it's approved.")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)
            }

            Button {
                model.resetForm()
                isComposing = true
            } label: {
                Text("Write a Scenario")
                    .font(.cfBody.weight(.semibold))
                    .foregroundStyle(Color.cfAccent)
            }
            .accessibilityLabel("Write your first scenario")
        }
        .frame(maxWidth: .infinity)
        .padding(.cfSpacing40)
    }

    // MARK: Error

    private func errorView(message: String) -> some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color.cfSecondaryLabel)
            Text("Could not load scenarios")
                .font(.cfBody.weight(.semibold))
            Text(message)
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await model.refresh() }
            }
            .foregroundStyle(Color.cfAccent)
        }
        .padding(.cfSpacing40)
    }
}

// MARK: - CommunityScenarioRow

/// A row showing an approved community scenario as inspiration.
private struct CommunityScenarioRow: View {
    let scenario: CommunityScenario

    var body: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            HStack(alignment: .firstTextBaseline) {
                Text(scenario.title)
                    .font(.cfBody.weight(.semibold))
                    .foregroundStyle(Color.cfLabel)
                    .lineLimit(2)
                Spacer()
                scopeTag
            }
            Text(scenario.scenario)
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
                .lineLimit(3)
            if let author = scenario.authorName {
                Text("— \(author)")
                    .font(.cfCaption2)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }
        }
        .padding(.vertical, .cfSpacing4)
        .accessibilityElement(children: .combine)
    }

    private var scopeTag: some View {
        Text(scopeLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.cfSecondaryLabel)
            .padding(.horizontal, .cfSpacing6)
            .padding(.vertical, 3)
            .background(Color.cfSecondaryFill, in: Capsule())
    }

    private var scopeLabel: String {
        switch scenario.scope {
        case .work:           return "Work"
        case .school:         return "School"
        case .personal:       return "Personal"
        case .unknown(let s): return s.capitalized
        }
    }
}

// MARK: - CGFloat helpers

private extension CGFloat {
    static let cfSpacing6: CGFloat = 6
    static let cfSpacing10: CGFloat = 10
    static let cfRadius10: CGFloat = 10
}
