import SwiftUI
import DesignSystem

/// A circular avatar showing either a remote image, an emoji, or two-letter initials.
///
/// When a cosmetic frame is equipped it is rendered as a decorative ring.
public struct AvatarView: View {

    private let avatarUrl: String?
    private let avatarEmoji: String?
    private let initials: String
    private let frame: CosmeticItem?
    private let size: CGFloat

    public init(
        avatarUrl: String?,
        avatarEmoji: String?,
        initials: String,
        equippedFrame: CosmeticItem?,
        size: CGFloat = 80
    ) {
        self.avatarUrl = avatarUrl
        self.avatarEmoji = avatarEmoji
        self.initials = initials
        self.frame = equippedFrame
        self.size = size
    }

    public var body: some View {
        ZStack {
            if let emoji = avatarEmoji, !emoji.isEmpty {
                emojiAvatar(emoji)
            } else if avatarUrl != nil {
                // Remote image placeholder — a proper AsyncImage could be added here
                // once the avatar-upload flow ships.
                initialsCircle
            } else {
                initialsCircle
            }

            if let frame, frame.itemType != .unknown("") {
                frameRing(for: frame)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(initials.isEmpty ? "Avatar" : "Avatar for \(initials)")
    }

    // MARK: - Sub-views

    private func emojiAvatar(_ emoji: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.cfAccent.opacity(0.12))
            Text(emoji)
                .font(.system(size: size * 0.5))
        }
    }

    private var initialsCircle: some View {
        ZStack {
            Circle()
                .fill(Color.cfAccent.opacity(0.18))
            Text(initials)
                .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.cfAccent)
        }
    }

    private func frameRing(for equippedFrame: CosmeticItem) -> some View {
        Circle()
            .strokeBorder(
                LinearGradient(
                    colors: frameColors(for: equippedFrame),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: size * 0.06
            )
            .frame(width: size + size * 0.12, height: size + size * 0.12)
    }

    private func frameColors(for equippedFrame: CosmeticItem) -> [Color] {
        switch equippedFrame.rarity {
        case "legendary": return [.yellow, .orange, .red]
        case "rare":      return [Color(red: 1, green: 0.84, blue: 0), Color(red: 0.85, green: 0.65, blue: 0)]
        case "uncommon":  return [Color.gray.opacity(0.8), Color.gray.opacity(0.4)]
        default:          return [Color.cfAccent.opacity(0.6), Color.cfAccent.opacity(0.3)]
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("AvatarView — variants") {
    VStack(spacing: .cfSpacing24) {
        HStack(spacing: .cfSpacing24) {
            AvatarView(
                avatarUrl: nil,
                avatarEmoji: nil,
                initials: "AR",
                equippedFrame: nil
            )

            AvatarView(
                avatarUrl: nil,
                avatarEmoji: "📚",
                initials: "?",
                equippedFrame: nil
            )

            AvatarView(
                avatarUrl: nil,
                avatarEmoji: nil,
                initials: "CL",
                equippedFrame: CosmeticItem(
                    itemId: "frame-gold",
                    name: "Gold Wave",
                    itemType: .avatarFrame,
                    rarity: "rare"
                )
            )
        }

        HStack(spacing: .cfSpacing24) {
            AvatarView(
                avatarUrl: nil,
                avatarEmoji: "✨",
                initials: "?",
                equippedFrame: CosmeticItem(
                    itemId: "frame-legend",
                    name: "Stellar",
                    itemType: .avatarFrame,
                    rarity: "legendary"
                ),
                size: 96
            )

            AvatarView(
                avatarUrl: nil,
                avatarEmoji: nil,
                initials: "?",
                equippedFrame: nil,
                size: 48
            )
        }
    }
    .padding(.cfSpacing32)
    .background(Color.cfGroupedBackground)
}
#endif
