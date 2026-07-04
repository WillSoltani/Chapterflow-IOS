import SwiftUI
import DesignSystem
import CoreKit

/// Privacy controls for the user's social presence.
///
/// Toggles govern what partners can see (streak, progress, books finished),
/// how the user's name appears, and participation in leaderboards/discovery.
/// Every toggle defaults to the privacy-RESPECTING option (sharing off).
/// Changes are saved to the server automatically via ``PrivacySettingsModel``.
public struct PrivacySettingsView: View {

    @State private var model: PrivacySettingsModel

    public init(settings: PrivacySettings, repository: any SocialRepository) {
        _model = State(initialValue: PrivacySettingsModel(settings: settings, repository: repository))
    }

    public var body: some View {
        Form {
            profileVisibilitySection
            identitySection
            socialSurfacesSection
            if case .error(let msg) = model.saveState {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.cfFootnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Privacy")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .status) {
                saveIndicator
            }
        }
    }

    // MARK: - Sections

    private var profileVisibilitySection: some View {
        Section {
            privacyToggle(
                title: "Show Reading Streak",
                subtitle: "Partners can see your current streak",
                systemImage: "flame",
                isOn: Binding(
                    get: { model.settings.showStreak },
                    set: { model.settings.showStreak = $0; Task { await model.save() } }
                )
            )
            privacyToggle(
                title: "Show Books Finished",
                subtitle: "Partners can see how many books you've completed",
                systemImage: "books.vertical",
                isOn: Binding(
                    get: { model.settings.showBooksFinished },
                    set: { model.settings.showBooksFinished = $0; Task { await model.save() } }
                )
            )
            privacyToggle(
                title: "Show Reading Progress",
                subtitle: "Partners can see your chapter-level progress",
                systemImage: "chart.bar",
                isOn: Binding(
                    get: { model.settings.showProgress },
                    set: { model.settings.showProgress = $0; Task { await model.save() } }
                )
            )
        } header: {
            Text("What Partners Can See")
        } footer: {
            Text("These settings control what a reading partner sees on your public profile. All fields are hidden by default.")
                .font(.cfCaption)
        }
    }

    private var identitySection: some View {
        Section {
            privacyToggle(
                title: "Use Display Name",
                subtitle: "Show your chosen display name instead of your account name",
                systemImage: "person.text.rectangle",
                isOn: Binding(
                    get: { model.settings.useDisplayName },
                    set: { model.settings.useDisplayName = $0; Task { await model.save() } }
                )
            )
        } header: {
            Text("Name Display")
        } footer: {
            Text("Your display name is what you set in Edit Profile. Turning this off would show your account name instead.")
                .font(.cfCaption)
        }
    }

    private var socialSurfacesSection: some View {
        Section {
            privacyToggle(
                title: "Leaderboards",
                subtitle: "Appear on reading leaderboards and rankings",
                systemImage: "trophy",
                isOn: Binding(
                    get: { model.settings.leaderboardOptIn },
                    set: { model.settings.leaderboardOptIn = $0; Task { await model.save() } }
                )
            )
            privacyToggle(
                title: "Discoverability",
                subtitle: "Allow others to find your profile via people search",
                systemImage: "magnifyingglass",
                isOn: Binding(
                    get: { model.settings.discoverabilityOptIn },
                    set: { model.settings.discoverabilityOptIn = $0; Task { await model.save() } }
                )
            )
        } header: {
            Text("Social Surfaces")
        } footer: {
            Text("Opting out removes you from leaderboards and search results immediately. Your existing reading partners are not affected.")
                .font(.cfCaption)
        }
    }

    // MARK: - Components

    private func privacyToggle(
        title: String,
        subtitle: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            Label {
                VStack(alignment: .leading, spacing: .cfSpacing2) {
                    Text(title)
                        .font(.cfBody)
                        .foregroundStyle(Color.cfLabel)
                    Text(subtitle)
                        .font(.cfCaption)
                        .foregroundStyle(Color.cfSecondaryLabel)
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.cfAccent)
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    @ViewBuilder
    private var saveIndicator: some View {
        switch model.saveState {
        case .saving:
            ProgressView()
                .scaleEffect(0.8)
        case .saved:
            Image(systemName: "checkmark")
                .font(.cfCaption)
                .foregroundStyle(Color.cfAccent)
        case .idle, .error:
            EmptyView()
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("PrivacySettings — defaults (all private)") {
    NavigationStack {
        PrivacySettingsView(
            settings: .default,
            repository: FakeSocialRepository.loaded
        )
    }
}

#Preview("PrivacySettings — some shared") {
    NavigationStack {
        PrivacySettingsView(
            settings: PrivacySettings(
                showStreak: true,
                showBooksFinished: false,
                showProgress: false,
                useDisplayName: true,
                leaderboardOptIn: true,
                discoverabilityOptIn: false
            ),
            repository: FakeSocialRepository.loaded
        )
    }
}

#Preview("PrivacySettings — dark mode") {
    NavigationStack {
        PrivacySettingsView(
            settings: .default,
            repository: FakeSocialRepository.loaded
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("PrivacySettings — XXL text") {
    NavigationStack {
        PrivacySettingsView(
            settings: .default,
            repository: FakeSocialRepository.loaded
        )
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
