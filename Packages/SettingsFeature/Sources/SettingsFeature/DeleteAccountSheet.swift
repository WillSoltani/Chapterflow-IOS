import SwiftUI
import DesignSystem

/// Presents the permanent-deletion confirmation UI.
///
/// This is a separate sheet so the destructive action requires the user to
/// actively type a confirmation phrase — reducing accidental taps.
@MainActor
struct DeleteAccountSheet: View {
    @Binding var isPresented: Bool
    let isLoading: Bool
    let onConfirm: () async -> Void

    @State private var confirmText = ""
    private let requiredPhrase = "delete my account"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    consequencesView
                } header: {
                    Text("What happens when you delete")
                        .accessibilityAddTraits(.isHeader)
                }

                Section {
                    VStack(alignment: .leading, spacing: .cfSpacing8) {
                        Text("Type \"\(requiredPhrase)\" to confirm")
                            .font(.cfFootnote)
                            .foregroundStyle(.secondary)
                        TextField("Confirmation phrase", text: $confirmText)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .accessibilityLabel("Type delete my account to confirm")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await onConfirm() }
                    } label: {
                        if isLoading {
                            HStack {
                                ProgressView().tint(.red)
                                Text("Deleting…")
                            }
                        } else {
                            Text("Permanently Delete Account")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(confirmText.lowercased() != requiredPhrase || isLoading)
                    .accessibilityLabel("Permanently delete account")
                    .accessibilityHint("Disabled until you type the confirmation phrase")
                }
            }
            .navigationTitle("Delete Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .disabled(isLoading)
                }
            }
        }
    }

    private var consequencesView: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            consequenceRow(
                icon: "trash",
                title: "All data deleted",
                detail: "Your books, progress, notes, and streaks are permanently removed."
            )
            consequenceRow(
                icon: "apple.logo",
                title: "Apple Sign-In revoked",
                detail: "If you signed in with Apple, the connection is revoked server-side."
            )
            consequenceRow(
                icon: "creditcard",
                title: "Subscription not cancelled",
                detail: "Cancel your subscription in the App Store before deleting."
            )
            consequenceRow(
                icon: "clock.arrow.circlepath",
                title: "Cannot be undone",
                detail: "Deletion is immediate and permanent. There is no recovery."
            )
        }
        .padding(.vertical, .cfSpacing4)
    }

    private func consequenceRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: .cfSpacing12) {
            Image(systemName: icon)
                .font(.cfBody)
                .foregroundStyle(Color.red)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: .cfSpacing4) {
                Text(title)
                    .font(.cfSubheadline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.cfFootnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Delete Sheet") {
    DeleteAccountSheet(
        isPresented: .constant(true),
        isLoading: false,
        onConfirm: {}
    )
}

#Preview("Delete Sheet — Loading") {
    DeleteAccountSheet(
        isPresented: .constant(true),
        isLoading: true,
        onConfirm: {}
    )
}
#endif
