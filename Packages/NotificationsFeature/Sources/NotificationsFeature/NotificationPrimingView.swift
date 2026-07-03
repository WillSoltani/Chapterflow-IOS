import SwiftUI
import DesignSystem

/// Pre-permission priming sheet shown before the OS notification prompt.
///
/// Present as a sheet at a high-value moment (e.g. after the first chapter).
/// The `NotificationPrimingCoordinator` drives `isPrimingVisible`; bind to that.
public struct NotificationPrimingView: View {
    private let onAccept: () async -> Void
    private let onDismiss: () -> Void

    @State private var isRequesting = false

    public init(
        onAccept: @escaping () async -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onAccept = onAccept
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: .cfSpacing40)
            bellIcon
            Spacer(minLength: .cfSpacing24)
            headlines
            Spacer(minLength: .cfSpacing32)
            benefitRows
            Spacer(minLength: .cfSpacing40)
            actionButtons
            Spacer(minLength: .cfSpacing24)
        }
        .padding(.horizontal, .cfSpacing24)
        .background(Color.cfBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Bell icon

    private var bellIcon: some View {
        ZStack {
            Circle()
                .fill(Color.cfAccent.opacity(0.12))
                .frame(width: 88, height: 88)
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Color.cfAccent)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Headlines

    private var headlines: some View {
        VStack(spacing: .cfSpacing8) {
            Text("Stay on Track")
                .font(.cfTitle2)
                .foregroundStyle(Color.cfLabel)
            Text("Get a gentle nudge when it's time to review, and celebrate milestones as you build your reading habit.")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Benefit rows

    private var benefitRows: some View {
        VStack(alignment: .leading, spacing: .cfSpacing16) {
            PrimingBenefitRow(
                icon: "clock.badge.checkmark.fill",
                title: "Review reminders",
                detail: "Never let a spaced-repetition card go cold"
            )
            PrimingBenefitRow(
                icon: "flame.fill",
                title: "Streak protection",
                detail: "A heads-up before your reading streak is at risk"
            )
            PrimingBenefitRow(
                icon: "sparkles",
                title: "Reading milestones",
                detail: "Celebrate when you hit a new chapter or book"
            )
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: .cfSpacing12) {
            Button {
                isRequesting = true
                Task {
                    await onAccept()
                    isRequesting = false
                }
            } label: {
                Label(
                    isRequesting ? "Enabling…" : "Enable Notifications",
                    systemImage: "bell.fill"
                )
                .font(.cfHeadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, .cfSpacing4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.cfAccent)
            .disabled(isRequesting)
            .accessibilityLabel("Enable notifications")
            .accessibilityHint("Requests permission and shows the system prompt")

            Button("Not Now", role: .cancel, action: onDismiss)
                .font(.cfCallout)
                .foregroundStyle(Color.cfSecondaryLabel)
                .accessibilityLabel("Skip for now")
        }
    }
}

// MARK: - Benefit row helper

private struct PrimingBenefitRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: .cfSpacing16) {
            Image(systemName: icon)
                .font(.system(size: .cfIconSmall, weight: .medium))
                .foregroundStyle(Color.cfAccent)
                .frame(width: .cfIconSmall, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: .cfSpacing2) {
                Text(title)
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfLabel)
                Text(detail)
                    .font(.cfFootnote)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(detail)")
    }
}

// MARK: - Previews

#Preview("Priming — Light") {
    NotificationPrimingView(
        onAccept: {},
        onDismiss: {}
    )
}

#Preview("Priming — Dark") {
    NotificationPrimingView(
        onAccept: {},
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Priming — XXL Text") {
    NotificationPrimingView(
        onAccept: {},
        onDismiss: {}
    )
    .dynamicTypeSize(.accessibility3)
}
