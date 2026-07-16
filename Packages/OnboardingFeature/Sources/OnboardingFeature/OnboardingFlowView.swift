import SwiftUI
import DesignSystem
import Persistence
import Networking
import CoreKit

// MARK: - Onboarding flow view

/// The first-run onboarding flow, presented full-screen immediately after sign-up.
///
/// Gates visibility on `AppPreferences.onboardingCompleted` — when the model sets
/// that flag, `AppRootView` automatically dismisses this cover.
public struct OnboardingFlowView: View {
    @State private var model: OnboardingModel

    public init(
        preferences: AppPreferences,
        repository: any OnboardingRepository,
        goalStore: DailyGoalStore,
        workPermit: SessionWorkPermit,
        analytics: any AnalyticsClient = NoopAnalyticsClient()
    ) {
        _model = State(initialValue: OnboardingModel(
            preferences: preferences,
            repository: repository,
            goalStore: goalStore,
            workPermit: workPermit,
            analytics: analytics
        ))
    }

    public var body: some View {
        ZStack {
            Color.cfBackground.ignoresSafeArea()

            stepView
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        }
        .animation(.easeInOut(duration: 0.35), value: model.currentStep)
        .overlay(alignment: .top) {
            if model.currentStep != .welcome {
                progressIndicator
                    .padding(.top, 56)
                    .transition(.opacity)
            }
        }
        .overlay {
            if model.isLoading {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .overlay(ProgressView())
            }
        }
        .interactiveDismissDisabled(true)
        .task { await model.loadProgress() }
        .accessibilityElement(children: .contain)
    }

    // MARK: Step content

    @ViewBuilder
    private var stepView: some View {
        switch model.currentStep {
        case .welcome:
            WelcomeStepView(model: model)
        case .interests:
            InterestsStepView(model: model)
        case .readingPrefs:
            ReadingPrefsStepView(model: model)
        case .dailyGoal:
            DailyGoalStepView(model: model)
        case .notifications:
            NotificationsStepView(model: model)
        case .completed:
            Color.clear
        }
    }

    // MARK: Progress dots

    private var progressIndicator: some View {
        HStack(spacing: .cfSpacing8) {
            ForEach(progressSteps, id: \.self) { step in
                Capsule()
                    .fill(step == model.currentStep ? Color.cfAccent : Color.cfSeparator)
                    .frame(width: step == model.currentStep ? 20 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: model.currentStep)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progressLabel)
    }

    private let progressSteps: [OnboardingStep] = [
        .interests, .readingPrefs, .dailyGoal, .notifications,
    ]

    private var progressLabel: String {
        guard let idx = progressSteps.firstIndex(of: model.currentStep) else { return "" }
        return "Step \(idx + 1) of \(progressSteps.count)"
    }
}

// MARK: - Shared button styles

/// The primary CTA button style used across all onboarding steps.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cfHeadline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, .cfSpacing16)
            .background(
                Color.cfAccent.opacity(configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: .cfRadius16)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Shared view helpers (used by step views)

/// Standard step header with icon, title, and subtitle.
func stepHeader(icon: String, title: String, subtitle: String) -> some View {
    VStack(spacing: .cfSpacing20) {
        Image(systemName: icon)
            .font(.system(size: 52, weight: .light))
            .foregroundStyle(Color.cfAccent)
            .accessibilityHidden(true)

        VStack(spacing: .cfSpacing8) {
            Text(title)
                .font(.cfTitle1)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.cfCallout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    .padding(.horizontal, .cfSpacing24)
}

/// Standard primary continue button used across onboarding steps.
func continueButton(
    label: String,
    isEnabled: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Text(label).frame(maxWidth: .infinity)
    }
    .buttonStyle(OnboardingPrimaryButtonStyle())
    .opacity(isEnabled ? 1 : 0.4)
    .disabled(!isEnabled)
    .animation(.easeInOut(duration: 0.2), value: isEnabled)
    .accessibilityLabel(label)
    .accessibilityHint(isEnabled ? "" : "Make a selection to continue")
}

// MARK: - Preview support

/// A preview container that starts the flow at a given step, using mock dependencies.
struct OnboardingFlowPreviewContainer: View {
    let step: OnboardingStep

    var body: some View {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "preview-onboarding")!)
        let repo = MockOnboardingRepository()
        let container = OnboardingFlowView(
            preferences: prefs,
            repository: repo,
            goalStore: DailyGoalStore(defaults: UserDefaults(suiteName: "preview-onboarding")!),
            workPermit: SessionWorkPermit()
        )
        container
    }
}

// MARK: - Previews

#Preview("Full Flow — light") {
    OnboardingFlowPreviewContainer(step: .welcome)
}

#Preview("Full Flow — dark") {
    OnboardingFlowPreviewContainer(step: .welcome)
        .preferredColorScheme(.dark)
}

#Preview("Full Flow — XXL type") {
    OnboardingFlowPreviewContainer(step: .welcome)
        .dynamicTypeSize(.accessibility3)
}
