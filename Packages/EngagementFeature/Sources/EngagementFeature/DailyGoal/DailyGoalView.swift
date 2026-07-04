import SwiftUI
import DesignSystem
import CoreKit

/// The daily-goal & habit surface.
///
/// Shows a large progress ring for today's reading minutes vs the user's
/// daily goal, a seven-day activity bar for the current week, a calm nudge
/// message, and a button to adjust the goal (which persists immediately).
///
/// Mount this view wherever a habit check-in is needed (home tab, engagement
/// tab). Supply a ``DailyGoalModel`` via the initializer.
public struct DailyGoalView: View {
    private let model: DailyGoalModel

    @State private var showGoalPicker = false

    public init(model: DailyGoalModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.loadState {
            case .loading:
                skeletonView
            case .loaded(let state):
                loadedView(state)
            case .error(let error):
                errorView(error)
            }
        }
        .navigationTitle("Today's Goal")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .background(Color.cfGroupedBackground.ignoresSafeArea())
        .task { model.load() }
        .sheet(isPresented: $showGoalPicker) {
            GoalPickerSheet(
                currentGoal: model.goalMinutes,
                onSelect: { minutes in
                    model.setGoal(minutes)
                    showGoalPicker = false
                }
            )
        }
    }

    // MARK: - Loaded

    private func loadedView(_ state: DailyGoalState) -> some View {
        ScrollView {
            VStack(spacing: .cfSpacing24) {
                ringSection(state)
                weekSection(state)
                nudgeSection(state)
                adjustGoalButton
            }
            .padding(.cfSpacing16)
        }
        .refreshable { await model.refresh() }
        .animation(.easeInOut(duration: 0.25), value: model.isRefreshing)
    }

    // MARK: - Ring section

    private func ringSection(_ state: DailyGoalState) -> some View {
        CFCard {
            VStack(spacing: .cfSpacing16) {
                ZStack {
                    CFProgressRing(progress: state.goalFraction, lineWidth: 12)
                        .frame(width: 160, height: 160)
                        .accessibilityHidden(true)

                    VStack(spacing: .cfSpacing4) {
                        Text("\(state.todayMinutes)")
                            .font(.cfLargeTitle)
                            .foregroundStyle(state.isGoalMet ? Color.green : Color.cfAccent)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: state.todayMinutes)
                        Text("of \(state.goalMinutes) min")
                            .font(.cfCaption)
                            .foregroundStyle(Color.cfTertiaryLabel)
                    }
                }

                if state.isGoalMet {
                    Label("Daily goal complete!", systemImage: "checkmark.circle.fill")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, .cfSpacing8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Today's reading: \(state.todayMinutes) of \(state.goalMinutes) minutes. " +
            "\(Int(state.goalFraction * 100)) percent complete." +
            (state.isGoalMet ? " Daily goal complete." : "")
        )
    }

    // MARK: - Week section

    private func weekSection(_ state: DailyGoalState) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Label("This Week", systemImage: "calendar")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            CFCard {
                HStack(spacing: 0) {
                    ForEach(state.weekActivity, id: \.date) { day in
                        DayActivityPill(day: day)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, .cfSpacing4)
            }
        }
    }

    // MARK: - Nudge

    private func nudgeSection(_ state: DailyGoalState) -> some View {
        Text(state.nudgeMessage)
            .font(.cfSubheadline)
            .foregroundStyle(Color.cfSecondaryLabel)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, .cfSpacing8)
    }

    // MARK: - Adjust-goal button

    private var adjustGoalButton: some View {
        Button {
            showGoalPicker = true
        } label: {
            Label("Adjust Daily Goal", systemImage: "slider.horizontal.3")
                .font(.cfBody)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Adjust your daily reading goal, currently \(model.goalMinutes) minutes")
    }

    // MARK: - Skeleton

    private var skeletonView: some View {
        VStack(spacing: .cfSpacing24) {
            CFSkeleton(Circle())
                .frame(width: 172, height: 172)
            CFSkeleton()
                .frame(height: 88)
                .padding(.horizontal, .cfSpacing16)
            CFSkeleton()
                .frame(height: 20)
                .frame(maxWidth: 220)
        }
        .padding(.cfSpacing16)
    }

    // MARK: - Error

    private func errorView(_ error: AppError) -> some View {
        VStack(spacing: .cfSpacing16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.cfLargeTitle)
                .foregroundStyle(Color.cfTertiaryLabel)
            Text(error.errorDescription ?? "Something went wrong.")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
            Button("Try Again") { model.load() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(.cfSpacing24)
    }
}

// MARK: - DayActivityPill

private struct DayActivityPill: View {
    let day: DailyGoalDay

    var body: some View {
        VStack(spacing: .cfSpacing4) {
            Text(day.dayLabel)
                .font(.cfCaption2)
                .foregroundStyle(day.isToday ? Color.cfLabel : Color.cfTertiaryLabel)
                .fontWeight(day.isToday ? .semibold : .regular)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: .cfRadius4)
                    .fill(Color.cfFill)
                    .frame(width: 24, height: 36)

                RoundedRectangle(cornerRadius: .cfRadius4)
                    .fill(barColor(for: day))
                    .frame(width: 24, height: max(4, 36 * day.fraction))
                    .animation(.easeInOut(duration: 0.4), value: day.fraction)
            }

            if day.isToday {
                Circle()
                    .fill(Color.cfAccent)
                    .frame(width: 4, height: 4)
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
    }

    private func barColor(for day: DailyGoalDay) -> Color {
        if day.isGoalMet { return .green }
        if day.hasActivity { return Color.cfAccent }
        return Color.cfFill
    }
}

// MARK: - GoalPickerSheet

private struct GoalPickerSheet: View {
    let currentGoal: Int
    let onSelect: (Int) -> Void

    @State private var selected: Int
    @Environment(\.dismiss) private var dismiss

    init(currentGoal: Int, onSelect: @escaping (Int) -> Void) {
        self.currentGoal = currentGoal
        self.onSelect = onSelect
        self._selected = State(initialValue: currentGoal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Daily reading goal", selection: $selected) {
                        ForEach(DailyGoalStore.options, id: \.self) { mins in
                            Text("\(mins) min").tag(mins)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.wheel)
                    #endif
                    .frame(height: 160)
                } header: {
                    Text("How many minutes do you want to read each day?")
                        .font(.cfSubheadline)
                        .textCase(nil)
                }

                Section {
                    Text("Your daily goal builds a consistent reading habit. Adjust it whenever your schedule changes.")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
            }
            .navigationTitle("Daily Goal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSelect(selected) }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Previews

// Fixture has todayReadingMinutes: 25 — vary goal to show different ring states.

@MainActor
private func previewModel(goal: Int, repo: EngagementRepository = .preview) -> DailyGoalModel {
    // Each preview uses an isolated UserDefaults suite so they don't share state.
    let store = DailyGoalStore(defaults: UserDefaults(suiteName: "preview.dailygoal.\(goal)"))
    store.dailyGoalMinutes = goal
    return DailyGoalModel(repository: repo, store: store)
}

#Preview("Daily Goal — in progress (light)") {
    // 25 of 30 min = 83 %
    NavigationStack {
        DailyGoalView(model: previewModel(goal: 30))
    }
}

#Preview("Daily Goal — goal met (dark)") {
    // 25 of 20 min = 100 %
    NavigationStack {
        DailyGoalView(model: previewModel(goal: 20))
    }
    .preferredColorScheme(.dark)
}

#Preview("Daily Goal — early in the day") {
    // 25 of 60 min = 42 %
    NavigationStack {
        DailyGoalView(model: previewModel(goal: 60))
    }
}

#Preview("Daily Goal — XXL text") {
    // 25 of 30 min, large Dynamic Type
    NavigationStack {
        DailyGoalView(model: previewModel(goal: 30))
    }
    .dynamicTypeSize(.accessibility3)
}
