import SwiftUI
import Models
import DesignSystem

/// A visual mockup of what ChapterFlow items look like in Spotlight search.
///
/// Used only in `#Preview`s to verify thumbnail + label rendering. The actual
/// Spotlight UI is rendered by the system; this view approximates its look.
struct SpotlightResultRow: View {

    let emoji: String
    let hexColor: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: .cfSpacing12) {
            coverThumb
            labels
            Spacer(minLength: 0)
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing8)
    }

    private var coverThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: .cfRadius8)
                .fill(Color(hex: hexColor) ?? Color.cfFill)
                .frame(width: .cfIconLarge, height: .cfIconLarge)
            Text(emoji)
                .font(.title3)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.cfCallout)
                .fontWeight(.semibold)
                .foregroundStyle(Color.cfLabel)
            Text(subtitle)
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
        }
    }
}

// MARK: - Hex helper (preview-only, not shared with SpotlightIndexer)

private extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str = String(str.dropFirst()) }
        guard str.count == 6, let value = UInt64(str, radix: 16) else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double((value      ) & 0xFF) / 255
        )
    }
}

// MARK: - Previews

#Preview("Spotlight results — light") {
    List {
        Section("Books") {
            SpotlightResultRow(
                emoji: "⚛️",
                hexColor: "#2D6A4F",
                title: "Atomic Habits",
                subtitle: "by James Clear"
            )
            SpotlightResultRow(
                emoji: "🎯",
                hexColor: "#1B4332",
                title: "Deep Work",
                subtitle: "by Cal Newport"
            )
            SpotlightResultRow(
                emoji: "🧠",
                hexColor: "#1A237E",
                title: "Thinking, Fast and Slow",
                subtitle: "by Daniel Kahneman"
            )
        }
        Section("Chapters") {
            SpotlightResultRow(
                emoji: "⚛️",
                hexColor: "#2D6A4F",
                title: "The Surprising Power of Atomic Habits",
                subtitle: "Atomic Habits · Chapter 1 · by James Clear"
            )
            SpotlightResultRow(
                emoji: "⚛️",
                hexColor: "#2D6A4F",
                title: "How Your Habits Shape Your Identity",
                subtitle: "Atomic Habits · Chapter 2 · by James Clear"
            )
        }
    }
}

#Preview("Spotlight results — dark") {
    List {
        Section("Books") {
            SpotlightResultRow(
                emoji: "⚛️",
                hexColor: "#2D6A4F",
                title: "Atomic Habits",
                subtitle: "by James Clear"
            )
            SpotlightResultRow(
                emoji: "🎯",
                hexColor: "#1B4332",
                title: "Deep Work",
                subtitle: "by Cal Newport"
            )
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Spotlight results — XXL text") {
    List {
        SpotlightResultRow(
            emoji: "⚛️",
            hexColor: "#2D6A4F",
            title: "Atomic Habits",
            subtitle: "by James Clear"
        )
        SpotlightResultRow(
            emoji: "⚛️",
            hexColor: "#2D6A4F",
            title: "The Surprising Power of Atomic Habits",
            subtitle: "Atomic Habits · Chapter 1 · by James Clear"
        )
    }
    .dynamicTypeSize(.accessibility3)
}
