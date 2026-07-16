import SwiftUI

/// A compact editorial section heading with an optional trailing action.
///
/// The title and subtitle wrap without a fixed height. At accessibility text
/// sizes, the action moves below the copy so it remains reachable and keeps a
/// full 44-point target. Leading/trailing alignment adapts automatically in RTL.
public struct CFEditorialSectionHeader: View {
    let title: String
    let subtitle: String?
    let actionTitle: String?
    let action: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static let minimumActionTarget = CGFloat.cfIconLarge

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        actionTitle = nil
        action = nil
    }

    public init(
        title: String,
        subtitle: String? = nil,
        actionTitle: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        Group {
            if Self.usesStackedLayout(for: dynamicTypeSize) {
                stackedHeader
            } else {
                inlineHeader
            }
        }
    }

    static func usesStackedLayout(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var inlineHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: .cfSpacing12) {
            titleBlock
                .layoutPriority(1)

            if hasAction {
                Spacer(minLength: .cfSpacing8)
                actionButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stackedHeader: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            titleBlock

            if hasAction {
                actionButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: .cfSpacing4) {
            Text(title)
                .cfEditorialTextStyle(.sectionTitle)
                .foregroundStyle(Color.cfLabel)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                Text(subtitle)
                    .cfEditorialTextStyle(.metadata)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionTitle, let action {
            Button(actionTitle, action: action)
                .font(.cfMetadata)
                .buttonStyle(.plain)
                .foregroundStyle(Color.cfAccent)
                .frame(
                    minWidth: Self.minimumActionTarget,
                    minHeight: Self.minimumActionTarget
                )
                .contentShape(.rect)
        }
    }

    private var hasAction: Bool {
        actionTitle != nil && action != nil
    }
}

#Preview("Editorial section header") {
    CFEditorialSectionHeader(
        title: "Continue your learning loop",
        subtitle: "Resume where you left off and keep the idea in motion.",
        actionTitle: "See All"
    ) {}
    .padding(.cfSpacing16)
}

#Preview("Editorial section header — AX5") {
    CFEditorialSectionHeader(
        title: "Ideas worth returning to this week",
        subtitle: "A deliberately long subtitle that must wrap without losing the action.",
        actionTitle: "Review"
    ) {}
    .padding(.cfSpacing16)
    .frame(width: 320)
    .environment(\.dynamicTypeSize, .accessibility5)
}
