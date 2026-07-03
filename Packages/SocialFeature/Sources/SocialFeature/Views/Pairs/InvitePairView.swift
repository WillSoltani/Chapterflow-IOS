import SwiftUI
import DesignSystem
import CoreKit

/// Generates a reading-partner invite and lets the user share it.
///
/// Calls `POST /book/me/pairs/invite` on appear, then surfaces the resulting
/// Universal Link via `ShareLink` and the raw invite code as a copyable fallback.
public struct InvitePairView: View {

    private let repository: any SocialRepository

    @State private var invite: PairInvite?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    public init(repository: any SocialRepository) {
        self.repository = repository
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: .cfSpacing32) {
                headerSection
                inviteContent
            }
            .padding(.horizontal, .cfSpacing24)
            .padding(.vertical, .cfSpacing32)
        }
        .background(Color.cfGroupedBackground)
        .navigationTitle("Invite a Partner")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .task { await generateInvite() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.cfAccent)

            VStack(spacing: .cfSpacing8) {
                Text("Invite a Reading Partner")
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfLabel)
                    .multilineTextAlignment(.center)

                Text("Share the link below. Once they accept, you'll see each other's streaks and progress.")
                    .font(.cfBody)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Invite content

    @ViewBuilder
    private var inviteContent: some View {
        if isLoading {
            VStack(spacing: .cfSpacing16) {
                ProgressView()
                Text("Generating invite…")
                    .font(.cfBody)
                    .foregroundStyle(Color.cfSecondaryLabel)
            }
            .frame(maxWidth: .infinity)
        } else if let error = errorMessage {
            VStack(spacing: .cfSpacing16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.cfLargeTitle)
                    .foregroundStyle(Color.cfSecondaryLabel)
                Text(error)
                    .font(.cfBody)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await generateInvite() }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let invite = invite {
            inviteCard(invite)
        }
    }

    private func inviteCard(_ invite: PairInvite) -> some View {
        VStack(spacing: .cfSpacing20) {
            // Share button (Universal Link)
            if let url = URL(string: invite.inviteLink) {
                ShareLink(
                    item: url,
                    subject: Text("Join me on ChapterFlow"),
                    message: Text("Use my invite link to become reading partners!"),
                    label: {
                        HStack(spacing: .cfSpacing8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Invite Link")
                                .font(.cfHeadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.cfSpacing16)
                        .background(Color.cfAccent, in: RoundedRectangle(cornerRadius: .cfRadius12))
                        .foregroundStyle(.white)
                    }
                )
                .accessibilityLabel("Share reading partner invite link")
            }

            // Invite code for manual entry
            VStack(spacing: .cfSpacing12) {
                Text("Or share the code")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfSecondaryLabel)

                codeCard(invite.code)
            }

            // Expiry
            if let expiresAt = invite.expiresAt, let date = parseDate(expiresAt) {
                Text("Expires \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.cfCaption)
                    .foregroundStyle(Color.cfTertiaryLabel)
            }

            // Generate a fresh invite
            Button("Generate New Code") {
                Task { await generateInvite() }
            }
            .font(.cfCaption)
            .foregroundStyle(Color.cfSecondaryLabel)
            .accessibilityLabel("Generate a new invite code")
        }
    }

    private func codeCard(_ code: String) -> some View {
        HStack {
            Text(code)
                .font(.cfTitle3.monospaced())
                .foregroundStyle(Color.cfLabel)
                .tracking(4)

            Spacer()

            Button {
                #if os(iOS)
                UIPasteboard.general.string = code
                #endif
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(Color.cfAccent)
            }
            .accessibilityLabel("Copy invite code")
        }
        .padding(.cfSpacing16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius12))
    }

    // MARK: - Actions

    private func generateInvite() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            invite = try await repository.createInvite()
        } catch let appError as AppError {
            errorMessage = appError.errorDescription ?? appError.code
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func parseDate(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("InvitePairView — loaded") {
    NavigationStack {
        InvitePairView(repository: FakeSocialRepository.loaded)
    }
}

#Preview("InvitePairView — dark") {
    NavigationStack {
        InvitePairView(repository: FakeSocialRepository.loaded)
    }
    .preferredColorScheme(.dark)
}

#Preview("InvitePairView — error") {
    NavigationStack {
        InvitePairView(repository: FakeSocialRepository.errored)
    }
}

#Preview("InvitePairView — XXL text") {
    NavigationStack {
        InvitePairView(repository: FakeSocialRepository.loaded)
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
