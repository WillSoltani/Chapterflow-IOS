import SwiftUI

/// A single scrollable catalog of every design-system token and component, for
/// visual QA. Render it in light/dark and at the largest Dynamic Type size to
/// confirm nothing clips.
public struct DesignSystemGallery: View {
    @State private var depth: Depth = .medium
    @State private var showSheet = false
    @State private var toast: ToastData?

    private enum Depth: String, CaseIterable, Hashable {
        case easy, medium, hard
    }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                buttonsSection
                displaySection
                progressSection
                feedbackSection
                colorSection
                typographySection
            }
            .padding(DSSpacing.md)
        }
        .background(DSColor.background)
        .toast($toast)
        .bottomSheet(isPresented: $showSheet, title: "Reading Settings") {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("A design-system bottom sheet.")
                    .font(DSTypography.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
                PrimaryButton("Done") { showSheet = false }
            }
        }
    }

    // MARK: Sections

    private var buttonsSection: some View {
        section("Buttons") {
            PrimaryButton("Continue Reading", icon: "book") { toast = .init(style: .success, message: "Primary tapped") }
            SecondaryButton("Add to Library", icon: "plus") { toast = .init(style: .info, message: "Secondary tapped") }
            HStack(spacing: DSSpacing.md) {
                IconButton(systemName: "heart", accessibilityLabel: "Save") {}
                IconButton(systemName: "textformat.size", accessibilityLabel: "Text size", style: .filled) {}
                IconButton(systemName: "ellipsis", accessibilityLabel: "More", style: .filled) {}
                Spacer()
            }
            SegmentedControl(selection: $depth, options: Depth.allCases) {
                LocalizedStringKey($0.rawValue.capitalized)
            }
        }
    }

    private var displaySection: some View {
        section("Surfaces & Tags") {
            Card {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("Atomic Habits").font(DSTypography.headline).foregroundStyle(DSColor.textPrimary)
                    Text("Chapter 3").font(DSTypography.subheadline).foregroundStyle(DSColor.textSecondary)
                }
            }
            HStack(spacing: DSSpacing.sm) {
                Pill("New", tint: .accent)
                Pill("Done", icon: "checkmark", tint: .success)
                Pill("Due", icon: "clock", tint: .warning)
            }
            HStack(spacing: DSSpacing.md) {
                Avatar(initials: "WS", size: .small)
                Avatar(initials: "RC", size: .medium)
                Avatar(size: .large)
                Image(systemName: "bell.fill")
                    .font(.title2).foregroundStyle(DSColor.textPrimary)
                    .dsBadge(count: 3)
            }
        }
    }

    private var progressSection: some View {
        section("Progress") {
            HStack(spacing: DSSpacing.lg) {
                ProgressRing(progress: 0.35, label: "35%")
                ProgressRing(progress: 0.8, tint: DSColor.success, label: "8/10")
            }
            LinearProgressBar(progress: 0.45)
            HStack(spacing: DSSpacing.sm) {
                Skeleton().frame(width: 44, height: 44)
                VStack(spacing: DSSpacing.sm) {
                    Skeleton().frame(height: 16)
                    Skeleton().frame(height: 16)
                }
            }
        }
    }

    private var feedbackSection: some View {
        section("Feedback") {
            SecondaryButton("Show Toast") { toast = .init(style: .success, message: "Saved to library") }
            SecondaryButton("Show Bottom Sheet") { showSheet = true }
            EmptyState(
                systemImage: "books.vertical",
                title: "No books yet",
                message: "Start a book to begin.",
                actionTitle: "Browse",
                action: {}
            )
        }
    }

    private var colorSection: some View {
        section("Colors") {
            let swatches: [(String, Color)] = [
                ("background", DSColor.background), ("surface", DSColor.surface),
                ("surfaceElevated", DSColor.surfaceElevated), ("accent", DSColor.accent),
                ("success", DSColor.success), ("warning", DSColor.warning),
                ("danger", DSColor.danger), ("separator", DSColor.separator)
            ]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: DSSpacing.sm)], spacing: DSSpacing.sm) {
                ForEach(swatches, id: \.0) { name, color in
                    VStack(spacing: DSSpacing.xs) {
                        RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous)
                            .fill(color)
                            .frame(height: 44)
                            .overlay(RoundedRectangle(cornerRadius: DSRadius.sm).strokeBorder(DSColor.separator))
                        Text(name).font(.caption2).foregroundStyle(DSColor.textSecondary)
                    }
                }
            }
        }
    }

    private var typographySection: some View {
        section("Typography") {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Large Title").font(DSTypography.largeTitle)
                Text("Title").font(DSTypography.title)
                Text("Headline").font(DSTypography.headline)
                Text("Reading body — a refined serif for long-form content.")
                    .font(DSTypography.body)
                Text("UI body — SF Pro for chrome and controls.")
                    .font(DSTypography.bodyUI)
                Text("Footnote").font(DSTypography.footnote).foregroundStyle(DSColor.textSecondary)
            }
            .foregroundStyle(DSColor.textPrimary)
        }
    }

    // MARK: Layout helper

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(title)
                .font(DSTypography.title2)
                .foregroundStyle(DSColor.textPrimary)
            content()
        }
    }
}

#Preview("Gallery · Light") {
    DesignSystemGallery().themeMode(.light)
}

#Preview("Gallery · Dark") {
    DesignSystemGallery().themeMode(.dark)
}

#Preview("Gallery · XXL") {
    DesignSystemGallery()
        .themeMode(.light)
        .dynamicTypeSize(.accessibility3)
}
