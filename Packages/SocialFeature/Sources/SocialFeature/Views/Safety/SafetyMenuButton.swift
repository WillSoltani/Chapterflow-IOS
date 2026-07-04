import SwiftUI
import DesignSystem

/// Toolbar button that presents block and report actions for a user profile.
///
/// Drop this into a `NavigationStack` toolbar. It shows a context menu with
/// block/unblock and report items. Blocked-user enforcement in P7.1's public
/// profile variant is signalled via the `isBlocked` binding.
public struct SafetyMenuButton: View {

    let displayName: String?
    let isBlocked: Bool
    let isLoading: Bool
    let onBlockTapped: () -> Void
    let onUnblockTapped: () -> Void
    let onReportTapped: () -> Void

    public init(
        displayName: String?,
        isBlocked: Bool,
        isLoading: Bool = false,
        onBlockTapped: @escaping () -> Void,
        onUnblockTapped: @escaping () -> Void,
        onReportTapped: @escaping () -> Void
    ) {
        self.displayName = displayName
        self.isBlocked = isBlocked
        self.isLoading = isLoading
        self.onBlockTapped = onBlockTapped
        self.onUnblockTapped = onUnblockTapped
        self.onReportTapped = onReportTapped
    }

    public var body: some View {
        Menu {
            if isBlocked {
                Button {
                    onUnblockTapped()
                } label: {
                    Label("Unblock", systemImage: "person.badge.plus")
                }
            } else {
                Button(role: .destructive) {
                    onBlockTapped()
                } label: {
                    Label("Block", systemImage: "hand.raised")
                }
            }

            Divider()

            Button(role: .destructive) {
                onReportTapped()
            } label: {
                Label("Report", systemImage: "flag")
            }
        } label: {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("More actions")
            }
        }
        .disabled(isLoading)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("SafetyMenuButton — unblocked") {
    NavigationStack {
        Color.clear
            .navigationTitle("Preview")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SafetyMenuButton(
                        displayName: "Alice",
                        isBlocked: false,
                        onBlockTapped: {},
                        onUnblockTapped: {},
                        onReportTapped: {}
                    )
                }
            }
    }
}

#Preview("SafetyMenuButton — blocked") {
    NavigationStack {
        Color.clear
            .navigationTitle("Preview")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SafetyMenuButton(
                        displayName: "Alice",
                        isBlocked: true,
                        onBlockTapped: {},
                        onUnblockTapped: {},
                        onReportTapped: {}
                    )
                }
            }
    }
}
#endif
