import SwiftUI
import DesignSystem

/// Confirmation sheet shown before blocking a user.
///
/// Explains the consequences of blocking so the action is explicit and
/// informed (Apple Guideline 1.2).
public struct BlockConfirmationView: View {

    let displayName: String?
    let isLoading: Bool
    let onBlock: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    public init(
        displayName: String?,
        isLoading: Bool = false,
        onBlock: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.displayName = displayName
        self.isLoading = isLoading
        self.onBlock = onBlock
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: .cfSpacing24) {
                iconView
                textContent
                Spacer()
                actionButtons
            }
            .padding(.horizontal, .cfSpacing24)
            .padding(.vertical, .cfSpacing32)
            .navigationTitle("Block User")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Sub-views

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.1))
                .frame(width: 72, height: 72)
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 30))
                .foregroundStyle(.red)
        }
    }

    private var textContent: some View {
        VStack(spacing: .cfSpacing12) {
            Text("Block \(displayName ?? "this user")?")
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.center)

            Text("They won't be able to pair with you, send nudges, or view your profile. You can unblock them at any time from your blocked users list.")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: .cfSpacing12) {
            Button(role: .destructive) {
                onBlock()
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Block")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, .cfSpacing12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isLoading)
            .accessibilityLabel("Confirm block")

            Button("Cancel", role: .cancel) {
                onCancel()
                dismiss()
            }
            .foregroundStyle(Color.cfSecondaryLabel)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("BlockConfirmationView — light") {
    BlockConfirmationView(
        displayName: "Reading Partner",
        onBlock: {},
        onCancel: {}
    )
}

#Preview("BlockConfirmationView — dark") {
    BlockConfirmationView(
        displayName: "Reading Partner",
        onBlock: {},
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("BlockConfirmationView — loading") {
    BlockConfirmationView(
        displayName: "Reading Partner",
        isLoading: true,
        onBlock: {},
        onCancel: {}
    )
}

#Preview("BlockConfirmationView — XXL text") {
    BlockConfirmationView(
        displayName: "Reading Partner",
        onBlock: {},
        onCancel: {}
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
