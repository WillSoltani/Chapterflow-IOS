import SwiftUI

/// A system-native empty state using `ContentUnavailableView`.
///
/// The optional action button uses `.glass` style on iOS/macOS 26+ and
/// `.bordered` on older OS versions for a graceful fallback.
public struct CFEmptyState: View {
    private let systemImage: String
    private let title: String
    private let description: String?
    private let actionLabel: String?
    private let action: (() -> Void)?

    public init(
        systemImage: String,
        title: String,
        description: String? = nil,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.description = description
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let description {
                Text(description)
            }
        } actions: {
            if let action, let label = actionLabel {
                Group {
                    if #available(iOS 26, macOS 26, *) {
                        Button(label, action: action)
                            .buttonStyle(.glass)
                    } else {
                        Button(label, action: action)
                            .buttonStyle(.bordered)
                            .tint(.cfAccent)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("CFEmptyState — with action") {
    CFEmptyState(
        systemImage: "books.vertical",
        title: "No Books Yet",
        description: "Add books to your library to start learning.",
        actionLabel: "Browse Library"
    ) {}
}

#Preview("CFEmptyState — no action") {
    CFEmptyState(
        systemImage: "star.slash",
        title: "No Reviews Due",
        description: "Great work — you're all caught up!"
    )
}
