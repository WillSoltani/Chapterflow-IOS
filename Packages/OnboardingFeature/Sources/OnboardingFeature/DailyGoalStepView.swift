import SwiftUI
import DesignSystem

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
                subtitle: "Reading a chapter a day adds up fast. How many can you commit to?"
            )
            .padding(.top, .cfSpacing48)

            ScrollView {
                VStack(spacing: .cfSpacing32) {
                    chaptersSection
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
            // Sync the date picker to whatever is stored in model
            var c = DateComponents()
            c.hour = model.reminderHour
            c.minute = model.reminderMinute
            reminderDate = Calendar.current.date(from: c) ?? reminderDate
        }
    }

    // MARK: Sections

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing16) {
            SectionLabel(text: "Chapters per day")

            HStack {
                Button {
                    if model.dailyGoalChapters > 1 { model.dailyGoalChapters -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(model.dailyGoalChapters > 1 ? Color.cfAccent : Color.cfSecondaryLabel)
                }
                .accessibilityLabel("Decrease goal")
                .disabled(model.dailyGoalChapters <= 1)

                Spacer()

                VStack(spacing: .cfSpacing4) {
                    Text("\(model.dailyGoalChapters)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.cfAccent)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: model.dailyGoalChapters)

                    Text(model.dailyGoalChapters == 1 ? "chapter" : "chapters")
                        .font(.cfSubheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(model.dailyGoalChapters) \(model.dailyGoalChapters == 1 ? "chapter" : "chapters") per day")

                Spacer()

                Button {
                    if model.dailyGoalChapters < 10 { model.dailyGoalChapters += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(model.dailyGoalChapters < 10 ? Color.cfAccent : Color.cfSecondaryLabel)
                }
                .accessibilityLabel("Increase goal")
                .disabled(model.dailyGoalChapters >= 10)
            }
            .padding(.vertical, .cfSpacing20)
            .padding(.horizontal, .cfSpacing24)
            .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius16))
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
