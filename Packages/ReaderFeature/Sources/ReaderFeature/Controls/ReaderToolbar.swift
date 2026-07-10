import SwiftUI
import Models
import DesignSystem
import Persistence

/// The auto-hiding reader control bar overlaid at the bottom of the reading surface.
///
/// Contains the depth (variant) and tone switchers, a reading-mode toggle,
/// quick access to the appearance panel, and a focus-mode button.
/// Also hosts the "Recommended for you" depth hint slot (filled by P6.4).
///
/// Depth and tone switches update content instantly via `ReaderControlsModel`
/// — no network call is made.
public struct ReaderToolbar: View {
    private let model: ReaderControlsModel
    private let currentTopIndex: Int
    private let navModel: ChapterNavModel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        model: ReaderControlsModel,
        currentTopIndex: Int,
        navModel: ChapterNavModel? = nil
    ) {
        self.model = model
        self.currentTopIndex = currentTopIndex
        self.navModel = navModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            recommendedHint
            mainControls
        }
        .background(
            RoundedRectangle(cornerRadius: .cfRadius16)
                .fill(reduceTransparency
                    ? AnyShapeStyle(Color.cfSecondaryBackground)
                    : AnyShapeStyle(.regularMaterial))
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -2)
        .padding(.horizontal, .cfSpacing16)
        .padding(.bottom, .cfSpacing8)
    }

    // MARK: - Recommended depth hint (P6.4)

    @ViewBuilder
    private var recommendedHint: some View {
        if let recommended = model.recommendedVariant,
           recommended != model.selectedVariant,
           !recommended.isUnknown {
            VStack(spacing: 0) {
                Button {
                    model.switchVariant(recommended, currentTopIndex: currentTopIndex)
                } label: {
                    HStack(alignment: .top, spacing: .cfSpacing8) {
                        Image(systemName: "sparkles")
                            .font(.cfCaption)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recommended for you: \(model.displayName(for: recommended))")
                                .font(.cfCaption)
                                .fontWeight(.medium)
                            if let rationale = model.recommendedRationale, !rationale.isEmpty {
                                Text(rationale)
                                    .font(.cfCaption2)
                                    .foregroundStyle(Color.cfAccent.opacity(0.8))
                            }
                        }
                    }
                    .foregroundStyle(Color.cfAccent)
                    .padding(.horizontal, .cfSpacing16)
                    .padding(.vertical, .cfSpacing8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Switch to recommended depth: \(model.displayName(for: recommended))"
                )

                Divider().padding(.horizontal, .cfSpacing12)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Main controls

    private var mainControls: some View {
        VStack(spacing: 0) {
            scrubberRow
            Divider().padding(.horizontal, .cfSpacing12)
            if !model.availableVariants.isEmpty {
                depthRow
                Divider().padding(.horizontal, .cfSpacing12)
            }
            toneRow
            Divider().padding(.horizontal, .cfSpacing12)
            actionRow
            if navModel != nil {
                Divider().padding(.horizontal, .cfSpacing12)
                navRow
            }
        }
    }

    // MARK: - Scrubber row

    private var scrubberRow: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            sectionLabel("Position")
            ChapterScrubberView(
                readPercent: model.readPercent,
                blockCount: model.blocks.count
            ) { [model] blockIndex in
                model.pendingScrollAnchor = blockIndex
            }
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.top, .cfSpacing12)
        .padding(.bottom, .cfSpacing8)
    }

    // MARK: - Nav row (prev / ToC / next)

    @ViewBuilder
    private var navRow: some View {
        if let nav = navModel {
            HStack {
                previousButton(nav: nav)
                Spacer()
                tocButton(nav: nav)
                Spacer()
                nextButton(nav: nav)
            }
            .padding(.horizontal, .cfSpacing16)
            .padding(.vertical, .cfSpacing8)
        }
    }

    private func previousButton(nav: ChapterNavModel) -> some View {
        Button {
            nav.goToPreviousChapter()
        } label: {
            HStack(spacing: .cfSpacing4) {
                Image(systemName: "chevron.left")
                    .font(.cfCaption.weight(.semibold))
                Text("Previous")
                    .font(.cfCaption)
            }
            .foregroundStyle(nav.canGoPrevious ? Color.cfLabel : Color.cfTertiaryLabel)
            .padding(.horizontal, .cfSpacing12)
            .padding(.vertical, .cfSpacing8)
            .background(Color.cfSecondaryFill, in: RoundedRectangle(cornerRadius: .cfRadius8))
        }
        .buttonStyle(.plain)
        .disabled(!nav.canGoPrevious)
        .accessibilityLabel("Previous chapter")
        .accessibilityHint(nav.canGoPrevious ? "" : "No previous chapter available")
    }

    private func tocButton(nav: ChapterNavModel) -> some View {
        Button {
            nav.isToCPresented = true
        } label: {
            HStack(spacing: .cfSpacing4) {
                Image(systemName: "list.bullet")
                    .font(.cfCaption)
                Text("Contents")
                    .font(.cfCaption)
            }
            .foregroundStyle(Color.cfAccent)
            .padding(.horizontal, .cfSpacing12)
            .padding(.vertical, .cfSpacing8)
            .background(Color.cfAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: .cfRadius8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Table of Contents")
    }

    private func nextButton(nav: ChapterNavModel) -> some View {
        Button {
            nav.goToNextChapter()
        } label: {
            HStack(spacing: .cfSpacing4) {
                Text("Next")
                    .font(.cfCaption)
                Image(systemName: "chevron.right")
                    .font(.cfCaption.weight(.semibold))
            }
            .foregroundStyle(nav.canGoNext ? Color.cfLabel : Color.cfTertiaryLabel)
            .padding(.horizontal, .cfSpacing12)
            .padding(.vertical, .cfSpacing8)
            .background(Color.cfSecondaryFill, in: RoundedRectangle(cornerRadius: .cfRadius8))
        }
        .buttonStyle(.plain)
        .disabled(!nav.canGoNext)
        .accessibilityLabel("Next chapter")
        .accessibilityHint(nav.canGoNext ? "" : "Next chapter is locked or unavailable")
    }

    // MARK: - Depth row

    private var depthRow: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            sectionLabel("Depth")
            HStack(spacing: .cfSpacing4) {
                ForEach(model.availableVariants, id: \.rawValue) { variant in
                    depthButton(for: variant)
                }
            }
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.top, .cfSpacing12)
        .padding(.bottom, .cfSpacing12)
    }

    private func depthButton(for variant: VariantKey) -> some View {
        let isSelected = model.selectedVariant == variant
        let isRecommended = model.recommendedVariant == variant && !variant.isUnknown
        let bgColor: Color = isSelected
            ? Color.cfAccent
            : (isRecommended ? Color.cfAccent.opacity(0.1) : Color.cfSecondaryFill)

        return Button {
            model.switchVariant(variant, currentTopIndex: currentTopIndex)
        } label: {
            HStack(spacing: 3) {
                if isRecommended {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.cfAccent)
                }
                Text(model.displayName(for: variant))
                    .font(.cfSubheadline)
                    .foregroundStyle(isSelected ? Color.white : Color.cfLabel)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: .cfRadius8)
                    .fill(bgColor)
                    .animation(reduceMotion ? .none : .spring(duration: 0.2), value: isSelected)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(model.displayName(for: variant)) depth\(isRecommended ? ", recommended for you" : "")"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Tone row

    private var toneRow: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            sectionLabel("Tone")
            HStack(spacing: .cfSpacing4) {
                ForEach([ToneKey.gentle, .direct, .competitive], id: \.rawValue) { tone in
                    toneButton(for: tone)
                }
            }
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.top, .cfSpacing12)
        .padding(.bottom, .cfSpacing12)
    }

    private func toneButton(for tone: ToneKey) -> some View {
        let isSelected = model.selectedTone == tone
        return Button {
            model.switchTone(tone, currentTopIndex: currentTopIndex)
        } label: {
            Text(model.displayName(for: tone))
                .font(.cfSubheadline)
                .foregroundStyle(isSelected ? Color.white : Color.cfLabel)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    RoundedRectangle(cornerRadius: .cfRadius8)
                        .fill(isSelected ? Color.cfAccent : Color.cfSecondaryFill)
                        .animation(reduceMotion ? .none : .spring(duration: 0.2), value: isSelected)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.displayName(for: tone)) tone")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack {
            readingModeButton
            Spacer()
            bookPreferencesButton
            Spacer().frame(width: .cfSpacing16)
            appearanceButton
            Spacer().frame(width: .cfSpacing16)
            focusModeButton
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing8)
    }

    private var readingModeButton: some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring(duration: 0.25)) {
                switch model.readingMode {
                case .scroll:   model.readingMode = .paginate
                case .paginate: model.readingMode = .scroll
                }
            }
        } label: {
            HStack(spacing: .cfSpacing4) {
                Image(systemName: model.readingMode == .scroll
                    ? "doc.text.below.ecg"
                    : "doc.text")
                    .font(.cfCallout)
                Text(model.readingMode == .scroll ? "Scroll" : "Pages")
                    .font(.cfCaption)
            }
            .foregroundStyle(Color.cfLabel)
            .padding(.horizontal, .cfSpacing12)
            .padding(.vertical, .cfSpacing8)
            .background(Color.cfSecondaryFill, in: RoundedRectangle(cornerRadius: .cfRadius8))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            model.readingMode == .scroll
                ? "Switch to paginated reading"
                : "Switch to scroll reading"
        )
    }

    private var appearanceButton: some View {
        Button {
            model.isAppearancePanelPresented = true
        } label: {
            Image(systemName: "textformat.size")
                .font(.cfCallout)
                .foregroundStyle(Color.cfLabel)
                .frame(width: 44, height: 44)
                .background(Color.cfSecondaryFill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reading appearance")
    }

    private var bookPreferencesButton: some View {
        Button {
            model.isBookPreferencesPanelPresented = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.cfCallout)
                .foregroundStyle(Color.cfLabel)
                .frame(width: 44, height: 44)
                .background(Color.cfSecondaryFill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Book reading preferences")
    }

    private var focusModeButton: some View {
        Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.3)) {
                model.toggleFocusMode()
            }
        } label: {
            Image(systemName: model.isFocusModeActive ? "eye.slash" : "eye")
                .font(.cfCallout)
                .foregroundStyle(model.isFocusModeActive ? Color.cfAccent : Color.cfLabel)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(
                            model.isFocusModeActive
                                ? Color.cfAccent.opacity(0.12)
                                : Color.cfSecondaryFill
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            model.isFocusModeActive ? "Exit focus mode" : "Enter focus mode"
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.cfCaption)
            .foregroundStyle(Color.cfSecondaryLabel)
    }
}

// MARK: - VariantKey helper

private extension VariantKey {
    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}
