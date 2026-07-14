import DesignSystem
import SwiftUI

struct BootstrapPreparingView: View {
    var body: some View {
        ZStack {
            Color.cfGroupedBackground.ignoresSafeArea()

            VStack(spacing: .cfSpacing20) {
                Image(systemName: "book.closed")
                    .font(.largeTitle)
                    .foregroundStyle(Color.cfAccent)
                    .accessibilityHidden(true)

                Text("Preparing ChapterFlow")
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfLabel)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel("Preparing your library")
            }
            .padding(.cfSpacing24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("bootstrap-preparing")
    }
}

struct BootstrapFailureView: View {
    enum Kind {
        case storage
        case session
    }

    let kind: Kind
    let supportCode: String
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.cfGroupedBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: .cfSpacing24) {
                    Image(systemName: iconName)
                        .font(.largeTitle)
                        .foregroundStyle(Color.cfAccent)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: .cfSpacing12) {
                        Text(heading)
                            .font(.cfTitle1)
                            .foregroundStyle(Color.cfLabel)
                            .accessibilityAddTraits(.isHeader)

                        Text(explanation)
                            .font(.cfBody)
                            .foregroundStyle(Color.cfSecondaryLabel)

                        Text("No local data was reset or deleted.")
                            .font(.cfBody)
                            .foregroundStyle(Color.cfSecondaryLabel)
                    }

                    Button("Try Again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityHint("Retries ChapterFlow startup")
                        .accessibilityIdentifier("bootstrap-retry")

                    Text("Support code: \(supportCode)")
                        .font(.cfFootnote.monospaced())
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("bootstrap-support-code")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, .cfSpacing20)
                .padding(.vertical, .cfSpacing32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(rootIdentifier)
    }

    private var iconName: String {
        switch kind {
        case .storage:
            "externaldrive.badge.exclamationmark"
        case .session:
            "person.crop.circle.badge.exclamationmark"
        }
    }

    private var heading: String {
        switch kind {
        case .storage:
            "ChapterFlow Can't Open Your Library"
        case .session:
            "ChapterFlow Can't Start"
        }
    }

    private var explanation: String {
        switch kind {
        case .storage:
            "Storage required for your books, progress, notes, and downloads is unavailable right now."
        case .session:
            "Required account services could not be prepared, so account-backed features have not started."
        }
    }

    private var rootIdentifier: String {
        switch kind {
        case .storage:
            "bootstrap-storage-unavailable"
        case .session:
            "bootstrap-session-configuration-failed"
        }
    }
}
