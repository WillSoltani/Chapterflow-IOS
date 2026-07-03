import SwiftUI
import DesignSystem
import CoreKit

/// The reading-partners list screen.
///
/// Shows active partners, pending invites, and expired invites in grouped sections.
/// Toolbar button opens ``InvitePairView``. Tapping a row navigates to
/// ``PairDetailView``. An "Enter Code" button opens ``AcceptInviteView``.
public struct PairsView: View {

    @State private var model: PairsModel
    // Stored separately so we can pass it to InvitePairView without extracting from model.
    private let repository: any SocialRepository

    @State private var showInvite = false
    @State private var showEnterCode = false

    /// When non-empty, show the AcceptInviteView sheet pre-filled with this code.
    /// Used by the deep-link path from ``ProfileView``.
    @Binding private var pendingAcceptCode: String

    public init(
        repository: any SocialRepository,
        pendingAcceptCode: Binding<String> = .constant("")
    ) {
        self.repository = repository
        _model = State(initialValue: PairsModel(repository: repository))
        _pendingAcceptCode = pendingAcceptCode
    }

    public var body: some View {
        content
            .navigationTitle("Reading Partners")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar { toolbarContent }
            .refreshable { await model.load() }
            .task { await model.load() }
            .sheet(isPresented: $showInvite) {
                NavigationStack {
                    InvitePairView(repository: repository)
                }
            }
            .sheet(isPresented: $showEnterCode) {
                NavigationStack {
                    AcceptInviteView(model: model, initialCode: "")
                }
            }
            .sheet(isPresented: showPendingCodeSheet) {
                NavigationStack {
                    AcceptInviteView(model: model, initialCode: pendingAcceptCode)
                        .onDisappear { pendingAcceptCode = "" }
                }
            }
    }

    // MARK: - Pending deep-link sheet binding

    private var showPendingCodeSheet: Binding<Bool> {
        Binding(
            get: { !pendingAcceptCode.isEmpty },
            set: { if !$0 { pendingAcceptCode = "" } }
        )
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle where model.pairs.isEmpty,
             .loading where model.pairs.isEmpty:
            loadingSkeleton
        case .error(let message):
            errorView(message)
        default:
            loadedList
        }
    }

    // MARK: - Loaded list

    private var loadedList: some View {
        List {
            if model.activePairs.isEmpty && model.pendingPairs.isEmpty && model.expiredPairs.isEmpty {
                emptySection
            } else {
                if !model.activePairs.isEmpty {
                    Section("Active") {
                        ForEach(model.activePairs) { pair in
                            pairRow(pair)
                        }
                    }
                }
                if !model.pendingPairs.isEmpty {
                    Section("Pending") {
                        ForEach(model.pendingPairs) { pair in
                            pairRow(pair)
                        }
                    }
                }
                if !model.expiredPairs.isEmpty {
                    Section("Expired") {
                        ForEach(model.expiredPairs) { pair in
                            pairRow(pair)
                        }
                    }
                }
            }

            Section {
                Button {
                    showEnterCode = true
                } label: {
                    Label("Enter Invite Code", systemImage: "keyboard")
                        .foregroundStyle(Color.cfAccent)
                }
                .accessibilityLabel("Enter an invite code manually")
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: - Pair row

    private func pairRow(_ pair: ReadingPair) -> some View {
        NavigationLink {
            PairDetailView(pair: pair, model: model)
        } label: {
            HStack(spacing: .cfSpacing12) {
                AvatarView(
                    avatarUrl: pair.partnerAvatarUrl,
                    avatarEmoji: pair.partnerAvatarEmoji,
                    initials: pair.initials,
                    equippedFrame: nil,
                    size: 44
                )

                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text(pair.partnerDisplayName ?? "Reading Partner")
                        .font(.cfBody)
                        .foregroundStyle(Color.cfLabel)

                    HStack(spacing: .cfSpacing8) {
                        Label("\(pair.partnerCurrentStreak)", systemImage: "flame.fill")
                            .font(.cfCaption)
                            .foregroundStyle(Color.cfSecondaryLabel)

                        statusPill(pair.status)
                    }
                }

                Spacer()
            }
            .padding(.vertical, .cfSpacing4)
        }
        .accessibilityLabel(
            "\(pair.partnerDisplayName ?? "Partner"), streak \(pair.partnerCurrentStreak), \(pair.status.displayLabel)"
        )
    }

    private func statusPill(_ status: PairStatus) -> some View {
        let (label, color): (String, Color) = switch status {
        case .active:       ("Active", .green)
        case .pending:      ("Pending", Color.cfSecondaryLabel)
        case .expired:      ("Expired", .red)
        case .unknown:      ("Unknown", Color.cfSecondaryLabel)
        }
        return Text(label)
            .font(.cfCaption2)
            .padding(.horizontal, .cfSpacing4)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Empty state

    private var emptySection: some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "person.2")
                .font(.system(size: 40))
                .foregroundStyle(Color.cfSecondaryLabel)
            VStack(spacing: .cfSpacing8) {
                Text("No Reading Partners")
                    .font(.cfHeadline)
                    .foregroundStyle(Color.cfLabel)
                Text("Invite a friend to stay accountable and see each other's progress.")
                    .font(.cfBody)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)
            }
            Button("Invite a Partner") {
                showInvite = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.cfAccent)
        }
        .padding(.vertical, .cfSpacing32)
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showInvite = true
            } label: {
                Image(systemName: "person.badge.plus")
            }
            .accessibilityLabel("Invite a reading partner")
        }
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        List {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: .cfSpacing12) {
                    Circle()
                        .fill(Color.cfFill)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: .cfSpacing4) {
                        RoundedRectangle(cornerRadius: .cfRadius4)
                            .fill(Color.cfFill)
                            .frame(width: 120, height: 16)
                        RoundedRectangle(cornerRadius: .cfRadius4)
                            .fill(Color.cfFill)
                            .frame(width: 70, height: 12)
                    }
                    Spacer()
                }
                .padding(.vertical, .cfSpacing4)
                .listRowBackground(Color.cfGroupedBackground)
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: - Error state

    private func errorView(_ message: String) -> some View {
        VStack(spacing: .cfSpacing16) {
            Image(systemName: "person.2.slash")
                .font(.cfLargeTitle)
                .foregroundStyle(Color.cfSecondaryLabel)
            Text(message)
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await model.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.cfSpacing32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("PairsView — with partners") {
    NavigationStack {
        PairsView(repository: FakeSocialRepository.withPairs)
    }
}

#Preview("PairsView — empty") {
    NavigationStack {
        PairsView(repository: FakeSocialRepository.loaded)
    }
}

#Preview("PairsView — dark") {
    NavigationStack {
        PairsView(repository: FakeSocialRepository.withPairs)
    }
    .preferredColorScheme(.dark)
}

#Preview("PairsView — XXL text") {
    NavigationStack {
        PairsView(repository: FakeSocialRepository.withPairs)
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
