import SwiftUI
import DesignSystem

// MARK: - SyncStatusIndicatorView

/// A subtle status indicator that shows sync state in a toolbar or nav bar.
///
/// Designed to be unobtrusive: visible only when something is happening
/// (syncing or error), and completely hidden when the outbox is empty.
///
/// ```swift
/// .toolbar {
///     ToolbarItem(placement: .navigationBarTrailing) {
///         SyncStatusIndicatorView(status: engine.status)
///     }
/// }
/// ```
public struct SyncStatusIndicatorView: View {
    @State var status: SyncStatus

    public init(status: SyncStatus) {
        self.status = status
    }

    public var body: some View {
        Group {
            switch status.phase {
            case .idle:
                EmptyView()
            case .syncing:
                SyncingView(pendingCount: status.pendingCount)
            case .error:
                ErrorDotView(pendingCount: status.pendingCount)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: status.phase)
    }
}

// MARK: - SyncingView

private struct SyncingView: View {
    let pendingCount: Int

    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.cfSecondaryLabel)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    .linear(duration: 1.0).repeatForever(autoreverses: false),
                    value: isAnimating
                )
            if pendingCount > 0 {
                Text("\(pendingCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
        }
        .accessibilityLabel("Syncing \(pendingCount) item\(pendingCount == 1 ? "" : "s")")
        .onAppear { isAnimating = true }
    }
}

// MARK: - ErrorDotView

private struct ErrorDotView: View {
    let pendingCount: Int

    var body: some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: "exclamationmark.circle")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.red.opacity(0.8))
            if pendingCount > 0 {
                Text("\(pendingCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
        }
        .accessibilityLabel("\(pendingCount) item\(pendingCount == 1 ? "" : "s") failed to sync")
    }
}

// MARK: - Previews

#Preview("Idle") {
    let s = SyncStatus()
    return SyncStatusIndicatorView(status: s)
        .padding()
}

#Preview("Syncing (3 pending)") {
    let s = SyncStatus()
    s.phase = .syncing
    s.pendingCount = 3
    return SyncStatusIndicatorView(status: s)
        .padding()
}

#Preview("Error (2 failed)") {
    let s = SyncStatus()
    s.phase = .error
    s.pendingCount = 2
    s.lastError = "Network timeout"
    return SyncStatusIndicatorView(status: s)
        .padding()
}

#Preview("Dark Mode — Syncing") {
    let s = SyncStatus()
    s.phase = .syncing
    s.pendingCount = 1
    return SyncStatusIndicatorView(status: s)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility XXL") {
    let s = SyncStatus()
    s.phase = .error
    s.pendingCount = 5
    return SyncStatusIndicatorView(status: s)
        .padding()
        .environment(\.dynamicTypeSize, .accessibility5)
}
