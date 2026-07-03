import SwiftUI
import DesignSystem
import Models
import CoreKit

// MARK: - CommitmentReflectionView

/// Full-screen sheet shown at follow-up time — prompts the user to reflect on
/// their commitment and select an outcome (helped / partly / didn't help).
///
/// On success the server marks the commitment `done` and updates the chapter's
/// application-axis badge (server-authoritative).
public struct CommitmentReflectionView: View {

    let commitment: Commitment
    private let model: CommitmentsModel

    @Environment(\.dismiss) private var dismiss

    @State private var selectedOutcome: CommitmentOutcome?
    @State private var reflectionText: String = ""
    @State private var errorMessage: String?
    @State private var isSubmitting: Bool = false

    private var canSubmit: Bool {
        selectedOutcome != nil && !reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(commitment: Commitment, model: CommitmentsModel) {
        self.commitment = commitment
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: .cfSpacing24) {
                    commitmentCard
                    outcomeSection
                    reflectionSection
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.cfFootnote)
                            .foregroundStyle(Color.red)
                            .multilineTextAlignment(.center)
                    }
                    submitButton
                }
                .padding(.cfSpacing16)
            }
            .background(Color.cfGroupedBackground.ignoresSafeArea())
            .navigationTitle("Commitment check-in")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                        .accessibilityLabel("Dismiss and reflect later")
                }
            }
        }
    }

    // MARK: - Commitment recap card

    private var commitmentCard: some View {
        CFCard {
            VStack(alignment: .leading, spacing: .cfSpacing12) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(Color.cfAccent)
                        .accessibilityHidden(true)
                    Text("Your commitment")
                        .font(.cfHeadline)
                        .foregroundStyle(Color.cfLabel)
                }
                Divider()
                labeledRow(label: "IF", value: commitment.ifStatement)
                labeledRow(label: "THEN", value: commitment.thenStatement)
            }
            .padding(.cfSpacing4)
        }
    }

    private func labeledRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing2) {
            Text(label)
                .font(.cfCaption2)
                .foregroundStyle(Color.cfAccent)
                .tracking(1.2)
            Text(value)
                .font(.cfBody)
                .foregroundStyle(Color.cfLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Outcome picker

    private var outcomeSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            Text("How did it go?")
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)

            VStack(spacing: .cfSpacing8) {
                ForEach([CommitmentOutcome.helped, .partly, .didnt], id: \.rawValue) { outcome in
                    OutcomeButton(
                        outcome: outcome,
                        isSelected: selectedOutcome == outcome,
                        onTap: { selectedOutcome = outcome }
                    )
                }
            }
        }
    }

    // MARK: - Reflection text

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Text("Reflect")
                .font(.cfTitle3)
                .foregroundStyle(Color.cfLabel)
            Text("What did you notice? What would you adjust?")
                .font(.cfFootnote)
                .foregroundStyle(Color.cfSecondaryLabel)

            TextEditor(text: $reflectionText)
                .frame(minHeight: 100)
                .padding(.cfSpacing8)
                .background(Color.cfSecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
                .font(.cfBody)
                .accessibilityLabel("Reflection text")
        }
    }

    // MARK: - Submit button

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            if isSubmitting {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            } else {
                Text("Submit reflection")
                    .font(.cfHeadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSubmit || isSubmitting)
        .accessibilityLabel("Submit reflection and outcome")
    }

    // MARK: - Submit

    private func submit() async {
        guard let outcome = selectedOutcome else { return }
        isSubmitting = true
        errorMessage = nil
        let trimmed = reflectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await model.submitReflection(
                commitmentId: commitment.id,
                reflection: trimmed,
                outcome: outcome
            )
            dismiss()
        } catch {
            isSubmitting = false
            errorMessage = "Failed to submit reflection. Please try again."
        }
    }
}

// MARK: - OutcomeButton

private struct OutcomeButton: View {

    let outcome: CommitmentOutcome
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: .cfSpacing12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : tintColor)
                    .frame(width: .cfIconSmall)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: .cfSpacing2) {
                    Text(title)
                        .font(.cfSubheadline)
                        .foregroundStyle(isSelected ? .white : Color.cfLabel)
                    Text(subtitle)
                        .font(.cfFootnote)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : Color.cfSecondaryLabel)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
            }
            .padding(.cfSpacing16)
            .background(isSelected ? tintColor : Color.cfSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: .cfRadius12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) — \(subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var icon: String {
        switch outcome {
        case .helped:  return "hand.thumbsup.fill"
        case .partly:  return "hand.thumbsup"
        case .didnt:   return "hand.thumbsdown"
        case .unknown: return "questionmark"
        }
    }

    private var title: String {
        switch outcome {
        case .helped:  return "It helped"
        case .partly:  return "Partly helped"
        case .didnt:   return "Didn't help"
        case .unknown: return "Unknown"
        }
    }

    private var subtitle: String {
        switch outcome {
        case .helped:  return "I applied it and it made a difference"
        case .partly:  return "I tried it but with mixed results"
        case .didnt:   return "It didn't fit or I couldn't apply it"
        case .unknown: return "Unknown outcome"
        }
    }

    private var tintColor: Color {
        switch outcome {
        case .helped:  return .green
        case .partly:  return .orange
        case .didnt:   return .red
        case .unknown: return Color.cfSecondaryLabel
        }
    }
}

// MARK: - Previews

#Preview("Reflection — light") {
    CommitmentReflectionView(
        commitment: Commitment.preview,
        model: CommitmentsModel.preview
    )
}

#Preview("Reflection — dark") {
    CommitmentReflectionView(
        commitment: Commitment.preview,
        model: CommitmentsModel.preview
    )
    .preferredColorScheme(.dark)
}

#Preview("Reflection — XXL") {
    CommitmentReflectionView(
        commitment: Commitment.preview,
        model: CommitmentsModel.preview
    )
    .dynamicTypeSize(.accessibility2)
}
