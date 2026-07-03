import SwiftUI
import DesignSystem
import Models
import CoreKit

// MARK: - SeasonalEventView

/// The seasonal-events screen.
///
/// Shows the active event (or an empty state when none is running), lets the
/// user join, tracks their daily + total progress, and displays a live countdown
/// to the event end using server time.
public struct SeasonalEventView: View {

    private let model: SeasonalEventModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: SeasonalEventModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.loadState {
            case .loading:
                loadingView
            case .loaded(let event, let progress):
                if let event {
                    loadedView(event: event, progress: progress)
                } else {
                    emptyView
                }
            case .error(let error):
                errorView(error)
            }
        }
        .navigationTitle("Events")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .background(Color.cfGroupedBackground.ignoresSafeArea())
        .task { model.load() }
        .refreshable { await model.refresh() }
    }

    // MARK: - Loaded

    private func loadedView(event: SeasonalEvent, progress: EventProgress?) -> some View {
        ScrollView {
            VStack(spacing: .cfSpacing20) {
                eventHeaderCard(event)

                if event.hasJoined, let progress {
                    progressSection(event: event, progress: progress)
                } else {
                    joinSection(event: event)
                }

                eventDetailsCard(event)
            }
            .padding(.cfSpacing16)
        }
    }

    // MARK: - Event header card

    private func eventHeaderCard(_ event: SeasonalEvent) -> some View {
        CFCard {
            VStack(alignment: .leading, spacing: .cfSpacing16) {
                // Title + badge icon row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: .cfSpacing4) {
                        Text(event.title)
                            .font(.cfTitle2)
                            .foregroundStyle(Color.cfLabel)

                        if let description = event.description {
                            Text(description)
                                .font(.cfBody)
                                .foregroundStyle(Color.cfSecondaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer()

                    if let badge = event.badge, let icon = badge.icon {
                        Text(icon)
                            .font(.system(size: 40))
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.cfAccent)
                            .accessibilityHidden(true)
                    }
                }

                Divider()

                // Countdown
                countdownRow(event)

                // Reward pills
                rewardPills(event)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Countdown row

    private func countdownRow(_ event: SeasonalEvent) -> some View {
        HStack(spacing: .cfSpacing12) {
            Image(systemName: "timer")
                .font(.cfSubheadline)
                .foregroundStyle(model.secondsRemaining > 0 ? Color.cfAccent : Color.cfTertiaryLabel)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: .cfSpacing2) {
                Text(model.secondsRemaining > 0 ? "Time remaining" : "Event ended")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfTertiaryLabel)

                Text(model.secondsRemaining > 0 ? model.countdownText : "—")
                    .font(.cfTitle3.monospacedDigit())
                    .foregroundStyle(
                        model.secondsRemaining < 3600
                            ? Color.orange
                            : Color.cfLabel
                    )
                    .contentTransition(.numericText(countsDown: true))
                    .animation(
                        reduceMotion ? .none : .linear(duration: 0.2),
                        value: model.countdownText
                    )
            }

            Spacer()
        }
        .accessibilityLabel(
            model.secondsRemaining > 0
                ? "Time remaining: \(model.countdownText)"
                : "Event has ended"
        )
    }

    // MARK: - Reward pills

    private func rewardPills(_ event: SeasonalEvent) -> some View {
        HStack(spacing: .cfSpacing8) {
            if event.bonusIp > 0 {
                rewardPill(
                    icon: "bolt.fill",
                    label: "+\(event.bonusIp) IP",
                    color: .yellow
                )
            }
            if let badge = event.badge {
                rewardPill(
                    icon: "medal.fill",
                    label: badge.name,
                    color: Color(red: 0.85, green: 0.65, blue: 0.15)
                )
            }
            Spacer()
        }
    }

    private func rewardPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: .cfSpacing4) {
            Image(systemName: icon)
                .font(.cfCaption2)
            Text(label)
                .font(.cfCaption.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, .cfSpacing8)
        .padding(.vertical, .cfSpacing4)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityLabel("\(label) reward")
    }

    // MARK: - Join section

    private func joinSection(event: SeasonalEvent) -> some View {
        CFCard {
            VStack(spacing: .cfSpacing16) {
                VStack(spacing: .cfSpacing8) {
                    Text("Ready to join?")
                        .font(.cfSubheadline.weight(.semibold))
                        .foregroundStyle(Color.cfLabel)
                    Text("Complete \(event.targetChapters) chapters before the event ends to earn your badge and bonus IP.")
                        .font(.cfBody)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    model.join()
                } label: {
                    HStack(spacing: .cfSpacing8) {
                        if model.isJoining {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.8)
                        }
                        Text(model.isJoining ? "Joining…" : "Join Event")
                            .font(.cfBody.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isJoining || model.secondsRemaining <= 0)
                .accessibilityLabel(model.isJoining ? "Joining event" : "Join event")
                .accessibilityHint("Join the \(event.title) challenge")
            }
        }
    }

    // MARK: - Progress section

    private func progressSection(event: SeasonalEvent, progress: EventProgress) -> some View {
        VStack(spacing: .cfSpacing12) {
            if progress.isCompleted {
                completedBanner(event: event)
            }

            CFCard {
                VStack(alignment: .leading, spacing: .cfSpacing16) {
                    // Total progress
                    progressRow(
                        label: "Total progress",
                        current: progress.chaptersCompleted,
                        target: event.targetChapters,
                        icon: "book.fill",
                        color: .cfAccent
                    )

                    Divider()

                    // Daily progress
                    progressRow(
                        label: "Today",
                        current: progress.dailyChaptersCompleted,
                        target: event.dailyTarget,
                        icon: "sun.max.fill",
                        color: .orange
                    )
                }
            }
        }
    }

    private func progressRow(
        label: String,
        current: Int,
        target: Int,
        icon: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.cfSubheadline.weight(.medium))
                    .foregroundStyle(Color.cfLabel)
                Spacer()
                Text("\(current) / \(target)")
                    .font(.cfSubheadline.monospacedDigit())
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: .cfRadius4)
                        .fill(Color.cfSecondaryFill)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: .cfRadius4)
                        .fill(color)
                        .frame(
                            width: geo.size.width * min(1, target > 0 ? Double(current) / Double(target) : 0),
                            height: 8
                        )
                        .animation(
                            reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8),
                            value: current
                        )
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(current) of \(target) chapters")
    }

    // MARK: - Completed banner

    private func completedBanner(event: SeasonalEvent) -> some View {
        HStack(spacing: .cfSpacing12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.cfTitle3)
                .foregroundStyle(Color.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: .cfSpacing2) {
                Text("Challenge complete!")
                    .font(.cfSubheadline.weight(.semibold))
                    .foregroundStyle(Color.green)
                if let badge = event.badge {
                    Text("You earned the \"\(badge.name)\" badge.")
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
            }
            Spacer()
        }
        .padding(.cfSpacing12)
        .background {
            RoundedRectangle(cornerRadius: .cfRadius12)
                .fill(Color.green.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: .cfRadius12)
                        .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
                }
        }
        .accessibilityLabel("Challenge complete. You earned the \(event.badge?.name ?? "event") badge.")
    }

    // MARK: - Event details card

    private func eventDetailsCard(_ event: SeasonalEvent) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Label("Event Details", systemImage: "info.circle")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            CFCard {
                VStack(spacing: 0) {
                    detailRow(
                        label: "Target",
                        value: "\(event.targetChapters) chapters",
                        icon: "target"
                    )
                    Divider().padding(.leading, .cfSpacing32 + .cfSpacing12)
                    detailRow(
                        label: "Daily pace",
                        value: "\(event.dailyTarget) chapter\(event.dailyTarget == 1 ? "" : "s") / day",
                        icon: "calendar"
                    )
                    Divider().padding(.leading, .cfSpacing32 + .cfSpacing12)
                    detailRow(
                        label: "Ends",
                        value: eventEndDateText(event),
                        icon: "clock"
                    )
                }
            }
        }
    }

    private func detailRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: .cfSpacing12) {
            Image(systemName: icon)
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfAccent)
                .frame(width: .cfSpacing20)
                .accessibilityHidden(true)
            Text(label)
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
            Spacer()
            Text(value)
                .font(.cfBody.weight(.medium))
                .foregroundStyle(Color.cfLabel)
        }
        .padding(.vertical, .cfSpacing12)
        .accessibilityLabel("\(label): \(value)")
    }

    private func eventEndDateText(_ event: SeasonalEvent) -> String {
        guard let date = JSONDecoder.chapterFlow.dateFromStringPublic(event.endsAt) else {
            return event.endsAt
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    // MARK: - Loading

    private var loadingView: some View {
        ScrollView {
            VStack(spacing: .cfSpacing20) {
                CFCard { CFSkeleton().frame(height: 180) }
                CFCard { CFSkeleton().frame(height: 120) }
                CFCard { CFSkeleton().frame(height: 100) }
            }
            .padding(.cfSpacing16)
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: .cfSpacing16) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(Color.cfTertiaryLabel)
                .accessibilityHidden(true)
            Text("No Active Event")
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)
            Text("Check back soon for the next seasonal challenge.")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.cfSpacing24)
    }

    // MARK: - Error

    private func errorView(_ error: AppError) -> some View {
        VStack(spacing: .cfSpacing16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.cfLargeTitle)
                .foregroundStyle(Color.cfTertiaryLabel)
                .accessibilityHidden(true)
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

// MARK: - JSONDecoder date helper (view-accessible)

extension JSONDecoder {
    func dateFromStringPublic(_ string: String) -> Date? {
        try? decode(SingleDateWrapper.self, from: Data("\"\(string)\"".utf8)).date
    }

    private struct SingleDateWrapper: Decodable {
        let date: Date
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            self.date = try c.decode(Date.self)
        }
    }
}

// MARK: - Previews

#Preview("Event — not joined (light)") {
    let presenter = CelebrationPresenter()
    let model = SeasonalEventModel(
        repository: .previewNotJoined,
        celebrationPresenter: presenter
    )
    return NavigationStack {
        SeasonalEventView(model: model)
    }
    .celebrationOverlay(presenter)
}

#Preview("Event — in progress (dark)") {
    let presenter = CelebrationPresenter()
    let model = SeasonalEventModel(
        repository: .previewInProgress,
        celebrationPresenter: presenter
    )
    return NavigationStack {
        SeasonalEventView(model: model)
    }
    .preferredColorScheme(.dark)
    .celebrationOverlay(presenter)
}

#Preview("Event — completed") {
    let presenter = CelebrationPresenter()
    let model = SeasonalEventModel(
        repository: .previewCompleted,
        celebrationPresenter: presenter
    )
    return NavigationStack {
        SeasonalEventView(model: model)
    }
    .celebrationOverlay(presenter)
}

#Preview("Event — none active") {
    let presenter = CelebrationPresenter()
    let model = SeasonalEventModel(
        repository: .previewNoEvent,
        celebrationPresenter: presenter
    )
    return NavigationStack {
        SeasonalEventView(model: model)
    }
}

#Preview("Event — XXL text") {
    let presenter = CelebrationPresenter()
    let model = SeasonalEventModel(
        repository: .previewInProgress,
        celebrationPresenter: presenter
    )
    return NavigationStack {
        SeasonalEventView(model: model)
    }
    .dynamicTypeSize(.accessibility3)
}
