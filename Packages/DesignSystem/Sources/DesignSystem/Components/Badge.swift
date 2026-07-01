import SwiftUI

/// A small notification badge — either a numeric count (capsule) or a bare dot.
/// Use ``SwiftUI/View/dsBadge(count:)`` / ``SwiftUI/View/dsBadgeDot(_:)`` to
/// overlay one on an icon.
public struct Badge: View {
    private let count: Int?

    /// A numeric badge. Counts above 99 render as "99+"; zero renders nothing.
    public init(count: Int) {
        self.count = count
    }

    /// A bare dot badge (no number).
    public init() {
        self.count = nil
    }

    public var body: some View {
        Group {
            if let count {
                if count > 0 {
                    Text(displayCount(count))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(DSColor.onAccent)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(DSColor.danger, in: Capsule())
                }
            } else {
                Circle()
                    .fill(DSColor.danger)
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func displayCount(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    private var accessibilityLabel: Text {
        if let count, count > 0 {
            Text("\(count) new")
        } else {
            Text("New")
        }
    }
}

public extension View {
    /// Overlays a numeric ``Badge`` on the top-trailing corner.
    func dsBadge(count: Int) -> some View {
        overlay(alignment: .topTrailing) {
            Badge(count: count)
                .alignmentGuide(.top) { $0[.top] + 6 }
                .alignmentGuide(.trailing) { $0[.trailing] - 6 }
        }
    }

    /// Overlays a dot ``Badge`` on the top-trailing corner when `isVisible`.
    func dsBadgeDot(_ isVisible: Bool) -> some View {
        overlay(alignment: .topTrailing) {
            if isVisible {
                Badge()
                    .alignmentGuide(.top) { $0[.top] + 4 }
                    .alignmentGuide(.trailing) { $0[.trailing] - 4 }
            }
        }
    }
}

#Preview("Badge", traits: .sizeThatFitsLayout) {
    DSPreviewMatrix {
        HStack(spacing: DSSpacing.lg) {
            Image(systemName: "bell.fill")
                .font(.title2)
                .foregroundStyle(DSColor.textPrimary)
                .dsBadge(count: 3)
            Image(systemName: "tray.fill")
                .font(.title2)
                .foregroundStyle(DSColor.textPrimary)
                .dsBadge(count: 128)
            Image(systemName: "person.fill")
                .font(.title2)
                .foregroundStyle(DSColor.textPrimary)
                .dsBadgeDot(true)
        }
        .padding(DSSpacing.md)
    }
}
