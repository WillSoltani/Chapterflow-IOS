import SwiftUI
import DesignSystem

/// A sheet for editing the user's display name (and future editable fields).
///
/// Calls `ProfileModel.saveDisplayName()` on save; dismisses on success or cancel.
public struct EditProfileView: View {

    @Bindable private var model: ProfileModel
    @Environment(\.dismiss) private var dismiss

    public init(model: ProfileModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display name", text: $model.editDisplayName)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Display name")
                } header: {
                    Text("Display Name")
                } footer: {
                    Text("This is how your name appears to reading partners.")
                        .font(.cfCaption)
                }

                if let error = model.saveError {
                    Section {
                        Text(error)
                            .font(.cfFootnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await model.saveDisplayName()
                            if model.saveError == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.isSaving || model.editDisplayName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .overlay {
                        if model.isSaving {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#if DEBUG
#Preview("EditProfileView") {
    let model = ProfileModel(repository: FakeSocialRepository.loaded)
    model.editDisplayName = "Alice Reader"

    return EditProfileView(model: model)
}
#endif
