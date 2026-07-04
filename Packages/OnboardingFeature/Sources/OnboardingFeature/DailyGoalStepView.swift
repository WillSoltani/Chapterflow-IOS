import SwiftUI
import DesignSystem
import Persistence

// MARK: - Daily goal step

struct DailyGoalStepView: View {
    @Bindable var model: OnboardingModel

    @State private var reminderDate: Date = {
        var components = DateComponents()
        components.hour = 20
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }()

    var body: some View {
        VStack(spacing: 0) {
            stepHeader(
                icon: "target",
                title: "Set your\ndaily goal",
                subtitle: "Consistency builds knowledge. How many minutes can you commit to each day?"
            )
            .padding(.top, .cfSpacing48)

            ScrollView {
                VStack(spacing: .cfSpacing32) {
                    minutesSection
                    reminderSection
                }
                .padding(.horizontal, .cfSpacing24)
                .padding(.top, .cfSpacing24)
                .padding(.bottom, .cfSpacing20)
            }

            Spacer(minLength: 0)

            continueButton(label: "Continue", isEnabled: true) {
                applyReminderDate()
                Task { await model.advance() }
            }
            .padding(.horizontal, .cfSpacing24)
            .padding(.bottom, .cfSpacing40)
        }
        .onAppear {
            var c = DateComponents()
            c.hour = model.reminderHour
            c.minute = model.reminderMinute
            reminderDate = Calendar.current.date(from: c) ?? reminderDate
        }
    }

    // MARK: Sections

    private var minutesSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing16) {
            SectionLabel(text: "Minutes per day")

            HStack(spacing: .cfSpacing12) {
                ForEach(DailyGoalStore.tiers, id: \.self) { tier in
                    GoalTileButton(
                        minutes: tier,
                        isSelected: model.dailyGoalMinutes == tier
                    ) {
                        model.dailyGoalMinutes = tier
                    }
                }
            }
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            SectionLabel(text: "Daily reminder")

            HStack {
                VStack(alignment: .leading, spacing: .cfSpacing4) {
                    Text("Remind me at")
                        .font(.cfHeadline)
                    Text("We'll send a gentle nudge to keep your streak.")
                        .font(.cfFootnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                DatePicker(
                    "",
                    selection: $reminderDate,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .onChange(of: reminderDate) { _, newValue in
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    model.reminderHour = comps.hour ?? 20
                    model.reminderMinute = comps.minute ?? 0
                }
                .accessibilityLabel("Daily reminder time")
            }
            .padding(.cfSpacing16)
            .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius12))
        }
    }

    // MARK: Private

    private func applyReminderDate() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderDate)
        model.reminderHour = comps.hour ?? 20
        model.reminderMinute = comps.minute ?? 0
    }
}

// MARK: - Goal tile button

private struct GoalTileButton: View {
    let minutes: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: .cfSpacing4) {
                Text("\(minutes)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.cfAccent : Color.cfLabel)
                Text("min")
                    .font(.cfSubheadline)
                    .foregroundStyle(isSelected ? Color.cfAccent : Color.cfSecondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, .cfSpacing20)
            .background(tileBackground, in: RoundedRectangle(cornerRadius: .cfRadius16))
            .overlay(
                RoundedRectangle(cornerRadius: .cfRadius16)
                    .strokeBorder(
                        isSelected ? Color.cfAccent.opacity(0.7) : Color.cfSeparator,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityLabel("\(minutes) minutes per day")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var tileBackground: some ShapeStyle {
        isSelected
            ? AnyShapeStyle(Color.cfAccent.opacity(0.08))
            : AnyShapeStyle(Color.cfSecondaryBackground)
    }
}

// MARK: - Previews

#Preview("Daily Goal — light") {
    OnboardingFlowPreviewContainer(step: .dailyGoal)
}

#Preview("Daily Goal — dark") {
    OnboardingFlowPreviewContainer(step: .dailyGoal)
        .preferredColorScheme(.dark)
}

#Preview("Daily Goal — XXL type") {
    OnboardingFlowPreviewContainer(step: .dailyGoal)
        .dynamicTypeSize(.accessibility3)
}
