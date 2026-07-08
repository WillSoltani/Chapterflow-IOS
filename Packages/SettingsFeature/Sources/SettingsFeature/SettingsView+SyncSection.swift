import SwiftUI
import DesignSystem
import CoreKit
import SyncEngine

// MARK: - Sync section (P3.5)

extension SettingsView {

    @ViewBuilder
    var syncSection: some View {
        if let status = syncStatus {
            Section("Sync") {
                HStack(spacing: .cfSpacing12) {
                    syncPhaseIcon(status.phase)
                        .foregroundStyle(syncPhaseColor(status.phase))
                        .frame(width: .cfIconSmall, alignment: .center)
                    VStack(alignment: .leading, spacing: .cfSpacing2) {
                        Text(syncPhaseLabel(status))
                            .font(.cfSubheadline)
                            .foregroundStyle(Color.cfLabel)
                        if let date = status.lastSyncedDate {
                            Text("Last synced \(date, style: .relative) ago")
                                .font(.cfCaption)
                                .foregroundStyle(Color.cfTertiaryLabel)
                        }
                    }
                    Spacer()
                    if status.pendingCount > 0 {
                        Text("\(status.pendingCount)")
                            .font(.cfCaption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .padding(.horizontal, .cfSpacing8)
                            .padding(.vertical, .cfSpacing4)
                            .background(Color.cfSecondaryFill, in: Capsule())
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(syncAccessibilityLabel(status))
            }
        }
    }

    func syncPhaseIcon(_ phase: SyncPhase) -> Image {
        switch phase {
        case .idle:
            return Image(systemName: "checkmark.icloud")
        case .syncing:
            return Image(systemName: "arrow.triangle.2.circlepath")
        case .error:
            return Image(systemName: "exclamationmark.icloud")
        }
    }

    func syncPhaseColor(_ phase: SyncPhase) -> Color {
        switch phase {
        case .idle:
            return Color.cfSecondaryLabel
        case .syncing:
            return Color.cfAccent
        case .error:
            return .red.opacity(0.8)
        }
    }

    func syncPhaseLabel(_ status: SyncStatus) -> String {
        switch status.phase {
        case .idle:
            return "All synced"
        case .syncing:
            return "Syncing\u{2026}"
        case .error:
            return status.lastError ?? "Sync failed"
        }
    }

    func syncAccessibilityLabel(_ status: SyncStatus) -> String {
        let base: String
        switch status.phase {
        case .idle:
            base = "Sync is up to date"
        case .syncing:
            base = "Syncing \(status.pendingCount) item\(status.pendingCount == 1 ? "" : "s")"
        case .error:
            base = "Sync failed: \(status.lastError ?? "unknown error")"
        }
        if let date = status.lastSyncedDate {
            return "\(base). Last synced \(RelativeDate.string(for: date))."
        }
        return base
    }
}

// MARK: - Sync section preview

#if DEBUG
#Preview("Sync — idle (last synced)") {
    let status = SyncStatus()
    status.phase = .idle
    status.pendingCount = 0
    status.lastSyncedDate = Date(timeIntervalSinceNow: -120)
    return NavigationStack {
        Form { SettingsView(syncStatus: status).syncSection }
    }
}

#Preview("Sync — syncing") {
    let status = SyncStatus()
    status.phase = .syncing
    status.pendingCount = 4
    return NavigationStack {
        Form { SettingsView(syncStatus: status).syncSection }
    }
}

#Preview("Sync — error") {
    let status = SyncStatus()
    status.phase = .error
    status.pendingCount = 2
    status.lastError = "Network timeout"
    return NavigationStack {
        Form { SettingsView(syncStatus: status).syncSection }
    }
}

#Preview("Sync — dark") {
    let status = SyncStatus()
    status.phase = .syncing
    status.pendingCount = 1
    return NavigationStack {
        Form { SettingsView(syncStatus: status).syncSection }
    }
    .preferredColorScheme(.dark)
}

#Preview("Sync — XXL") {
    let status = SyncStatus()
    status.phase = .idle
    status.pendingCount = 0
    status.lastSyncedDate = Date(timeIntervalSinceNow: -60)
    return NavigationStack {
        Form { SettingsView(syncStatus: status).syncSection }
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
