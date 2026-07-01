import SwiftUI

/// A design-system bottom sheet container. Wraps content with a consistent
/// title, optional close affordance, token padding and a grabber, on the
/// standard elevated surface.
///
/// Present it with ``SwiftUI/View/bottomSheet(isPresented:detents:title:content:)``,
/// which applies the native sheet chrome (detents, drag indicator, rounded
/// corners) styled to match the app.
public struct BottomSheetContainer<Content: View>: View {
    private let title: LocalizedStringKey?
    private let content: Content

    public init(title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            if let title {
                Text(title)
                    .font(DSTypography.title2)
                    .foregroundStyle(DSColor.textPrimary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.lg)
    }
}

public extension View {
    /// Presents a design-system bottom sheet.
    func bottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        detents: Set<PresentationDetent> = [.medium, .large],
        title: LocalizedStringKey? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented) {
            BottomSheetContainer(title: title, content: content)
                .presentationDetents(detents)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(DSRadius.xl)
                .presentationBackground(DSColor.surfaceElevated)
        }
    }
}

#Preview("BottomSheet", traits: .sizeThatFitsLayout) {
    DSPreviewMatrix {
        BottomSheetContainer(title: "Reading Settings") {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("Adjust depth, tone and text size.")
                    .font(DSTypography.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
                PrimaryButton("Done") {}
            }
        }
        .background(DSColor.surfaceElevated)
    }
}
