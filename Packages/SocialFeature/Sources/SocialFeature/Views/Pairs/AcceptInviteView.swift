import SwiftUI
import DesignSystem
import CoreKit

/// Manual invite-code entry + acceptance screen.
///
/// **Critical**: iOS has no deferred deep linking, so a brand-new user who
/// follows the Universal Link through an App Store install loses the code.
/// This screen is the authoritative fallback — the user types or pastes the
/// code and taps "Accept".
///
/// It can also be shown pre-filled when the app receives the deep link while
/// already installed (the code is extracted from the URL and injected via
/// ``PairsView``).
public struct AcceptInviteView: View {

    private let model: PairsModel

    @State private var code: String
    @State private var acceptedPair: ReadingPair?
    @State private var showSuccess = false
    @Environment(\.dismiss) private var dismiss

    public init(model: PairsModel, initialCode: String) {
        self.model = model
        _code = State(initialValue: initialCode)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: .cfSpacing32) {
                headerSection
                codeEntrySection
                if let error = model.operationError {
                    errorBanner(error)
                }
                acceptButton
                manualHint
            }
            .padding(.horizontal, .cfSpacing24)
            .padding(.vertical, .cfSpacing32)
        }
        .background(Color.cfGroupedBackground)
        .navigationTitle("Accept Invite")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $showSuccess) {
            successSheet
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: "person.2.badge.gearshape")
                .font(.system(size: 44))
                .foregroundStyle(Color.cfAccent)

            VStack(spacing: .cfSpacing8) {
                Text("Accept a Partner Invite")
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfLabel)
                    .multilineTextAlignment(.center)

                Text("Enter the invite code your reading partner shared with you.")
                    .font(.cfBody)
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Code entry

    private var codeEntrySection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Text("Invite Code")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)

            TextField("e.g. ABCD-1234", text: $code)
                .font(.cfBody.monospaced())
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
                .autocorrectionDisabled()
                .padding(.cfSpacing12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius12))
                .accessibilityLabel("Invite code text field")
                .onChange(of: code) { _, newValue in
                    if model.operationError != nil {
                        model.operationError = nil
                    }
                    code = newValue.uppercased()
                }
        }
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: .cfSpacing12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: .cfRadius12))
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - Accept button

    private var acceptButton: some View {
        Button {
            Task { await performAccept() }
        } label: {
            HStack(spacing: .cfSpacing8) {
                if model.isAccepting {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(model.isAccepting ? "Accepting…" : "Accept Invite")
                    .font(.cfHeadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.cfSpacing16)
            .background(
                isAcceptEnabled ? Color.cfAccent : Color.cfFill,
                in: RoundedRectangle(cornerRadius: .cfRadius12)
            )
            .foregroundStyle(isAcceptEnabled ? .white : Color.cfSecondaryLabel)
        }
        .disabled(!isAcceptEnabled)
        .accessibilityLabel("Accept reading partner invite")
    }

    private var isAcceptEnabled: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isAccepting
    }

    // MARK: - Manual hint

    private var manualHint: some View {
        VStack(spacing: .cfSpacing8) {
            Text("Don't have a code?")
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)
            Text("Ask your reading partner to send you their invite link or code.")
                .font(.cfCaption)
                .foregroundStyle(Color.cfTertiaryLabel)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Success sheet

    private var successSheet: some View {
        VStack(spacing: .cfSpacing24) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.cfAccent)

            VStack(spacing: .cfSpacing8) {
                Text("You're Now Partners!")
                    .font(.cfTitle2)
                    .foregroundStyle(Color.cfLabel)

                if let pair = acceptedPair {
                    Text("You and \(pair.partnerDisplayName ?? "your partner") can now see each other's progress.")
                        .font(.cfBody)
                        .foregroundStyle(Color.cfSecondaryLabel)
                        .multilineTextAlignment(.center)
                }
            }

            Button("Done") {
                showSuccess = false
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.cfAccent)
        }
        .padding(.cfSpacing32)
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func performAccept() async {
        do {
            let pair = try await model.acceptInvite(code: code)
            acceptedPair = pair
            showSuccess = true
        } catch let appError as AppError {
            model.operationError = appError.errorDescription ?? appError.code
        } catch {
            model.operationError = error.localizedDescription
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("AcceptInviteView — empty") {
    NavigationStack {
        AcceptInviteView(
            model: PairsModel(repository: FakeSocialRepository.loaded),
            initialCode: ""
        )
    }
}

#Preview("AcceptInviteView — pre-filled (deep link)") {
    NavigationStack {
        AcceptInviteView(
            model: PairsModel(repository: FakeSocialRepository.loaded),
            initialCode: "ABCD-1234"
        )
    }
}

#Preview("AcceptInviteView — dark") {
    NavigationStack {
        AcceptInviteView(
            model: PairsModel(repository: FakeSocialRepository.loaded),
            initialCode: ""
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("AcceptInviteView — XXL text") {
    NavigationStack {
        AcceptInviteView(
            model: PairsModel(repository: FakeSocialRepository.loaded),
            initialCode: ""
        )
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
