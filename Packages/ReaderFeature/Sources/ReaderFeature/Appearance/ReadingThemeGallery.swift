#if DEBUG
import SwiftUI
import DesignSystem
import Persistence

/// A design-QA gallery that renders every reading theme side by side.
/// Open this preview to verify the token set looks premium for each theme.
struct ReadingThemeGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(ReadingTheme.allCases, id: \.self) { theme in
                    themeCard(theme: theme)
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func themeCard(theme: ReadingTheme) -> some View {
        let tokens = ReadingThemeTokens.tokens(for: theme)
        let appearance = ReadingAppearance(
            colors: tokens,
            fontScale: 1.0,
            lineSpacing: 6,
            colorSchemeOverride: theme == .dark ? .dark : (theme == .system ? nil : .light)
        )

        VStack(alignment: .leading, spacing: 12) {
            // Theme label
            Text(theme.displayName.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.tertiaryText)
                .kerning(1.2)

            // Body prose sample
            Text("Small habits might seem insignificant at first, but tiny **1% improvements** compound into remarkable results over time.")
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(tokens.primaryText)
                .lineSpacing(6)

            Divider().overlay(tokens.separator)

            // Card samples
            HStack(spacing: 12) {
                // Key-takeaway stripe
                HStack(spacing: 0) {
                    Rectangle().fill(tokens.quoteBar).frame(width: 3)
                    Text("Focus on systems, not goals.")
                        .font(.system(.subheadline, design: .default))
                        .foregroundStyle(tokens.primaryText)
                        .padding(10)
                }
                .background(tokens.surfaceBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity)

                // Pull-quote mark
                VStack(spacing: 4) {
                    Text("\u{201C}")
                        .font(.system(size: 32, weight: .thin, design: .serif))
                        .foregroundStyle(tokens.quoteBar)
                    Text("You fall to the level of your systems.")
                        .font(.system(size: 13, weight: .light, design: .serif))
                        .italic()
                        .foregroundStyle(tokens.quoteText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            // Accent swatch
            HStack(spacing: 8) {
                Circle().fill(tokens.accent).frame(width: 16, height: 16)
                Text("Accent · \(theme.displayName)")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.secondaryText)
            }
        }
        .padding(20)
        .background(tokens.pageBg)
        .environment(\.readerAppearance, appearance)
    }
}

#Preview("Theme Gallery — All") {
    ReadingThemeGallery()
}
#endif
