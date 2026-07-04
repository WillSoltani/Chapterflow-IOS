import SwiftUI
import Models
import DesignSystem
import Persistence

/// A sheet for configuring per-book reading preferences.
///
/// Controls: depth variant, tone, learning mode, and audio narration default.
/// Changes persist locally on every selection; the server sync fires on dismiss.
///
/// When `model.recommendedVariant` is non-nil (set by P6.4), a highlighted
/// "Recommended for you" banner appears above the depth picker.
public struct BookPreferencesSheet: View {
    @State private var model: BookPreferencesModel
    @Environment(\.dismiss) private var dismiss

    public init(model: BookPreferencesModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            List {
                recommendedSection
                depthSection
                toneSection
                learningModeSection
                audioSection
                resetSection
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Reading Preferences")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.syncToServer()
                        dismiss()
                    }
                    .font(.cfHeadline)
                }
            }
        }
    }

    // MARK: - Recommended depth

    @ViewBuilder
    private var recommendedSection: some View {
        if let recommended = model.recommendedVariant, !recommended.isUnknown {
            Section {
                Button {
                    model.selectedVariant = recommended
                } label: {
                    HStack(spacing: .cfSpacing12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.cfAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recommended for you")
                                .font(.cfSubheadline)
                                .foregroundStyle(Color.cfLabel)
                            Text(model.displayName(for: recommended))
                                .font(.cfCaption)
                                .foregroundStyle(Color.cfAccent)
                        }
                        Spacer()
                        if model.selectedVariant == recommended {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.cfAccent)
                                .font(.cfSubheadline)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apply recommended depth: \(model.displayName(for: recommended))")
            } header: {
                Text("AI Recommendation")
            }
        }
    }

    // MARK: - Depth

    private var depthSection: some View {
        Section {
            if model.availableVariants.isEmpty {
                Text("Depth options not available for this book")
                    .font(.cfBody)
                    .foregroundStyle(Color.cfSecondaryLabel)
            } else {
                ForEach(model.availableVariants, id: \.rawValue) { variant in
                    depthRow(variant)
                }
            }
        } header: {
            sectionHeader("Reading Depth", systemImage: "text.magnifyingglass")
        } footer: {
            Text("Switch depth anytime while reading without losing your place.")
                .font(.cfCaption2)
        }
    }

    private func depthRow(_ variant: VariantKey) -> some View {
        let isSelected = model.selectedVariant == variant
        return Button {
            model.selectedVariant = variant
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName(for: variant))
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfLabel)
                    Text(model.description(for: variant))
                        .font(.cfCaption2)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.cfAccent)
                        .font(.cfSubheadline)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.displayName(for: variant)): \(model.description(for: variant))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Tone

    private var toneSection: some View {
        Section {
            ForEach([ToneKey.gentle, .direct, .competitive], id: \.rawValue) { tone in
                toneRow(tone)
            }
        } header: {
            sectionHeader("Teaching Tone", systemImage: "quote.bubble")
        } footer: {
            Text("Switch tone anytime in the reader.")
                .font(.cfCaption2)
        }
    }

    private func toneRow(_ tone: ToneKey) -> some View {
        let isSelected = model.selectedTone == tone
        return Button {
            model.selectedTone = tone
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName(for: tone))
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfLabel)
                    Text(model.description(for: tone))
                        .font(.cfCaption2)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.cfAccent)
                        .font(.cfSubheadline)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.displayName(for: tone)): \(model.description(for: tone))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Learning mode

    private var learningModeSection: some View {
        Section {
            ForEach(LearningMode.allCases, id: \.rawValue) { mode in
                learningModeRow(mode)
            }
        } header: {
            sectionHeader("Learning Mode", systemImage: "brain.head.profile")
        } footer: {
            Text("Sets the default entry point when you open a chapter.")
                .font(.cfCaption2)
        }
    }

    private func learningModeRow(_ mode: LearningMode) -> some View {
        let isSelected = model.learningMode == mode
        return Button {
            model.learningMode = mode
        } label: {
            HStack(spacing: .cfSpacing12) {
                Image(systemName: mode.systemImage)
                    .foregroundStyle(isSelected ? Color.cfAccent : Color.cfSecondaryLabel)
                    .frame(width: 24)
                Text(mode.displayName)
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfLabel)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.cfAccent)
                        .font(.cfSubheadline)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Audio narration

    private var audioSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.audioNarrationEnabled },
                set: { model.audioNarrationEnabled = $0 }
            )) {
                Label("Start with Audio", systemImage: "headphones")
                    .font(.cfSubheadline)
                    .foregroundStyle(Color.cfLabel)
            }
            .tint(Color.cfAccent)
        } header: {
            sectionHeader("Audio Narration", systemImage: "speaker.wave.2")
        } footer: {
            Text("When enabled, the audio player opens automatically with each chapter.")
                .font(.cfCaption2)
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                model.resetToGlobalDefaults()
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset to Global Defaults")
                }
                .font(.cfSubheadline)
            }
            .disabled(!model.hasPerBookOverride)
            .accessibilityLabel("Reset book preferences to global defaults")
        } footer: {
            if model.hasPerBookOverride {
                Text("This book has custom settings. Resetting will apply your global defaults from Settings.")
                    .font(.cfCaption2)
            } else {
                Text("Using global defaults from Settings.")
                    .font(.cfCaption2)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.cfCaption)
            .foregroundStyle(Color.cfSecondaryLabel)
            .textCase(nil)
    }
}

// MARK: - VariantKey helper

private extension VariantKey {
    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

// MARK: - Previews

#if DEBUG
#Preview("EMH book — no override (light)") {
    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "preview.bookprefs.emh"))
    let model = BookPreferencesModel(
        bookId: "b-atomic-habits",
        variantFamily: .emh,
        store: KeyValueStore(defaults: UserDefaults(suiteName: "preview.bookprefs.emh.store")),
        preferences: prefs
    )
    return BookPreferencesSheet(model: model)
}

#Preview("PBC book — with override (dark)") {
    let defaults = UserDefaults(suiteName: "preview.bookprefs.pbc")!
    defaults.removePersistentDomain(forName: "preview.bookprefs.pbc")
    let prefs = AppPreferences(defaults: defaults)
    let storeDefaults = UserDefaults(suiteName: "preview.bookprefs.pbc.store")!
    storeDefaults.removePersistentDomain(forName: "preview.bookprefs.pbc.store")
    let store = KeyValueStore(defaults: storeDefaults)
    let saved = BookReadingPreferences(
        variantKeyRaw: "challenging",
        toneKeyRaw: "competitive",
        learningMode: "listening",
        audioNarrationEnabled: true
    )
    try? store.set(saved, forKey: BookReadingPreferences.storageKey(for: "b-deep-work"))
    let model = BookPreferencesModel(
        bookId: "b-deep-work",
        variantFamily: .pbc,
        store: store,
        preferences: prefs
    )
    return BookPreferencesSheet(model: model)
        .preferredColorScheme(.dark)
}

#Preview("With AI recommendation") {
    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "preview.bookprefs.rec"))
    let model = BookPreferencesModel(
        bookId: "b-atomic-habits",
        variantFamily: .emh,
        store: KeyValueStore(defaults: UserDefaults(suiteName: "preview.bookprefs.rec.store")),
        preferences: prefs
    )
    model.recommendedVariant = .hard
    return BookPreferencesSheet(model: model)
}

#Preview("XXL Dynamic Type") {
    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "preview.bookprefs.xxl"))
    let model = BookPreferencesModel(
        bookId: "b-atomic-habits",
        variantFamily: .emh,
        store: KeyValueStore(defaults: UserDefaults(suiteName: "preview.bookprefs.xxl.store")),
        preferences: prefs
    )
    return BookPreferencesSheet(model: model)
        .dynamicTypeSize(.accessibility3)
}
#endif
