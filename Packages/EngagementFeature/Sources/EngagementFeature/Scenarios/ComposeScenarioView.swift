import SwiftUI
import Models
import DesignSystem
import CoreKit

// MARK: - ComposeScenarioView

/// Modal sheet for composing and submitting a new real-world application scenario.
///
/// Validation runs inline as the user types. The submit button is disabled until
/// all fields are non-empty and within character limits. Points and status are
/// server-authoritative — never shown until after approval.
public struct ComposeScenarioView: View {

    private let model: ScenariosModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    // Local form state — passed to model.submitScenario() on submit
    @State private var title: String = ""
    @State private var scenario: String = ""
    @State private var whatToDo: String = ""
    @State private var whyItMatters: String = ""
    @State private var selectedScope: ScenarioScope = .work
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    private enum Field: Hashable {
        case title, scenario, whatToDo, whyItMatters
    }

    // MARK: Validation

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !scenario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !whatToDo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && {
            if case .unknown = selectedScope { return false }
            return true
        }()
    }

    private var hasAnyOverLimit: Bool {
        title.count > ScenariosModel.titleLimit
        || scenario.count > ScenariosModel.fieldLimit
        || whatToDo.count > ScenariosModel.fieldLimit
        || whyItMatters.count > ScenariosModel.fieldLimit
    }

    public init(model: ScenariosModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: .cfSpacing24) {
                    headerCard

                    scopePicker

                    composeFields

                    if let err = errorMessage {
                        Text(err)
                            .font(.cfSubheadline)
                            .foregroundStyle(Color(red: 0.80, green: 0.25, blue: 0.20))
                            .padding(.horizontal, .cfSpacing16)
                            .padding(.vertical, .cfSpacing12)
                            .background(
                                Color(red: 0.80, green: 0.25, blue: 0.20).opacity(0.08),
                                in: RoundedRectangle(cornerRadius: .cfRadius8)
                            )
                    }

                    submitButton
                }
                .padding(.cfSpacing20)
            }
            .navigationTitle("Apply It")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .background(Color.cfGroupedBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel scenario composition")
                }
            }
        }
    }

    // MARK: Header card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            Label("Make it real", systemImage: "lightbulb.fill")
                .font(.cfBody.weight(.semibold))
                .foregroundStyle(Color.cfAccent)
            Text("Describe a specific situation from your own life where you can apply what you just learned. Great applications are concrete, personal, and actionable.")
                .font(.cfSubheadline)
                .foregroundStyle(Color.cfSecondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.cfSpacing16)
        .background(Color.cfAccent.opacity(0.06), in: RoundedRectangle(cornerRadius: .cfRadius12))
    }

    // MARK: Scope picker

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: .cfSpacing8) {
            fieldLabel("Context")
            Picker("Scope", selection: $selectedScope) {
                Text("Work").tag(ScenarioScope.work)
                Text("School").tag(ScenarioScope.school)
                Text("Personal").tag(ScenarioScope.personal)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Compose fields

    private struct FieldConfig {
        let label: String
        let placeholder: String
        let limit: Int
        let focusField: Field
        let minHeight: CGFloat
    }

    private var composeFields: some View {
        VStack(alignment: .leading, spacing: .cfSpacing20) {
            fieldBlock(FieldConfig(
                label: "Headline",
                placeholder: "A short, memorable title for your scenario",
                limit: ScenariosModel.titleLimit,
                focusField: .title,
                minHeight: 44
            ), text: $title)

            fieldBlock(FieldConfig(
                label: "The Scenario",
                placeholder: "Describe a specific situation where you'll apply this…",
                limit: ScenariosModel.fieldLimit,
                focusField: .scenario,
                minHeight: 100
            ), text: $scenario)

            fieldBlock(FieldConfig(
                label: "What To Do",
                placeholder: "Concretely, what action will you take?",
                limit: ScenariosModel.fieldLimit,
                focusField: .whatToDo,
                minHeight: 80
            ), text: $whatToDo)

            fieldBlock(FieldConfig(
                label: "Why It Matters",
                placeholder: "Why does this application matter to you?",
                limit: ScenariosModel.fieldLimit,
                focusField: .whyItMatters,
                minHeight: 80
            ), text: $whyItMatters)
        }
    }

    @ViewBuilder
    private func fieldBlock(_ config: FieldConfig, text: Binding<String>) -> some View {
        let isOver = text.wrappedValue.count > config.limit
        VStack(alignment: .leading, spacing: .cfSpacing6) {
            fieldLabel(config.label)

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(config.placeholder)
                        .font(.cfBody)
                        .foregroundStyle(Color.cfTertiaryLabel)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(.cfBody)
                    .foregroundStyle(Color.cfLabel)
                    .focused($focusedField, equals: config.focusField)
                    .frame(minHeight: config.minHeight)
                    .scrollContentBackground(.hidden)
            }
            .padding(.cfSpacing12)
            .background(Color.cfSecondaryBackground, in: RoundedRectangle(cornerRadius: .cfRadius10))
            .overlay(
                RoundedRectangle(cornerRadius: .cfRadius10)
                    .stroke(
                        isOver
                            ? Color(red: 0.80, green: 0.25, blue: 0.20).opacity(0.5)
                            : Color.cfSeparator.opacity(0.3),
                        lineWidth: 1
                    )
            )

            HStack {
                if isOver {
                    Text("Over limit")
                        .font(.cfCaption2)
                        .foregroundStyle(Color(red: 0.80, green: 0.25, blue: 0.20))
                }
                Spacer()
                Text("\(text.wrappedValue.count) / \(config.limit)")
                    .font(.cfCaption2)
                    .foregroundStyle(isOver
                        ? Color(red: 0.80, green: 0.25, blue: 0.20)
                        : Color.cfTertiaryLabel
                    )
            }
        }
    }

    // MARK: Submit button

    private var submitButton: some View {
        let canSubmit = isFormValid && !hasAnyOverLimit && !isSubmitting
        return Button {
            Task { await submit() }
        } label: {
            HStack {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .padding(.trailing, .cfSpacing4)
                }
                Text(isSubmitting ? "Submitting…" : "Submit Scenario")
                    .font(.cfBody.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.cfSpacing16)
            .background(
                canSubmit ? Color.cfAccent : Color.cfSecondaryFill,
                in: RoundedRectangle(cornerRadius: .cfRadius12)
            )
            .foregroundStyle(canSubmit ? Color.white : Color.cfTertiaryLabel)
        }
        .disabled(!canSubmit)
        .accessibilityLabel("Submit scenario")
        .accessibilityHint(isFormValid ? "Double-tap to submit" : "Complete all fields to enable")
    }

    // MARK: Submit action

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        // Sync local state into model before calling submit
        model.title = title
        model.scenario = scenario
        model.whatToDo = whatToDo
        model.whyItMatters = whyItMatters
        model.selectedScope = selectedScope
        do {
            _ = try await model.submitScenario()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.cfCaption.weight(.semibold))
            .foregroundStyle(Color.cfAccent)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

// MARK: - Private CGFloat tokens

private extension CGFloat {
    static let cfSpacing6: CGFloat = 6
    static let cfSpacing20: CGFloat = 20
    static let cfRadius10: CGFloat = 10
}
