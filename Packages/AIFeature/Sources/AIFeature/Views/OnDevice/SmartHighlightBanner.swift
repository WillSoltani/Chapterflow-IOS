import SwiftUI
import DesignSystem

/// A non-intrusive banner surfacing on-device highlight suggestions.
///
/// Shows only when ``SmartHighlightModel/suggestions`` is non-empty.
/// Each suggestion chip can be tapped (to copy / start a highlight) or
/// dismissed with a swipe / the "×" button.
///
/// The caller must gate this view behind `OnDeviceAIAvailability.isAvailable`
/// and the feature flag — the view itself performs no availability check.
public struct SmartHighlightBanner: View {

    private let highlightModel: SmartHighlightModel
    private let onSelect: (String) -> Void

    public init(model: SmartHighlightModel, onSelect: @escaping (String) -> Void) {
        self.highlightModel = model
        self.onSelect = onSelect
    }

    public var body: some View {
        if !highlightModel.suggestions.isEmpty {
            bannerContent
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Banner

    private var bannerContent: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            headerRow
            suggestionsStack
        }
        .padding(.horizontal, .cfSpacing16)
        .padding(.vertical, .cfSpacing12)
        .background(
            RoundedRectangle(cornerRadius: .cfRadius12, style: .continuous)
                .fill(Color.cfAccent.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: .cfRadius12, style: .continuous)
                        .strokeBorder(Color.cfAccent.opacity(0.18), lineWidth: 0.5)
                )
        )
    }

    private var headerRow: some View {
        HStack(spacing: .cfSpacing6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.cfAccent)

            Text("Key sentences")
                .font(.cfCaption)
                .fontWeight(.medium)
                .foregroundStyle(Color.cfAccent)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    highlightModel.clearAll()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
            .accessibilityLabel("Dismiss highlight suggestions")
        }
    }

    private var suggestionsStack: some View {
        VStack(alignment: .leading, spacing: .cfSpacing6) {
            ForEach(highlightModel.suggestions, id: \.self) { suggestion in
                suggestionRow(suggestion)
            }
        }
    }

    private func suggestionRow(_ suggestion: String) -> some View {
        HStack(alignment: .top, spacing: .cfSpacing8) {
            Image(systemName: "quote.opening")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.cfAccent.opacity(0.7))
                .padding(.top, 3)

            Text(suggestion)
                .font(.cfFootnote)
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture {
                    onSelect(suggestion)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        highlightModel.dismiss(suggestion)
                    }
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suggested highlight: \(suggestion)")
        .accessibilityHint("Tap to use this highlight")
    }
}

private extension CGFloat {
    static let cfSpacing6: CGFloat = 6
}

// MARK: - Previews

#if DEBUG
#Preview("Smart highlights — loaded (light)") {
    let model = SmartHighlightModel(
        chapterText: "Sample chapter text about compound habits…",
        service: FakeOnDeviceAIService(availability: .available, delay: 0)
    )
    return VStack {
        SmartHighlightBanner(model: model) { suggestion in
            print("Selected: \(suggestion)")
        }
        .padding()
        Spacer()
    }
    .task { await model.loadSuggestions() }
    .background(Color.cfGroupedBackground)
}

#Preview("Smart highlights — loaded (dark)") {
    let model = SmartHighlightModel(
        chapterText: "Sample chapter text about compound habits…",
        service: FakeOnDeviceAIService(availability: .available, delay: 0)
    )
    return VStack {
        SmartHighlightBanner(model: model) { _ in }
            .padding()
        Spacer()
    }
    .task { await model.loadSuggestions() }
    .background(Color.cfGroupedBackground)
    .preferredColorScheme(.dark)
}

#Preview("Smart highlights — XXL text") {
    let model = SmartHighlightModel(
        chapterText: "Sample chapter text about compound habits…",
        service: FakeOnDeviceAIService(availability: .available, delay: 0)
    )
    return VStack {
        SmartHighlightBanner(model: model) { _ in }
            .padding()
        Spacer()
    }
    .task { await model.loadSuggestions() }
    .background(Color.cfGroupedBackground)
    .dynamicTypeSize(.accessibility3)
}

#Preview("Smart highlights — empty (unavailable)") {
    let model = SmartHighlightModel(
        chapterText: "Sample chapter text about compound habits…",
        service: FakeOnDeviceAIService(availability: .unavailableDeviceNotEligible)
    )
    return VStack {
        SmartHighlightBanner(model: model) { _ in }
            .padding()
        Text("(banner hidden — device not eligible)")
            .font(.cfCallout)
            .foregroundStyle(Color.cfSecondaryLabel)
        Spacer()
    }
    .task { await model.loadSuggestions() }
    .background(Color.cfGroupedBackground)
}
#endif
