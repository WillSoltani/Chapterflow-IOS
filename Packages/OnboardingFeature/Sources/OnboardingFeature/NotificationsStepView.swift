import SwiftUI
import DesignSystem

// MARK: - Notifications step

struct NotificationsStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: .cfSpacing64)

            heroSection

            Spacer()

            benefitsList

            Spacer()

            actions
                .padding(.horizontal, .cfSpacing24)
                .padding(.bottom, .cfSpacing40)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Sections

    private var heroSection: some View {
        VStack(spacing: .cfSpacing24) {
            ZStack {
                Circle()
                    .fill(Color.cfAccent.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.cfAccent)
            }
            .accessibilityHidden(true)

            VStack(spacing: .cfSpacing12) {
                Text("Stay on track")
                    .font(.cfLargeTitle)
                    .accessibilityAddTraits(.isHeader)

                Text("A daily nudge helps you build a reading habit\nthat actually sticks.")
                    .font(.cfBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, .cfSpacing32)
    }

    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: .cfSpacing16) {
            NotificationBenefit(
                icon: "flame",
                title: "Protect your streak",
                subtitle: "Never miss a day — we'll remind you before midnight."
            )
            NotificationBenefit(
                icon: "calendar.badge.checkmark",
                title: "Flexible timing",
                subtitle: "We remind you at the time you chose — no spam."
            )
            NotificationBenefit(
                icon: "lock.slash",
                title: "Always your choice",
                subtitle: "Change or disable notifications any time in Settings."
            )
        }
        .padding(.horizontal, .cfSpacing32)
    }

    private var actions: some View {
        VStack(spacing: .cfSpacing12) {
            Button {
                Task { await model.requestNotificationsAndAdvance() }
            } label: {
                Label("Enable Reminders", systemImage: "bell.badge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .accessibilityLabel("Enable Reminders — allow ChapterFlow to send daily notifications")

            Button {
                Task { await model.skip() }
            } label: {
                Text("Maybe Later")
                    .font(.cfFootnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Maybe Later — skip notifications and finish setup")
        }
    }
}

// MARK: - Benefit row

private struct NotificationBenefit: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: .cfSpacing16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.cfAccent)
                .frame(width: .cfIconMedium)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: .cfSpacing4) {
                Text(title)
                    .font(.cfHeadline)
                Text(subtitle)
                    .font(.cfFootnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Previews

#Preview("Notifications — light") {
    OnboardingFlowPreviewContainer(step: .notifications)
}

#Preview("Notifications — dark") {
    OnboardingFlowPreviewContainer(step: .notifications)
        .preferredColorScheme(.dark)
}

#Preview("Notifications — XXL type") {
    OnboardingFlowPreviewContainer(step: .notifications)
        .dynamicTypeSize(.accessibility3)
}
