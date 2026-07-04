import SwiftUI
import DesignSystem

// MARK: - Welcome step

struct WelcomeStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: .cfSpacing48)

            heroSection

            Spacer()

            valueProps

            Spacer()

            actions
                .padding(.horizontal, .cfSpacing24)
                .padding(.bottom, .cfSpacing40)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Sections

    private var heroSection: some View {
        VStack(spacing: .cfSpacing24) {
            Image(systemName: "book.open.fill")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Color.cfAccent)
                .accessibilityHidden(true)

            VStack(spacing: .cfSpacing12) {
                Text("Learn More From\nEvery Book")
                    .font(.cfLargeTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("ChapterFlow turns non-fiction into a personal\nlearning experience — at your depth, your pace.")
                    .font(.cfBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, .cfSpacing32)
    }

    private var valueProps: some View {
        VStack(alignment: .leading, spacing: .cfSpacing16) {
            ValuePropRow(
                icon: "brain",
                text: "AI insights tailored to your reading depth"
            )
            ValuePropRow(
                icon: "chart.line.uptrend.xyaxis",
                text: "Track progress chapter by chapter"
            )
            ValuePropRow(
                icon: "bell.badge",
                text: "Daily reminders to keep your streak alive"
            )
        }
        .padding(.horizontal, .cfSpacing32)
    }

    private var actions: some View {
        VStack(spacing: .cfSpacing12) {
            Button {
                Task { await model.advance() }
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .accessibilityLabel("Get Started — begin onboarding")

            Button {
                Task { await model.skip() }
            } label: {
                Text("Skip setup")
                    .font(.cfFootnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Skip setup — jump straight to the app")
        }
    }
}

// MARK: - Value prop row

private struct ValuePropRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: .cfSpacing16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.cfAccent)
                .frame(width: .cfIconMedium)
                .accessibilityHidden(true)

            Text(text)
                .font(.cfCallout)
                .foregroundStyle(Color.cfLabel)
        }
    }
}

// MARK: - Preview

#Preview("Welcome — light") {
    OnboardingFlowPreviewContainer(step: .welcome)
}

#Preview("Welcome — dark") {
    OnboardingFlowPreviewContainer(step: .welcome)
        .preferredColorScheme(.dark)
}

#Preview("Welcome — XXL type") {
    OnboardingFlowPreviewContainer(step: .welcome)
        .dynamicTypeSize(.accessibility3)
}
