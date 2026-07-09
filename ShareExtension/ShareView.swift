import SwiftUI

// MARK: - ShareView

/// The SwiftUI content of the Share Extension.
///
/// Shows a preview of the shared item, an optional note field, and Save/Cancel
/// actions. When the user is not signed in the save button is replaced with an
/// "Open ChapterFlow" prompt so the save is never silently dropped.
struct ShareView: View {

    // MARK: - State

    @State private var noteText: String = ""
    @State private var isSaving: Bool = false
    @State private var savedSuccessfully: Bool = false

    // MARK: - Input

    let sharedText: String?
    let sharedURL: String?
    let sourceTitle: String?
    let onSave: () -> Void
    let onCancel: () -> Void
    let onOpenApp: () -> Void

    // MARK: - Auth

    private var signedIn: Bool { isSignedIn() }

    // MARK: - Derived

    private var primaryContent: String {
        sharedText ?? sharedURL ?? ""
    }

    private var contentKind: ExtensionItem.Kind {
        if sharedURL != nil { return .link }
        return .text
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if signedIn {
                    signedInBody
                } else {
                    signedOutBody
                }
            }
            .navigationTitle("Save to ChapterFlow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                if signedIn {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { performSave() }
                            .fontWeight(.semibold)
                            .disabled(primaryContent.isEmpty || isSaving)
                    }
                }
            }
        }
    }

    // MARK: - Signed-in body

    @ViewBuilder
    private var signedInBody: some View {
        Form {
            // Preview of the shared item
            Section {
                contentPreviewRow
            }

            // Optional note field
            Section("Add a note (optional)") {
                TextField("Your thoughts…", text: $noteText, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityLabel("Note")
            }
        }
        .overlay {
            if savedSuccessfully {
                savedOverlay
            }
        }
    }

    // MARK: - Signed-out body

    @ViewBuilder
    private var signedOutBody: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Sign in Required")
                    .font(.headline)

                Text("Open ChapterFlow and sign in to save items to your Notebook.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button(action: onOpenApp) {
                Label("Open ChapterFlow", systemImage: "arrow.up.right.app")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content preview

    @ViewBuilder
    private var contentPreviewRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: contentKind == .link ? "link" : "text.quote")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                if let title = sourceTitle, !title.isEmpty {
                    Text(title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(primaryContent)
                    .font(.body)
                    .lineLimit(5)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Saved overlay

    @ViewBuilder
    private var savedOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Saved to Notebook")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    // MARK: - Save action

    private func performSave() {
        guard !primaryContent.isEmpty else { return }
        isSaving = true

        let item = ExtensionItem(
            id: UUID().uuidString,
            kind: contentKind,
            text: primaryContent,
            userNote: noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : noteText,
            sourceTitle: sourceTitle,
            sourceURL: sharedURL,
            createdAt: Date()
        )
        writeToOutbox(item)

        withAnimation {
            savedSuccessfully = true
        }
        // Brief delay so the user sees the confirmation before dismissal.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onSave()
        }
    }
}

// MARK: - Preview

#Preview("Signed-in — text") {
    ShareView(
        sharedText: "The key to great habits is starting with an identity, not a goal.",
        sharedURL: nil,
        sourceTitle: "Safari",
        onSave: {},
        onCancel: {},
        onOpenApp: {}
    )
}

#Preview("Signed-in — URL") {
    ShareView(
        sharedText: nil,
        sharedURL: "https://example.com/article",
        sourceTitle: "Example Article — Medium",
        onSave: {},
        onCancel: {},
        onOpenApp: {}
    )
}

#Preview("Signed-out") {
    // Simulate signed-out state by showing the alternate path.
    // In production this is driven by the real Keychain check.
    _SignedOutPreviewWrapper()
}

/// Helper: wraps ShareView and forces the signed-out UI for previews.
private struct _SignedOutPreviewWrapper: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    Text("Sign in Required")
                        .font(.headline)
                    Text("Open ChapterFlow and sign in to save items to your Notebook.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Button {} label: {
                    Label("Open ChapterFlow", systemImage: "arrow.up.right.app")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .navigationTitle("Save to ChapterFlow")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
