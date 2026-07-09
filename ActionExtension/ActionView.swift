import SwiftUI

// MARK: - ActionView

/// The SwiftUI content of the Action Extension ("Ask ChapterFlow about this").
///
/// Shows the selected text, a brief explanation, and an "Ask ChapterFlow" button
/// that saves the query to the App Group outbox and opens the main app.
/// When not signed in, replaces the action button with an "Open ChapterFlow" prompt.
struct ActionView: View {

    // MARK: - Input

    let selectedText: String?
    let sourceTitle: String?
    let onAsk: () -> Void
    let onCancel: () -> Void
    let onOpenApp: () -> Void

    // MARK: - State

    @State private var isLoading: Bool = false

    // MARK: - Auth

    private var signedIn: Bool { isSignedIn() }

    // MARK: - Derived

    private var hasContent: Bool {
        !(selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
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
            .navigationTitle("Ask ChapterFlow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    // MARK: - Signed-in body

    @ViewBuilder
    private var signedInBody: some View {
        Form {
            Section {
                selectedTextPreview
            } header: {
                Text("Selected text")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ChapterFlow will save this question and you can ask it within the app when you're reading a related book.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(action: {
                        isLoading = true
                        onAsk()
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "brain.head.profile")
                            }
                            Text("Ask ChapterFlow")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasContent || isLoading)
                    .opacity(hasContent ? 1 : 0.5)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Selected text preview

    @ViewBuilder
    private var selectedTextPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = sourceTitle, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let text = selectedText, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .lineLimit(8)
            } else {
                Text("No text selected")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .italic()
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

                Text("Open ChapterFlow and sign in to use Ask ChapterFlow.")
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
}

// MARK: - Previews

#Preview("With text — signed in") {
    ActionView(
        selectedText: "Atomic habits are the compound interest of self-improvement.",
        sourceTitle: "James Clear — Atomic Habits",
        onAsk: {},
        onCancel: {},
        onOpenApp: {}
    )
}

#Preview("No text") {
    ActionView(
        selectedText: nil,
        sourceTitle: nil,
        onAsk: {},
        onCancel: {},
        onOpenApp: {}
    )
}

#Preview("Signed out") {
    _ActionSignedOutPreview()
}

private struct _ActionSignedOutPreview: View {
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
                    Text("Open ChapterFlow and sign in to use Ask ChapterFlow.")
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
            .navigationTitle("Ask ChapterFlow")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
