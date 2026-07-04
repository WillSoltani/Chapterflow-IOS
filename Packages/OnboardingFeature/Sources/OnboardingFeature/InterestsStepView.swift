import SwiftUI
import DesignSystem

// MARK: - Interests step

struct InterestsStepView: View {
    @Bindable var model: OnboardingModel
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            stepHeader(
                icon: "sparkles",
                title: "What do you\nwant to explore?",
                subtitle: "Pick topics you're curious about — we'll surface the right books."
            )
            .padding(.top, .cfSpacing48)

            ScrollView {
                LazyVGrid(columns: columns, spacing: .cfSpacing12) {
                    ForEach(defaultInterestCategories) { category in
                        InterestChip(
                            category: category,
                            isSelected: model.selectedInterestIds.contains(category.id)
                        ) {
                            toggleInterest(category.id)
                        }
                    }
                }
                .padding(.horizontal, .cfSpacing20)
                .padding(.top, .cfSpacing24)
                .padding(.bottom, .cfSpacing20)
            }

            Spacer(minLength: 0)

            continueButton(
                label: "Continue",
                isEnabled: !model.selectedInterestIds.isEmpty
            ) {
                Task { await model.advance() }
            }
            .padding(.horizontal, .cfSpacing24)
            .padding(.bottom, .cfSpacing40)
        }
    }

    private func toggleInterest(_ id: String) {
        if model.selectedInterestIds.contains(id) {
            model.selectedInterestIds.remove(id)
        } else {
            model.selectedInterestIds.insert(id)
        }
    }
}

// MARK: - Interest chip

private struct InterestChip: View {
    let category: InterestCategory
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: .cfSpacing8) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .accessibilityHidden(true)
                Text(category.title)
                    .font(.cfSubheadline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, .cfSpacing12)
            .padding(.horizontal, .cfSpacing12)
            .background(chipBackground, in: RoundedRectangle(cornerRadius: .cfRadius12))
            .overlay(
                RoundedRectangle(cornerRadius: .cfRadius12)
                    .strokeBorder(chipBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .foregroundStyle(isSelected ? Color.cfAccent : Color.cfLabel)
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var chipBackground: some ShapeStyle {
        isSelected
            ? AnyShapeStyle(Color.cfAccent.opacity(0.1))
            : AnyShapeStyle(Color.cfSecondaryBackground)
    }

    private var chipBorder: some ShapeStyle {
        isSelected
            ? AnyShapeStyle(Color.cfAccent.opacity(0.6))
            : AnyShapeStyle(Color.cfSeparator)
    }
}

// MARK: - Previews

#Preview("Interests — light") {
    OnboardingFlowPreviewContainer(step: .interests)
}

#Preview("Interests — dark") {
    OnboardingFlowPreviewContainer(step: .interests)
        .preferredColorScheme(.dark)
}

#Preview("Interests — XXL type") {
    OnboardingFlowPreviewContainer(step: .interests)
        .dynamicTypeSize(.accessibility3)
}
