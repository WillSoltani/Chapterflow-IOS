import SwiftUI

/// A centered empty / zero-data state: an SF Symbol, a title, supporting copy,
/// and an optional call-to-action. Calm and content-first.
public struct EmptyState: View {
    private let systemImage: String
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey?
    private let actionTitle: LocalizedStringKey?
    private let action: (() -> Void)?

    public init(
        systemImage: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(DSColor.textTertiary)

            VStack(spacing: DSSpacing.xs) {
                Text(title)
                    .font(DSTypography.title2)
                    .foregroundStyle(DSColor.textPrimary)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(DSTypography.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let actionTitle, let action {
                SecondaryButton(actionTitle, action: action)
                    .fixedSize()
                    .padding(.top, DSSpacing.xs)
            }
        }
        .padding(DSSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

#Preview("EmptyState", traits: .sizeThatFitsLayout) {
    DSPreviewMatrix {
        EmptyState(
            systemImage: "books.vertical",
            title: "No books yet",
            message: "Start a book to begin your reading journey.",
            actionTitle: "Browse Library",
            action: {}
        )
    }
}
