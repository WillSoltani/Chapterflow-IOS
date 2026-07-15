import SwiftUI
import DesignSystem
import Persistence

/// A download state drive by the owning `BookDetailModel`.
public enum DownloadButtonState: Sendable, Equatable {
    case notDownloaded
    case inProgress(fraction: Double)
    case downloaded
    case failed(String)
}

/// A button that shows the offline-availability status of a book and triggers
/// or cancels downloads.
///
/// - `notDownloaded`: shows an arrow-down icon.
/// - `inProgress`: shows a circular progress ring with the fraction completed.
/// - `downloaded`: shows a filled checkmark badge.
/// - `failed`: shows a warning icon.
struct BookDownloadButton: View {
    let state: DownloadButtonState
    var canStartDownload = true
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        switch state {
        case .notDownloaded:
            Button(action: onDownload) {
                Label("Download for offline use", systemImage: "arrow.down.circle")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfAccent)
            }
            .buttonStyle(.plain)
            .disabled(!canStartDownload)
            .opacity(canStartDownload ? 1 : 0.55)
            .accessibilityLabel("Download book for offline reading")

        case .inProgress(let fraction):
            HStack(spacing: .cfSpacing8) {
                DownloadProgressRing(fraction: fraction)
                    .frame(width: 22, height: 22)
                Text("Downloading \(Int(fraction * 100))%")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel download")
            }

        case .downloaded:
            HStack(spacing: .cfSpacing8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.cfAccent)
                Text("Available offline")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfSecondaryLabel)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .font(.cfCaption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove download")
            }

        case .failed:
            Button(action: onDownload) {
                HStack(spacing: .cfSpacing8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.orange)
                    Text("Download failed — tap to retry")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canStartDownload)
            .opacity(canStartDownload ? 1 : 0.55)
            .accessibilityLabel("Download failed. Tap to retry.")
        }
    }
}

/// A thin circular progress ring used while a download is in progress.
struct DownloadProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.cfSecondaryFill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(Color.cfAccent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: fraction)
        }
    }
}

// MARK: - Previews

#Preview("Download States") {
    VStack(spacing: .cfSpacing24) {
        BookDownloadButton(
            state: .notDownloaded,
            onDownload: {}, onCancel: {}, onDelete: {}
        )
        BookDownloadButton(
            state: .inProgress(fraction: 0.45),
            onDownload: {}, onCancel: {}, onDelete: {}
        )
        BookDownloadButton(
            state: .downloaded,
            onDownload: {}, onCancel: {}, onDelete: {}
        )
        BookDownloadButton(
            state: .failed("Network error"),
            onDownload: {}, onCancel: {}, onDelete: {}
        )
    }
    .padding(.cfSpacing16)
}
