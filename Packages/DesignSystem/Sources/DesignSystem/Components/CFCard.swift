import SwiftUI

/// A surface-level container card with a material-backed background.
///
/// On iOS/macOS 26+ the background is `.regularMaterial`; when
/// Reduce Transparency is enabled the system replaces the blur with a
/// solid `cfSecondaryBackground` fill automatically, but we also honour
/// the environment flag explicitly for a cleaner fallback.
public struct CFCard<Content: View>: View {
    private let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.cfSpacing16)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: .cfRadius16))
    }

    private var cardBackground: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color.cfSecondaryBackground)
            : AnyShapeStyle(.regularMaterial)
    }
}

// MARK: - Preview

#Preview("CFCard — light") {
    ScrollView {
        VStack(spacing: .cfSpacing16) {
            CFCard {
                VStack(alignment: .leading, spacing: .cfSpacing8) {
                    Text("Card Title")
                        .font(.cfHeadline)
                    Text("Secondary content lives here. Cards defer to content.")
                        .font(.cfBody)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            CFCard {
                HStack(spacing: .cfSpacing12) {
                    Image(systemName: "book.fill")
                        .font(.cfTitle2)
                        .foregroundStyle(Color.cfAccent)
                    VStack(alignment: .leading, spacing: .cfSpacing4) {
                        Text("Atomic Habits")
                            .font(.cfSubheadline)
                        Text("James Clear · 4 chapters left")
                            .font(.cfCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(.cfSpacing16)
    }
    .background(Color.cfGroupedBackground)
}

#Preview("CFCard — dark") {
    CFCard {
        Text("Dark mode card")
            .font(.cfBody)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.cfSpacing16)
    .background(Color.cfGroupedBackground)
    .preferredColorScheme(.dark)
}
