import SwiftUI
import DesignSystem

/// Sheet for reporting a user or content.
///
/// Presents a reason picker, an optional free-text field, and a note explaining
/// that all reports are reviewed by the ChapterFlow team (Apple Guideline 1.2).
public struct ReportView: View {

    let displayName: String?
    let onSubmit: (ReportReason, String) async -> Void
    let onCancel: () -> Void

    @State private var selectedReason: ReportReason = .harassment
    @State private var details: String = ""
    @State private var isSubmitting: Bool = false
    @Environment(\.dismiss) private var dismiss

    public init(
        displayName: String?,
        onSubmit: @escaping (ReportReason, String) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.displayName = displayName
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            Form {
                reasonSection
                detailsSection
                conductSection
            }
            .navigationTitle("Report User")
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
                ToolbarItem(placement: .confirmationAction) {
                    submitButton
                }
            }
        }
    }

    // MARK: - Sections

    private var reasonSection: some View {
        Section("Reason") {
            ForEach(ReportReason.allDisplayCases, id: \.rawValue) { reason in
                Button {
                    selectedReason = reason
                } label: {
                    HStack {
                        Text(reason.displayLabel)
                            .foregroundStyle(Color.cfLabel)
                        Spacer()
                        if selectedReason == reason {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.cfAccent)
                        }
                    }
                }
            }
        }
    }

    private var detailsSection: some View {
        Section("Additional details (optional)") {
            TextField(
                "Describe what happened…",
                text: $details,
                axis: .vertical
            )
            .lineLimit(4, reservesSpace: true)
            .accessibilityLabel("Additional details about your report")
        }
    }

    private var conductSection: some View {
        Section {
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                Label("Reports are reviewed", systemImage: "shield.checkered")
                    .font(.cfSubheadline.weight(.medium))
                    .foregroundStyle(Color.cfLabel)
                Text(
                    "Every report is reviewed by the ChapterFlow team. " +
                    "We take user safety seriously and act on all valid reports " +
                    "in accordance with our Code of Conduct. Misuse of the reporting " +
                    "system may result in account action."
                )
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
            }
            .padding(.vertical, .cfSpacing4)
        }
    }

    private var submitButton: some View {
        Button("Submit") {
            isSubmitting = true
            Task {
                await onSubmit(selectedReason, details)
                isSubmitting = false
            }
        }
        .disabled(isSubmitting)
        .fontWeight(.semibold)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ReportView — light") {
    ReportView(
        displayName: "Reading Partner",
        onSubmit: { _, _ in },
        onCancel: {}
    )
}

#Preview("ReportView — dark") {
    ReportView(
        displayName: "Reading Partner",
        onSubmit: { _, _ in },
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("ReportView — XXL text") {
    ReportView(
        displayName: "Reading Partner",
        onSubmit: { _, _ in },
        onCancel: {}
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
