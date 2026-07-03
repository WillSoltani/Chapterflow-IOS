import SwiftUI
import DesignSystem
import Models

// MARK: - CelebrationCardView

/// The content card shown for a single ``CelebrationEvent``.
///
/// Caller is responsible for the overlay backdrop + confetti. This view only
/// renders the icon, headline, subheadline, and dismiss hint.
struct CelebrationCardView: View {
    let event: CelebrationEvent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: .cfSpacing20) {
            iconView
            textBlock
            dismissHint
        }
        .padding(.cfSpacing32)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: .cfRadius24))
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 8)
        .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.88))
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                    appeared = true
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Subviews

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(iconTint.opacity(0.12))
                .frame(width: 80, height: 80)
            Image(systemName: event.systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(iconTint)
                .modifier(BounceSymbolModifier())
        }
    }

    private var textBlock: some View {
        VStack(spacing: .cfSpacing8) {
            Text(event.headline)
                .font(.cfTitle2)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            if let sub = event.subheadline {
                Text(sub)
                    .font(.cfBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
        }
    }

    private var dismissHint: some View {
        Text("Tap anywhere to continue")
            .font(.cfCaption)
            .foregroundStyle(.tertiary)
            .padding(.top, .cfSpacing4)
    }

    // MARK: Helpers

    private var cardBackground: some ShapeStyle {
        AnyShapeStyle(.regularMaterial)
    }

    private var iconTint: Color {
        switch event {
        case .loopComplete:     return .cfAccent
        case .flowPointsGained: return .yellow
        case .streakIncrement:  return .orange
        case .streakMilestone:  return .red
        case .tierUp:           return .purple
        case .badgeEarned:      return Color(red: 0.85, green: 0.65, blue: 0.15)
        case .insightSpark:     return Color(red: 0.20, green: 0.75, blue: 0.55)
        case .journeyComplete:  return Color(red: 0.18, green: 0.72, blue: 0.42)
        }
    }

    private var accessibilityLabel: String {
        var parts = [event.headline]
        if let sub = event.subheadline { parts.append(sub) }
        parts.append("Tap anywhere to continue")
        return parts.joined(separator: ". ")
    }
}

// MARK: - BounceSymbolModifier

/// Wraps `.symbolEffect(.bounce)` behind an availability gate so the package
/// compiles on macOS 14 (the declared minimum) while getting the animation on
/// iOS 18 / macOS 15 at runtime.
private struct BounceSymbolModifier: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content.symbolEffect(.bounce, options: .nonRepeating)
#else
        if #available(macOS 15.0, *) {
            content.symbolEffect(.bounce, options: .nonRepeating)
        } else {
            content
        }
#endif
    }
}

// MARK: - Preview

#Preview("CelebrationCard — loopComplete") {
    ZStack {
        Color.cfGroupedBackground.ignoresSafeArea()
        CelebrationCardView(event: .loopComplete(chapterTitle: "The Compound Effect"))
            .padding(.cfSpacing32)
    }
}

#Preview("CelebrationCard — dark") {
    ZStack {
        Color.cfGroupedBackground.ignoresSafeArea()
        CelebrationCardView(event: .tierUp(newTier: "Luminary", previousTier: "Analyst"))
            .padding(.cfSpacing32)
    }
    .preferredColorScheme(.dark)
}

#Preview("CelebrationCard — XXL") {
    ZStack {
        Color.cfGroupedBackground.ignoresSafeArea()
        CelebrationCardView(event: .badgeEarned(badge: BadgeItem(
            badgeId: "first-finish",
            name: "Finisher",
            description: "Completed your first book from cover to cover.",
            category: "achievement",
            isEarned: true,
            earnedAt: nil,
            icon: nil
        )))
        .padding(.cfSpacing32)
    }
    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}
