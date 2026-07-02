import SwiftUI
import DesignSystem
import Persistence

/// A bottom-sheet panel for adjusting reading font size, line spacing, and theme.
///
/// Bind this to a sheet or overlay; it writes directly to `AppPreferences` so
/// changes persist and propagate to the reader instantly via the environment.
public struct ReadingAppearancePanel: View {
    private let preferences: AppPreferences

    public init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle
            content
        }
        .background(Color(uiOrNs: "systemBackground", fallback: .white))
        .clipShape(RoundedRectangle(cornerRadius: .cfRadius20))
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: -4)
    }

    // MARK: - Handle

    private var handle: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(Color.cfSeparator)
                .frame(width: 36, height: 5)
            Spacer()
        }
        .padding(.top, .cfSpacing12)
        .padding(.bottom, .cfSpacing8)
    }

    // MARK: - Main content

    private var content: some View {
        VStack(alignment: .leading, spacing: .cfSpacing24) {
            fontSizeRow
            Divider().padding(.horizontal, .cfSpacing20)
            lineSpacingRow
            Divider().padding(.horizontal, .cfSpacing20)
            themeRow
        }
        .padding(.horizontal, .cfSpacing20)
        .padding(.bottom, .cfSpacing32)
    }

    // MARK: - Font Size

    private var fontSizeRow: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            sectionHeader("Font Size")
            HStack(spacing: .cfSpacing12) {
                fontSizeButton(label: "A−", imageName: "textformat.size.smaller", step: -1)
                fontSizeSteps
                fontSizeButton(label: "A+", imageName: "textformat.size.larger", step: +1)
            }
        }
    }

    private var fontSizeSteps: some View {
        HStack(spacing: .cfSpacing4) {
            ForEach(0 ..< FontSizeStep.allCases.count, id: \.self) { index in
                let step = FontSizeStep.allCases[index]
                let isActive = currentFontStep == step
                Circle()
                    .fill(isActive ? Color.cfAccent : Color.cfSeparator)
                    .frame(width: isActive ? 8 : 6, height: isActive ? 8 : 6)
                    .animation(.spring(duration: 0.2), value: isActive)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func fontSizeButton(label: String, imageName: String, step: Int) -> some View {
        Button {
            adjustFontSize(by: step)
        } label: {
            VStack(spacing: .cfSpacing4) {
                Image(systemName: imageName)
                    .font(.cfBody)
                Text(label)
                    .font(.cfCaption)
            }
            .foregroundStyle(Color.cfLabel)
            .frame(width: 52, height: 44)
            .background(Color.cfSecondaryFill)
            .clipShape(RoundedRectangle(cornerRadius: .cfRadius8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step < 0 ? "Decrease font size" : "Increase font size")
        .disabled(step < 0
            ? currentFontStep == FontSizeStep.allCases.first
            : currentFontStep == FontSizeStep.allCases.last)
    }

    // MARK: - Line Spacing

    private var lineSpacingRow: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            sectionHeader("Line Spacing")
            HStack(spacing: .cfSpacing8) {
                ForEach(LineSpacingOption.allCases, id: \.self) { option in
                    lineSpacingButton(option: option)
                }
            }
        }
    }

    private func lineSpacingButton(option: LineSpacingOption) -> some View {
        let isActive = abs(preferences.readerLineSpacing - option.value) < 0.5
        return Button {
            withAnimation(.spring(duration: 0.2)) {
                preferences.readerLineSpacing = option.value
            }
        } label: {
            VStack(spacing: .cfSpacing4) {
                Image(systemName: option.systemImage)
                    .font(.cfBody)
                    .foregroundStyle(isActive ? Color.cfAccent : Color.cfLabel)
                Text(option.label)
                    .font(.cfCaption)
                    .foregroundStyle(isActive ? Color.cfAccent : Color.cfSecondaryLabel)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: .cfRadius8)
                    .fill(isActive ? Color.cfAccent.opacity(0.10) : Color.cfSecondaryFill)
                    .animation(.spring(duration: 0.2), value: isActive)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.label) line spacing")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Theme

    private var themeRow: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            sectionHeader("Theme")
            HStack(spacing: .cfSpacing8) {
                ForEach(ReadingTheme.allCases, id: \.self) { theme in
                    themeButton(theme: theme)
                }
            }
        }
    }

    private func themeButton(theme: ReadingTheme) -> some View {
        let tokens = ReadingThemeTokens.tokens(for: theme)
        let isActive = preferences.readerTheme == theme
        return Button {
            withAnimation(.spring(duration: 0.22)) {
                preferences.readerTheme = theme
            }
        } label: {
            VStack(spacing: .cfSpacing4) {
                ZStack {
                    Circle()
                        .fill(tokens.pageBg)
                        .frame(width: 36, height: 36)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    isActive ? tokens.accent : tokens.separator,
                                    lineWidth: isActive ? 2.5 : 1
                                )
                        }
                    Text("Aa")
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundStyle(tokens.primaryText)
                }
                Text(theme.displayName)
                    .font(.cfCaption2)
                    .foregroundStyle(isActive ? Color.cfLabel : Color.cfSecondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .scaleEffect(isActive ? 1.08 : 1.0)
            .animation(.spring(duration: 0.22), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.displayName) theme")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.cfSubheadline)
            .foregroundStyle(Color.cfSecondaryLabel)
    }

    // MARK: - Font size step logic

    private var currentFontStep: FontSizeStep {
        FontSizeStep.closest(to: preferences.readerFontScale)
    }

    private func adjustFontSize(by delta: Int) {
        let steps = FontSizeStep.allCases
        guard let current = steps.firstIndex(of: currentFontStep) else { return }
        let next = (current + delta).clamped(to: 0 ..< steps.count)
        withAnimation(.spring(duration: 0.2)) {
            preferences.readerFontScale = steps[next].scale
        }
    }
}

// MARK: - Supporting types

/// Discrete font-size steps that map to concrete scale values.
enum FontSizeStep: CaseIterable {
    case xs, small, medium, large, xl, xxl

    var scale: Double {
        switch self {
        case .xs:     return 0.82
        case .small:  return 0.91
        case .medium: return 1.00
        case .large:  return 1.12
        case .xl:     return 1.27
        case .xxl:    return 1.50
        }
    }

    static func closest(to value: Double) -> FontSizeStep {
        allCases.min(by: { abs($0.scale - value) < abs($1.scale - value) }) ?? .medium
    }
}

/// Discrete line-spacing options shown in the panel.
enum LineSpacingOption: Double, CaseIterable {
    case compact = 2
    case normal = 6
    case comfortable = 11

    var value: Double { rawValue }

    var label: String {
        switch self {
        case .compact:     return "Compact"
        case .normal:      return "Normal"
        case .comfortable: return "Spacious"
        }
    }

    var systemImage: String {
        switch self {
        case .compact:     return "line.3.horizontal"
        case .normal:      return "text.alignleft"
        case .comfortable: return "text.lineheight"
        }
    }
}

// MARK: - Platform shim

private extension Color {
    /// Returns the system background on UIKit platforms; falls back to `fallback` on macOS.
    init(uiOrNs name: String, fallback: Color) {
        #if canImport(UIKit)
        self = Color(UIColor.systemBackground)
        #else
        self = fallback
        #endif
    }
}

private extension Int {
    func clamped(to range: Range<Int>) -> Int {
        Swift.max(range.lowerBound, Swift.min(self, range.upperBound - 1))
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private func makePreviewPrefs(
    theme: ReadingTheme = .system,
    fontScale: Double = 1.0,
    lineSpacing: Double = 6
) -> AppPreferences {
    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "preview.reading.\(theme.rawValue)"))
    prefs.readerTheme = theme
    prefs.readerFontScale = fontScale
    prefs.readerLineSpacing = lineSpacing
    return prefs
}

#Preview("Appearance Panel — Light") {
    ReadingAppearancePanel(preferences: makePreviewPrefs())
        .padding()
}

#Preview("Appearance Panel — Sepia") {
    ReadingAppearancePanel(preferences: makePreviewPrefs(theme: .sepia))
        .padding()
}

#Preview("Appearance Panel — Dark") {
    ReadingAppearancePanel(preferences: makePreviewPrefs(theme: .dark))
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Appearance Panel — XXL Text") {
    ReadingAppearancePanel(preferences: makePreviewPrefs())
        .padding()
        .dynamicTypeSize(.accessibility3)
}
#endif
