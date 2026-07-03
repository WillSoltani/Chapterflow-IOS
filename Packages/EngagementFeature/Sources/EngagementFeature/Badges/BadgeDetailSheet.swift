import SwiftUI
import DesignSystem
import Models

// MARK: - BadgeDetailSheet

/// A sheet showing full detail for a tapped badge.
///
/// - Earned badge: icon, name, description, earned date.
/// - Locked (visible): icon, name, "how to earn" description, progress if available.
/// - Locked (hidden track): mysterious — no criteria revealed until earned.
struct BadgeDetailSheet: View {

    let badge: BadgeItem
    let onDismiss: () -> Void

    private var track: AchievementTrack? {
        AchievementTrack.from(category: badge.category)
    }

    private var isHiddenLocked: Bool {
        track == .hidden && !badge.isEarned
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: .cfSpacing24) {
                    iconSection
                    infoSection
                    if !badge.isEarned { progressSection }
                }
                .padding(.cfSpacing24)
            }
            .background(Color.cfGroupedBackground.ignoresSafeArea())
            .navigationTitle(isHiddenLocked ? "Hidden Achievement" : badge.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }

    // MARK: - Icon

    private var iconSection: some View {
        VStack(spacing: .cfSpacing12) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 96, height: 96)

                if isHiddenLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else if let emoji = badge.icon, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 48))
                } else {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(trackColor)
                }
            }

            if badge.isEarned {
                Label("Earned", systemImage: "checkmark.seal.fill")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfAccent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, .cfSpacing8)
    }

    // MARK: - Info rows

    @ViewBuilder
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing16) {
            if !isHiddenLocked {
                // Track chip
                if let track {
                    Label(track.displayName, systemImage: track.systemImage)
                        .font(.cfCaption)
                        .foregroundStyle(trackColor)
                        .padding(.horizontal, .cfSpacing8)
                        .padding(.vertical, .cfSpacing4)
                        .background(trackColor.opacity(0.10), in: Capsule())
                }

                // Description
                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text(badge.isEarned ? "About" : "How to earn")
                        .font(.cfCaption)
                        .foregroundStyle(.secondary)
                    Text(badge.description)
                        .font(.cfBody)
                        .foregroundStyle(.primary)
                }

                // Earned date
                if badge.isEarned, let dateString = badge.earnedAt {
                    VStack(alignment: .leading, spacing: .cfSpacing4) {
                        Text("Earned on")
                            .font(.cfCaption)
                            .foregroundStyle(.secondary)
                        Text(formattedDate(dateString))
                            .font(.cfBody)
                            .foregroundStyle(.primary)
                    }
                }
            } else {
                // Hidden & locked — reveal nothing
                VStack(spacing: .cfSpacing12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("This achievement is a secret.")
                        .font(.cfSubheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    Text("Earn it to reveal what it is.")
                        .font(.cfBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        if !isHiddenLocked, let fraction = badge.progressFraction,
           let progress = badge.progress, let target = badge.target {
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                HStack {
                    Text("Progress")
                        .font(.cfCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(progress) / \(target)")
                        .font(.cfCaption)
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.cfSecondaryFill)
                            .frame(height: 8)
                        Capsule()
                            .fill(Color.cfAccent)
                            .frame(width: geo.size.width * fraction, height: 8)
                            .animation(.easeOut(duration: 0.5), value: fraction)
                    }
                }
                .frame(height: 8)
            }
            .padding(.cfSpacing16)
            .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius12))
        }
    }

    // MARK: - Helpers

    private var trackColor: Color {
        switch track {
        case .mastery:     return .cfAccent
        case .consistency: return .orange
        case .exploration: return .green
        case .hidden:      return .purple
        case .none:        return .cfSecondaryLabel
        }
    }

    private var iconBackground: Color {
        badge.isEarned ? trackColor.opacity(0.12) : Color.cfSecondaryFill
    }

    private func formattedDate(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fmt.date(from: iso) {
            return date.formatted(date: .long, time: .omitted)
        }
        fmt.formatOptions = [.withInternetDateTime]
        if let date = fmt.date(from: iso) {
            return date.formatted(date: .long, time: .omitted)
        }
        return iso
    }
}
