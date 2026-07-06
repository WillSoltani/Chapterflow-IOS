import SwiftUI

/// Empty state shown when a user is offline and content hasn't been downloaded.
///
/// Presents a clear explanation and a CTA button that routes the user to the
/// book-detail download button (from P3.2). Pass `nil` for `onDownload` when
/// there is no download path available.
///
/// ```swift
/// CacheMissView(
///     title: "Chapter not available offline",
///     onDownload: { dismiss(); navigateToBookDetail() }
/// )
/// ```
public struct CacheMissView: View {

    public let title: String
    public let onDownload: (() -> Void)?

    public init(
        title: String = "Not available offline",
        onDownload: (() -> Void)? = nil
    ) {
        self.title = title
        self.onDownload = onDownload
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "arrow.down.circle.dotted")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.cfSecondaryLabel)
        } description: {
            Text("Download this book to read, take quizzes, and review it offline.")
                .font(.cfCallout)
                .foregroundStyle(Color.cfTertiaryLabel)
        } actions: {
            if let onDownload {
                Button("Download Book", action: onDownload)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cfAccent)
                    .accessibilityLabel("Download book for offline access")
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Cache miss — with download CTA") {
    CacheMissView(onDownload: {})
}

#Preview("Cache miss — without CTA") {
    CacheMissView()
}

#Preview("Cache miss — dark") {
    CacheMissView(onDownload: {})
        .preferredColorScheme(.dark)
}

#Preview("Cache miss — XXL") {
    CacheMissView(onDownload: {})
        .dynamicTypeSize(.accessibility3)
}
#endif
