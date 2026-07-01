import SwiftUI

/// A preview helper that renders the same content three ways side-by-side —
/// **light**, **dark**, and **light at the largest accessibility Dynamic Type
/// size** — so every component `#Preview` covers the required appearance and
/// accessibility matrix in one canvas.
///
/// This type is compiled into the module (not `#if DEBUG`-only) so it is
/// available to previews in dependent packages too.
public struct DSPreviewMatrix<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            cell("Light", scheme: .light)
            cell("Dark", scheme: .dark)
            cell("XXL", scheme: .light, size: .accessibility3)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func cell(_ label: String, scheme: ColorScheme, size: DynamicTypeSize = .large) -> some View {
        VStack(spacing: DSSpacing.sm) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity)
                .dynamicTypeSize(size)
        }
        .padding(DSSpacing.sm)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DSColor.background)
        .environment(\.colorScheme, scheme)
    }
}
