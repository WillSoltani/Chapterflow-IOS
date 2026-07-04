import SwiftUI
import DesignSystem
import Persistence

// MARK: - Reading preferences step

struct ReadingPrefsStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            stepHeader(
                icon: "books.vertical",
                title: "How do you\nlike to learn?",
                subtitle: "Set your preferred reading order and teaching style."
            )
            .padding(.top, .cfSpacing48)

            ScrollView {
                VStack(alignment: .leading, spacing: .cfSpacing32) {
                    chapterOrderSection
                    toneSection
                }
                .padding(.horizontal, .cfSpacing24)
                .padding(.top, .cfSpacing24)
                .padding(.bottom, .cfSpacing20)
            }

            Spacer(minLength: 0)

            continueButton(label: "Continue", isEnabled: true) {
                Task { await model.advance() }
            }
            .padding(.horizontal, .cfSpacing24)
            .padding(.bottom, .cfSpacing40)
        }
    }

    // MARK: Sections

    private var chapterOrderSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            SectionLabel(text: "Reading Order")

            VStack(spacing: .cfSpacing8) {
                ForEach(chapterOrderOptions, id: \.order) { option in
                    PreferenceRow(
                        title: option.title,
                        subtitle: option.description,
                        isSelected: model.chapterOrder == option.order
                    ) {
                        model.chapterOrder = option.order
                    }
                }
            }
        }
    }

    private var toneSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            SectionLabel(text: "Teaching Tone")

            VStack(spacing: .cfSpacing8) {
                ForEach(toneOptions, id: \.tone) { option in
                    PreferenceRow(
                        title: option.title,
                        subtitle: option.description,
                        isSelected: model.readingTone == option.tone
                    ) {
                        model.readingTone = option.tone
                    }
                }
            }
        }
    }

    // MARK: Data

    private struct ChapterOrderOption {
        let order: ChapterOrder
        let title: String
        let description: String
    }

    private struct ToneOption {
        let tone: ReadingTone
        let title: String
        let description: String
    }

    private let chapterOrderOptions: [ChapterOrderOption] = [
        ChapterOrderOption(
            order: .summaryFirst,
            title: "Summary First",
            description: "See the key ideas upfront, then explore real-world context."
        ),
        ChapterOrderOption(
            order: .scenariosFirst,
            title: "Scenarios First",
            description: "Start with real-world examples, then synthesise the core ideas."
        ),
    ]

    private let toneOptions: [ToneOption] = [
        ToneOption(
            tone: .gentle,
            title: "Gentle",
            description: "Supportive, patient, and encouraging."
        ),
        ToneOption(
            tone: .direct,
            title: "Direct",
            description: "Clear, concise, and straight to the point."
        ),
        ToneOption(
            tone: .competitive,
            title: "Competitive",
            description: "Challenging and motivating — push your limits."
        ),
    ]
}

// MARK: - Shared sub-components

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.cfSubheadline)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

struct PreferenceRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: .cfSpacing16) {
                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text(title)
                        .font(.cfHeadline)
                        .foregroundStyle(Color.cfLabel)
                    Text(subtitle)
                        .font(.cfFootnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.cfAccent : Color.cfSecondaryLabel)
                    .accessibilityHidden(true)
            }
            .padding(.cfSpacing16)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: .cfRadius12))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var rowBackground: some ShapeStyle {
        isSelected
            ? AnyShapeStyle(Color.cfAccent.opacity(0.08))
            : AnyShapeStyle(Color.cfSecondaryBackground)
    }
}

// MARK: - Previews

#Preview("Reading Prefs — light") {
    OnboardingFlowPreviewContainer(step: .readingPrefs)
}

#Preview("Reading Prefs — dark") {
    OnboardingFlowPreviewContainer(step: .readingPrefs)
        .preferredColorScheme(.dark)
}

#Preview("Reading Prefs — XXL type") {
    OnboardingFlowPreviewContainer(step: .readingPrefs)
        .dynamicTypeSize(.accessibility3)
}
