import SwiftUI
import DesignSystem

/// Fallback screen for manually entering a referral code after first launch.
///
/// iOS has no deferred deep-link API, so a referral link that takes a new user
/// through an App Store install cannot carry the code into the app automatically.
/// This view provides the manual attribution path: the user types or pastes the
/// code, and the server handles attribution.
///
/// When `initialCode` is non-empty (set by the referral deep-link handler), the
/// field is pre-filled so the user only has to confirm.
public struct EnterReferralCodeView: View {

    @Environment(\.dismiss) private var dismiss

    private let model: ReferralModel
    @State private var codeText: String
    @FocusState private var isFieldFocused: Bool

    public init(model: ReferralModel, initialCode: String = "") {
        self.model = model
        _codeText = State(initialValue: initialCode)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: .cfSpacing32) {
                    header
                    codeField
                    applyButton
                    if case .success(let msg) = model.applyPhase {
                        successBanner(message: msg)
                    }
                    if case .failure(let msg) = model.applyPhase {
                        errorBanner(message: msg)
                    }
                    pasteHint
                }
                .padding(.horizontal, .cfSpacing16)
                .padding(.vertical, .cfSpacing32)
            }
            .background(Color.cfGroupedBackground)
            .navigationTitle("Enter Referral Code")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.resetApplyPhase()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            isFieldFocused = codeText.isEmpty
        }
        .onChange(of: model.applyPhase) { _, newPhase in
            if case .success = newPhase {
                // Short delay so the user sees the success message, then close.
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    dismiss()
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: .cfSpacing12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.cfAccent)

            Text("Got a friend's code?")
                .font(.cfTitle2)
                .foregroundStyle(Color.cfLabel)
                .multilineTextAlignment(.center)

            Text("Enter the referral code your friend shared. Your friend earns a reward when you sign up, and you get credit for joining through their invite.")
                .font(.cfBody)
                .foregroundStyle(Color.cfSecondaryLabel)
                .multilineTextAlignment(.center)
        }
    }

    private var codeField: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Text("Referral Code")
                .font(.cfCaption)
                .foregroundStyle(Color.cfSecondaryLabel)

            codeTextField
        }
    }

    @ViewBuilder
    private var codeTextField: some View {
        let base = TextField("e.g. ALICE42", text: $codeText)
            .font(.system(.title3, design: .monospaced))
            .autocorrectionDisabled()
            .focused($isFieldFocused)
            .padding(.cfSpacing16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cfRadius12))
            .accessibilityLabel("Referral code")
            .onChange(of: codeText) { _, new in
                let cleaned = new.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
                if cleaned != new { codeText = cleaned }
                if case .failure = model.applyPhase { model.resetApplyPhase() }
            }
        #if os(iOS)
        base.textInputAutocapitalization(.characters)
        #else
        base
        #endif
    }

    private var applyButton: some View {
        Button {
            isFieldFocused = false
            Task { await model.applyCode(codeText) }
        } label: {
            Group {
                if case .submitting = model.applyPhase {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Apply Code")
                        .font(.cfHeadline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.cfSpacing16)
        }
        .buttonStyle(.borderedProminent)
        .disabled(codeText.trimmingCharacters(in: .whitespaces).isEmpty
                  || model.applyPhase == .submitting)
        .accessibilityLabel("Apply referral code")
    }

    private func successBanner(message: String) -> some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: .cfRadius12))
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: .cfSpacing8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
        }
        .padding(.cfSpacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: .cfRadius12))
    }

    private var pasteHint: some View {
        #if canImport(UIKit)
        Button {
            if let string = UIPasteboard.general.string, !string.isEmpty {
                codeText = string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            }
        } label: {
            Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                .font(.cfFootnote)
                .foregroundStyle(Color.cfAccent)
        }
        .accessibilityLabel("Paste referral code from clipboard")
        #else
        EmptyView()
        #endif
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Enter Code — empty") {
    EnterReferralCodeView(model: ReferralModel(repository: FakeSocialRepository.loaded))
}

#Preview("Enter Code — pre-filled") {
    EnterReferralCodeView(
        model: ReferralModel(repository: FakeSocialRepository.loaded),
        initialCode: "ALICE42"
    )
}

#Preview("Enter Code — dark") {
    EnterReferralCodeView(model: ReferralModel(repository: FakeSocialRepository.loaded))
        .preferredColorScheme(.dark)
}

#Preview("Enter Code — XXL text") {
    EnterReferralCodeView(model: ReferralModel(repository: FakeSocialRepository.loaded))
        .dynamicTypeSize(.accessibility3)
}
#endif
